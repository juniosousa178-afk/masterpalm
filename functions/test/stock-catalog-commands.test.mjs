import {applyOrderStockInTransaction, executeOrderStockCommand, orderStockOperationId} from '../src/stockCatalogOrders.js';
import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockProduct, runStockTransaction} from '../src/stockCatalogCommands.js';
const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
const db = new Firestore({projectId: 'demo-stock-catalog'});
after(() => db.terminate());
const runId = Date.now().toString(36);
let sequence = 0;
async function seed(product = {}) {
  const lojaId = `backend_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const stock = {quantidade: 1, stockKind: 'simple', stockRevision: 0, ...product};
  const batch = db.batch();
  batch.set(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
  batch.set(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true}});
  batch.set(base.collection('estoque_produtos').doc('p'), stock);
  batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Peça', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  await batch.commit();
  return {base, lojaId};
}
function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {protocolVersion: 1, lojaId, kind, operationId, items: [{productId: 'p', quantity: 1, ...item}], ...extra};
}
const owner = {uid: 'owner'};
async function state(base) {
  const [stock, live] = await Promise.all([base.collection('estoque_produtos').doc('p').get(), base.collection('produtos').doc('p').get()]);
  return {stock: stock.data(), live: live.exists ? live.data() : null};
}
async function denied(promise, code) { await assert.rejects(promise, e => e.code === code); }
test('real transaction simple {}: publish -> sale zero -> restock one', async () => {
  const {base, lojaId} = await seed({variacoes: {}});
  await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal((await state(base)).live.quantidade, 1);
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  let s = await state(base); assert.equal(s.stock.quantidade, 0); assert.equal(s.live, null);
  await executeStockCommand(db, intent(lojaId, 'restock', 'r1'), owner);
  s = await state(base); assert.equal(s.stock.quantidade, 1); assert.equal(s.live.quantidade, 1);
  assert.equal(s.live.catalogStockRevision, s.stock.stockRevision);
});
test('unauthenticated, self-promoted profile, cross-store are denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), null), 'unauthenticated');
  await db.collection('users').doc('intruder').set({role: 'admin', store_id: lojaId});
  await db.collection('usuarios').doc('intruder@example.test').set({tipo: 'admin'});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), {uid: 'intruder', token: {role: 'admin'}}), 'permission-denied');
  const other = await seed();
  await other.base.collection('stock_catalog_access').doc('owner').delete();
  await denied(executeStockCommand(db, intent(other.lojaId, 'sale', 's1'), owner), 'permission-denied');
});
test('concurrent sales limited stock: one succeeds, no negative', async () => {
  const {base, lojaId} = await seed();
  const results = await Promise.allSettled(['a','b'].map(id => executeStockCommand(db, intent(lojaId, 'sale', id), owner)));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const s = await state(base); assert.equal(s.stock.quantidade, 0); assert.equal(s.live, null);
});
test('concurrent retry identical intent decrements once; different payload conflicts', async () => {
  const {base, lojaId} = await seed({quantidade: 3});
  const command = intent(lojaId, 'sale', 'once');
  const results = await Promise.all([executeStockCommand(db, command, owner), executeStockCommand(db, command, owner)]);
  assert.equal(results.filter(r => r.alreadyApplied).length, 1);
  assert.equal((await state(base)).stock.quantidade, 2);
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 'once', {quantity: 2}), owner), 'already-exists');
});
test('revision CAS rejects stale zero after legitimate restock five', async () => {
  const {base, lojaId} = await seed({quantidade: 0});
  await executeStockCommand(db, intent(lojaId, 'restock', 'r', {quantity: 5}), owner);
  await denied(executeStockCommand(db, intent(lojaId, 'adjust', 'old', {quantity: 0, expectedRevision: 0}), owner), 'aborted');
  await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal((await state(base)).live.quantidade, 5);
});
for (const color of ['Azul', 'azul', 'AZUL', ' Azul ']) test(`variation real command: ${color}`, async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', variacoes: {P: {Azul: 1, Vermelho: 2}}, quantidade: 3});
  await executeStockCommand(db, intent(lojaId, 'sale', 's', {size: 'P', color}), owner);
  const s = await state(base);
  assert.equal(s.stock.variacoes.P.Azul, 0); assert.equal(s.stock.variacoes.P.Vermelho, 2);
  assert.equal(s.live.variacoes.P.Azul, 0); assert.equal(s.live.quantidade, 2);
});
test('restore references applied sale and cannot be repeated with another id', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, intent(lojaId, 'sale', 's'), owner);
  const restore = intent(lojaId, 'restore', 'restore', {}, {sourceOperationId: 's'});
  await executeStockCommand(db, restore, owner);
  await executeStockCommand(db, restore, owner);
  await denied(executeStockCommand(db, {...restore, operationId: 'different'}, owner), 'already-exists');
  assert.equal((await state(base)).stock.quantidade, 1);
});
test('missing data/capability and client-supplied stock/revision are rejected', async () => {
  const {base, lojaId} = await seed();
  const cmd = intent(lojaId, 'sale', 's');
  for (const field of ['stockRevision','available','stock']) await denied(executeStockCommand(db, {...cmd, [field]: 9}, owner), 'invalid-argument');
  await base.collection('estoque_produtos').doc('p').delete();
  await denied(executeStockCommand(db, cmd, owner), 'failed-precondition');
  // Absent control routes to inactive compat; without store membership → permission-denied.
  await base.collection('stock_catalog_control').doc('state').delete();
  await denied(executeStockCommand(db, cmd, owner), 'permission-denied');
});
test('non-stock editorial edit succeeds without accepting derived stock', async () => {
  const {base, lojaId} = await seed();
  const cmd = intent(lojaId, 'editorial', 'e', {}, {editorial: {descricao: 'Nova'}});
  await executeStockCommand(db, cmd, owner);
  const s = await state(base); assert.equal(s.live.descricao, 'Nova'); assert.equal(s.stock.descricao, 'Nova'); assert.equal(s.stock.stockRevision, 0);
  await denied(executeStockCommand(db, {...cmd, operationId: 'e2', editorial: {quantidade: 5}}, owner), 'invalid-argument');
});
test('concurrent publish and sale always converge atomically', async () => {
  const {base, lojaId} = await seed();
  await Promise.all([publishStockProduct(db, lojaId, 'p', owner), executeStockCommand(db, intent(lojaId, 'sale', 's'), owner)]);
  const s = await state(base); assert.equal(s.stock.quantidade, 0); assert.equal(s.live, null);
});

async function addProduct(base, id, stock) {
  const b = db.batch();
  b.set(base.collection('estoque_produtos').doc(id), {stockKind: 'simple', stockRevision: 0, ...stock});
  b.set(base.collection('draft_produtos').doc(id), {nome: id, publicadoNoCatalogo: true});
  b.set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  await b.commit();
}
async function getStock(base, id) {return (await base.collection('estoque_produtos').doc(id).get()).data();}
async function dependents(base, id) {return (await base.collection('stock_catalog_dependencies').doc(id).get()).data().comboIds;}
function define(lojaId, kind, op, id, definition, expectedRevision = 0) {
  return intent(lojaId, kind, op, {productId: id, expectedRevision}, {definition, editorial: {nome: id, publicadoNoCatalogo: true}});
}
const combo = (itensCombo, quantidade = 2) => ({quantidade, tipoProduto: 'combo', itensCombo});
test('create is atomic; retry after later delete does not recreate live', async () => {
  const {base, lojaId} = await seed();
  const cmd = define(lojaId, 'create', 'new', 'new', {quantidade: 2, variacoes: {}});
  await executeStockCommand(db, cmd, owner);
  assert.equal((await base.collection('produtos').doc('new').get()).data().quantidade, 2);
  await denied(executeStockCommand(db, {...cmd, operationId: 'other'}, owner), 'already-exists');
  await executeStockCommand(db, intent(lojaId, 'delete', 'delete', {productId: 'new', expectedRevision: 0}), owner);
  assert.equal((await executeStockCommand(db, cmd, owner)).alreadyApplied, true);
  assert.equal((await base.collection('produtos').doc('new').get()).exists, false);
});
test('create combo registers reverse dependency and component sale removes exhausted kit', async () => {
  const {base, lojaId} = await seed({quantidade: 2});
  await executeStockCommand(db, define(lojaId, 'create', 'combo', 'kit', combo([{productId: 'p', quantidade: 2}], 1)), owner);
  assert.deepEqual(await dependents(base, 'p'), ['kit']);
  await executeStockCommand(db, intent(lojaId, 'sale', 's'), owner);
  assert.equal((await getStock(base, 'kit')).quantidade, 0);
  assert.equal((await base.collection('produtos').doc('kit').get()).exists, false);
  assert.equal((await getStock(base, 'p')).quantidade, 1);
});
test('combo sale expands once; restore uses recorded components after recipe editing', async () => {
  const {base, lojaId} = await seed({quantidade: 4});
  await addProduct(base, 'q', {quantidade: 7});
  await executeStockCommand(db, define(lojaId, 'create', 'new', 'kit', combo([{productId: 'p', quantidade: 2}])), owner);
  const sale = intent(lojaId, 'sale', 'sale', {productId: 'kit'});
  await executeStockCommand(db, sale, owner); await executeStockCommand(db, sale, owner);
  assert.equal((await getStock(base, 'p')).quantidade, 2);
  const kit = await getStock(base, 'kit');
  await executeStockCommand(db, define(lojaId, 'replace', 'recipe', 'kit', combo([{productId: 'q'}], 1), kit.stockRevision), owner);
  assert.deepEqual(await dependents(base, 'p'), []); assert.deepEqual(await dependents(base, 'q'), ['kit']);
  await executeStockCommand(db, intent(lojaId, 'restore', 'undo-sale', {}, {sourceOperationId: 'sale'}), owner);
  assert.equal((await getStock(base, 'p')).quantidade, 4); assert.equal((await getStock(base, 'q')).quantidade, 7);
});
test('repeated fixed recipe lines share cell capacity', async () => {
  const {base, lojaId} = await seed({quantidade: 3});
  await executeStockCommand(db, define(lojaId, 'create', 'kit', 'kit', combo([{productId: 'p'}, {productId: 'p'}], 3)), owner);
  assert.equal((await getStock(base, 'kit')).quantidade, 1);
  await executeStockCommand(db, intent(lojaId, 'sale', 's', {productId: 'kit'}), owner);
  assert.equal((await getStock(base, 'p')).quantidade, 1); assert.equal((await getStock(base, 'kit')).quantidade, 0);
});
test('fixed recipe capacity uses selected color, preserving other colors', async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', quantidade: 8, variacoes: {P: {Azul: 1, Vermelho: 7}}});
  await executeStockCommand(db, define(lojaId, 'create', 'kit', 'kit', combo([{productId: 'p', tamanho: 'P', cor: ' azul '}], 8)), owner);
  assert.equal((await getStock(base, 'kit')).quantidade, 1);
  await executeStockCommand(db, intent(lojaId, 'sale', 's', {size: 'P', color: 'AZUL'}), owner);
  assert.equal((await getStock(base, 'kit')).quantidade, 0);
  assert.equal((await base.collection('produtos').doc('kit').get()).exists, false);
});
test('cyclic recipe replacement aborts all writes', async () => {
  const {base, lojaId} = await seed({quantidade: 2});
  await executeStockCommand(db, define(lojaId, 'create', 'kit', 'kit', combo([{productId: 'p'}])), owner);
  await denied(executeStockCommand(db, define(lojaId, 'replace', 'cycle', 'p', combo([{productId: 'kit'}])), owner), 'failed-precondition');
  assert.equal((await getStock(base, 'p')).stockKind, 'simple');
  assert.equal((await base.collection('stock_catalog_operations').doc('cycle').get()).exists, false);
  assert.deepEqual(await dependents(base, 'kit'), []);
});
test('delete component removes combo; retry is safe; CAS undo restores availability', async () => {
  const {base, lojaId} = await seed({quantidade: 2});
  await executeStockCommand(db, define(lojaId, 'create', 'kit', 'kit', combo([{productId: 'p'}])), owner);
  const deletion = intent(lojaId, 'delete', 'd', {expectedRevision: 0});
  await executeStockCommand(db, deletion, owner);
  assert.equal((await executeStockCommand(db, deletion, owner)).alreadyApplied, true);
  assert.equal((await getStock(base, 'kit')).quantidade, 0);
  await publishStockProduct(db, lojaId, 'p', owner); assert.equal((await state(base)).live, null);
  await denied(executeStockCommand(db, intent(lojaId, 'undo', 'bad', {expectedRevision: 0}), owner), 'aborted');
  await executeStockCommand(db, intent(lojaId, 'undo', 'u', {expectedRevision: 1}), owner);
  assert.equal((await state(base)).live.quantidade, 2); assert.equal((await getStock(base, 'kit')).quantidade, 2);
  assert.equal((await base.collection('exclusao_produto').doc('p').get()).exists, false);
});
test('variation tombstone is partial: product remains, retry idempotent, never p:true', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 3,
    variacoes: {P: {Azul: 1, Vermelho: 2}},
  });
  await publishStockProduct(db, lojaId, 'p', owner);
  const key = 'V::P\u001EAzul\u001E';
  const cmd = intent(lojaId, 'tombstoneVariation', 'tv1', {expectedRevision: 0}, {tombstoneKeys: [key]});
  delete cmd.items[0].quantity;
  await executeStockCommand(db, cmd, owner);
  assert.equal((await executeStockCommand(db, cmd, owner)).alreadyApplied, true);
  const tomb = (await base.collection('exclusao_produto').doc('p').get()).data();
  assert.equal(tomb.p, false);
  assert.equal(tomb.v[key], true);
  const s = await state(base);
  assert.equal(s.stock.variacoes.P.Vermelho, 2);
  assert.equal(s.live.variacoes.P.Vermelho, 2);
  assert.equal(s.stock.pendingSoftDelete, undefined);
  await denied(executeStockCommand(db, intent(lojaId, 'tombstoneVariation', 'tv-stale', {expectedRevision: 99}, {tombstoneKeys: [key]}), owner), 'aborted');
});
test('CAS grade replacement ignores old aggregate and rejects old revision', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, define(lojaId, 'replace', 'grade', 'p', {variacoes: {P: {Azul: 0}}, estoquePorTamanho: {P: 8}, quantidade: 8}), owner);
  assert.equal((await state(base)).stock.quantidade, 0); assert.equal((await state(base)).live, null);
  await denied(executeStockCommand(db, define(lojaId, 'replace', 'stale', 'p', {quantidade: 8}), owner), 'aborted');
});
test('over-budget combo aborts before creating any stock or operation', async () => {
  const {base, lojaId} = await seed(); const components = [];
  for (let n = 0; n < 25; n++) {const id = `c${n}`; await addProduct(base, id, {quantidade: 1}); components.push({productId: id});}
  await denied(executeStockCommand(db, define(lojaId, 'create', 'big', 'kit', combo(components, 1)), owner), 'resource-exhausted');
  assert.equal((await base.collection('estoque_produtos').doc('kit').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_operations').doc('big').get()).exists, false);
});
test('reserved publishing identity cannot be spoofed by auth UID', async () => {
  const {base, lojaId} = await seed();
  await base.collection('stock_catalog_access').doc('stock-catalog-publisher').set({enabled: true, permissions: {publish: true}});
  await denied(publishStockProduct(db, lojaId, 'p', {uid: 'stock-catalog-publisher'}), 'permission-denied');
});

async function orderFixture(stock = 1) {
  const seeded = await seed({quantidade: stock});
  await seeded.base.collection('stock_catalog_access').doc('stock-catalog-payment').set({enabled: true, permissions: {sale: true}});
  const orderRef = seeded.base.collection('pre_pedidos').doc('order');
  await orderRef.set({itens: [{productId: 'p', quantidade: 1}], total: 10});
  return {...seeded, orderRef};
}
test('manual confirmation races verified webhook: same order identity, one decrement', async () => {
  const {base, lojaId, orderRef} = await orderFixture();
  const [manual, webhook] = await Promise.all([
    executeOrderStockCommand(db, lojaId, 'order', owner),
    runStockTransaction(db, async tx => {
      const order = await tx.get(orderRef);
      const r = await applyOrderStockInTransaction(tx, db, lojaId, 'order', order.data(), 1);
      tx.update(orderRef, {paidAt: 'emulator-fixture'});
      return r;
    }),
  ]);
  assert.equal([manual, webhook].filter(r => r.alreadyApplied).length, 1);
  assert.equal((await state(base)).stock.quantidade, 0); assert.equal((await state(base)).live, null);
  assert.equal((await orderRef.get()).data().paidAt, 'emulator-fixture');
  assert.equal(manual.operationId, orderStockOperationId('order'));
});
test('order adapter failure aborts paid marker and catalog together', async () => {
  const {base, lojaId, orderRef} = await orderFixture(0);
  await denied(runStockTransaction(db, async tx => {
    const order = await tx.get(orderRef);
    await applyOrderStockInTransaction(tx, db, lojaId, 'order', order.data(), 1);
    tx.update(orderRef, {paidAt: 'must-not-commit'});
  }), 'failed-precondition');
  assert.equal((await orderRef.get()).data().paidAt, undefined);
  assert.equal((await base.collection('stock_catalog_operations').doc(orderStockOperationId('order')).get()).exists, false);
});
test('order adapter requires user store grant and server payment grant; no spoofed service UID', async () => {
  const {base, lojaId} = await orderFixture();
  await denied(executeOrderStockCommand(db, lojaId, 'order', null), 'unauthenticated');
  await denied(executeOrderStockCommand(db, lojaId, 'order', {uid: 'intruder'}), 'permission-denied');
  await denied(executeOrderStockCommand(db, lojaId, 'order', {uid: 'stock-catalog-payment'}), 'permission-denied');
  await base.collection('stock_catalog_access').doc('stock-catalog-payment').delete();
  await denied(executeOrderStockCommand(db, lojaId, 'order', owner), 'permission-denied');
  assert.equal((await state(base)).stock.quantidade, 1);
});
test('replayed order with changed stock intent is rejected instead of silently re-debiting', async () => {
  const {base, lojaId, orderRef} = await orderFixture(4);
  await executeOrderStockCommand(db, lojaId, 'order', owner);
  await orderRef.update({itens: [{productId: 'p', quantidade: 2}]});
  await denied(executeOrderStockCommand(db, lojaId, 'order', owner), 'already-exists');
  assert.equal((await state(base)).stock.quantidade, 3);
});

for (const variant of [
  {name: 'size-only sem-cor', stock: {variacoes: {P: {'sem-cor': 1}}}, item: {size: 'P'}},
  {name: 'color-only sem-tamanho', stock: {variacoes: {'sem-tamanho': {Azul: 1}}}, item: {color: ' azul '}},
  {name: 'color-only root', stock: {estoquePorCor: {Azul: 1}}, item: {color: 'AZUL'}},
  {name: 'named extra', stock: {variacoes: {P: {Azul: {A: 1}}}}, item: {size: 'P', color: 'Azul', extra: 'A'}},
]) test(`sale and restore preserve ${variant.name}`, async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', ...variant.stock});
  await executeStockCommand(db, intent(lojaId, 'sale', 's', variant.item), owner);
  assert.equal((await state(base)).stock.quantidade, 0); assert.equal((await state(base)).live, null);
  await executeStockCommand(db, intent(lojaId, 'restore', 'r', {}, {sourceOperationId: 's'}), owner);
  assert.equal((await state(base)).stock.quantidade, 1); assert.equal((await state(base)).live.quantidade, 1);
});
test('write-count budget includes reverse indexes and operation marker', async () => {
  const {base, lojaId} = await seed(); const components = [];
  for (let n = 0; n < 24; n++) {const id = `c${n}`; await addProduct(base, id, {quantidade: 1}); components.push({productId: id});}
  await denied(executeStockCommand(db, define(lojaId, 'create', 'big', 'kit', combo(components, 1)), owner), 'resource-exhausted');
  assert.equal((await base.collection('estoque_produtos').doc('kit').get()).exists, false);
  assert.deepEqual(await dependents(base, 'c0'), []);
});
test('configurable combo validates canonical groups, selected option and amount before decrement', async () => {
  const {base, lojaId} = await seed({quantidade: 3});
  const definition = {quantidade: 3, tipoProduto: 'combo', comboConfig: {grupos: [{id: 'g', obrigatorio: true,
    selecaoMin: 1, selecaoMax: 1, opcoes: [{productId: 'p', qtdMin: 1, qtdMax: 2}]}]}};
  await executeStockCommand(db, define(lojaId, 'create', 'kit', 'kit', definition), owner);
  for (const selection of [[], [{groupId: 'g', productId: 'other', quantity: 1}], [{groupId: 'g', productId: 'p', quantity: 3}]]) {
    await denied(executeStockCommand(db, intent(lojaId, 'sale', 'invalid', {productId: 'kit', selection}), owner), 'invalid-argument');
  }
  assert.equal((await getStock(base, 'p')).quantidade, 3);
  await executeStockCommand(db, intent(lojaId, 'sale', 'valid', {productId: 'kit', selection: [{groupId: 'g', productId: 'p', quantity: 2}]}), owner);
  assert.equal((await getStock(base, 'p')).quantidade, 1); assert.equal((await getStock(base, 'kit')).quantidade, 2);
});

test('closed-token retry creates fresh transaction; domain and invalid-payload errors are never retried', async () => {
  let attempts = 0;
  const dbClosed = {runTransaction: async callback => {
    if (++attempts === 1) throw Object.assign(new Error('Transaction is invalid or closed.'), {code: 3});
    return callback({fresh: true});
  }};
  assert.equal(await runStockTransaction(dbClosed, tx => tx.fresh), true); assert.equal(attempts, 2);
  for (const code of ['aborted', 'permission-denied', 3]) {
    let called = 0;
    await assert.rejects(runStockTransaction({runTransaction: async () => {called++; throw Object.assign(new Error('Invalid payload'), {code});}}, () => {}));
    assert.equal(called, 1);
  }
});

test('real _sem_extra cell with private cost: sale zero, restore, no cost leak or cost debit', async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', variacoes: {P: {Azul: {_sem_extra: 1, __custoUnitario: 12.75}}}});
  await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal((await state(base)).live.variacoes.P.Azul.__custoUnitario, undefined);
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 'bad', {size: 'P', color: 'Azul', extra: '__custoUnitario'}), owner), 'failed-precondition');
  await executeStockCommand(db, intent(lojaId, 'sale', 's', {size: 'P', color: 'Azul'}), owner);
  assert.equal((await state(base)).stock.quantidade, 0); assert.equal((await state(base)).live, null);
  assert.equal((await state(base)).stock.variacoes.P.Azul.__custoUnitario, 12.75);
  await executeStockCommand(db, intent(lojaId, 'restore', 'r', {}, {sourceOperationId: 's'}), owner);
  assert.equal((await state(base)).live.quantidade, 1);
  assert.equal((await state(base)).live.variacoes.P.Azul.__custoUnitario, undefined);
});

test('catalog ranking belongs to recorded order debit, survives zero/restock and reverses only once', async () => {
  const {base, lojaId} = await orderFixture(1);
  await base.collection('estoque_produtos').doc('p').update({vendasCatalogoTotal: 7});
  const first = await executeOrderStockCommand(db, lojaId, 'order', owner);
  await executeOrderStockCommand(db, lojaId, 'order', owner);
  assert.equal((await state(base)).stock.vendasCatalogoTotal, 8);
  assert.equal((await state(base)).live, null);
  await executeStockCommand(db, intent(lojaId, 'restock', 'entry'), owner);
  assert.equal((await state(base)).live.vendasCatalogoTotal, 8);
  await executeStockCommand(db, intent(lojaId, 'restore', 'return', {}, {sourceOperationId: first.operationId}), owner);
  await executeStockCommand(db, intent(lojaId, 'restore', 'return', {}, {sourceOperationId: first.operationId}), owner);
  assert.equal((await state(base)).stock.vendasCatalogoTotal, 7);
  assert.equal((await state(base)).live.vendasCatalogoTotal, 7);
  await denied(executeStockCommand(db, intent(lojaId, 'editorial', 'spoof', {}, {editorial: {vendasCatalogoTotal: 999}}), owner), 'invalid-argument');
});
test('catalog ranking counts combo root and excludes its expanded components and ordinary PDV sales', async () => {
  const {base, lojaId, orderRef} = await orderFixture(5);
  await executeStockCommand(db, define(lojaId, 'create', 'create-kit', 'kit', combo([{productId: 'p', quantidade: 2}], 2)), owner);
  await orderRef.update({itens: [{productId: 'kit', quantidade: 1}]});
  await executeOrderStockCommand(db, lojaId, 'order', owner);
  assert.equal((await getStock(base, 'kit')).vendasCatalogoTotal, 1);
  assert.equal((await getStock(base, 'p')).vendasCatalogoTotal ?? 0, 0);
  await executeStockCommand(db, intent(lojaId, 'sale', 'pdv'), owner);
  assert.equal((await getStock(base, 'p')).vendasCatalogoTotal ?? 0, 0);
});
