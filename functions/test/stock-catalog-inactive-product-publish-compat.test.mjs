import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockAll, publishStockProduct} from '../src/stockCatalogCommands.js';
import {
  INACTIVE_COMPAT_ALLOWED_KINDS,
  INACTIVE_PRODUCT_COMPAT_ALLOWED_KINDS,
} from '../src/stockCatalogAccess.js';

const __emu = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emu)) {
  throw new Error('Local emulator required; refusing any other endpoint: ' + __emu);
}
const db = new Firestore({projectId: 'demo-stock-catalog'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};
const sellerVendas = {uid: 'seller_vendas'};
const sellerCadastro = {uid: 'seller_cadastro'};

async function seedStore({
  control = null,
  product = null,
  productId = 'p',
  withOwner = true,
  withDraft = false,
  withDep = false,
  omitStockKind = false,
  sellers = [],
} = {}) {
  const lojaId = `pp_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, withOwner ? {ownerUid: 'owner', name: 'Fixture'} : {name: 'Fixture'});
  if (product) {
    const stock = {quantidade: 5, stockRevision: 1, ...product};
    if (!omitStockKind && !('stockKind' in product)) stock.stockKind = 'simple';
    if (omitStockKind) delete stock.stockKind;
    batch.set(base.collection('estoque_produtos').doc(productId), stock);
    if (withDraft) {
      batch.set(base.collection('draft_produtos').doc(productId), {
        nome: product.nome || 'Peça',
        publicadoNoCatalogo: true,
      });
    }
    if (withDep) batch.set(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  }
  if (control) batch.set(base.collection('stock_catalog_control').doc('state'), control);
  for (const s of sellers) {
    batch.set(base.collection('vendedores').doc(s.uid), {
      ativo: true,
      permissoes: s.permissoes || {},
    });
  }
  await batch.commit();
  return {base, lojaId};
}

async function seedActive({product = {}, productId = 'p'} = {}) {
  const lojaId = `act_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid: 'owner', name: 'Active'});
  batch.set(base.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  batch.set(base.collection('stock_catalog_access').doc('owner'), {
    enabled: true,
    permissions: {
      sale: true, restock: true, adjust: true, restore: true, editorial: true,
      publish: true, create: true, delete: true, undo: true,
    },
  });
  const stock = {quantidade: 3, stockKind: 'simple', stockRevision: 0, ...product};
  batch.set(base.collection('estoque_produtos').doc(productId), stock);
  batch.set(base.collection('draft_produtos').doc(productId), {nome: 'Ativo', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  await batch.commit();
  return {base, lojaId};
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {
    protocolVersion: 1,
    lojaId,
    kind,
    operationId,
    items: [{productId: 'p', ...item}],
    ...extra,
  };
}

function createIntent(lojaId, operationId, definition, editorial, productId = 'p') {
  return intent(lojaId, 'create', operationId, {productId}, {
    definition,
    editorial: {nome: 'Novo', publicadoNoCatalogo: true, ...editorial},
  });
}

async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

test('allowlists: sale vs product remain separate', () => {
  assert.deepEqual([...INACTIVE_COMPAT_ALLOWED_KINDS], ['sale', 'restore', 'restock']);
  assert.deepEqual([...INACTIVE_PRODUCT_COMPAT_ALLOWED_KINDS], [
    'create', 'replace', 'editorial', 'delete',
  ]);
});

test('P1 NO_CONTROL create SIMPLE persists stockKind+draft+revision0', async () => {
  const {base, lojaId} = await seedStore();
  const result = await executeStockCommand(db, createIntent(lojaId, 'c1', {
    quantidade: 4, tipoProduto: 'simples',
  }, {nome: 'Anel'}), owner);
  assert.equal(result.alreadyApplied, false);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  const draft = (await base.collection('draft_produtos').doc('p').get()).data();
  assert.equal(stock.stockKind, 'simple');
  assert.equal(stock.stockRevision, 0);
  assert.equal(stock.quantidade, 4);
  assert.equal(draft.nome, 'Anel');
  assert.equal(draft.publicadoNoCatalogo, true);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').doc('owner').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_dependencies').doc('p').get()).exists, false);
});

test('P2 INACTIVE create VARIATION', async () => {
  const {base, lojaId} = await seedStore({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  await executeStockCommand(db, createIntent(lojaId, 'c2', {
    quantidade: 3,
    tipoProduto: 'variacao',
    variacoes: {37: {preto: 2}, 38: {preto: 1}},
    estoquePorTamanho: {37: 2, 38: 1},
    tamanhos: ['37', '38'],
  }, {nome: 'Sandalia'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.stockKind, 'variation');
  assert.equal(stock.stockRevision, 0);
  assert.equal(stock.variacoes['37'].preto, 2);
  assert.ok((await base.collection('draft_produtos').doc('p').get()).exists);
});

test('INACTIVE_COMBO_CREATE_REACHABLE self-contained combo', async () => {
  const {base, lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'ccombo', {
    quantidade: 1,
    tipoProduto: 'combo',
    itensCombo: [],
    comboConfig: {modo: 'fixo'},
  }, {nome: 'Kit'}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, 'combo');
});

test('P3/P4 NO_CONTROL and INACTIVE replace', async () => {
  for (const control of [null, {protocolVersion: 1, mode: 'inactive'}]) {
    const {base, lojaId} = await seedStore({
      control,
      product: {quantidade: 2, stockKind: 'simple', stockRevision: 1, nome: 'Velho'},
      withDraft: true,
    });
    await executeStockCommand(db, intent(lojaId, 'replace', `rep_${control ? 'in' : 'nc'}`, {
      productId: 'p', expectedRevision: 1,
    }, {
      definition: {quantidade: 9, tipoProduto: 'simples'},
      editorial: {nome: 'Novo', publicadoNoCatalogo: true},
    }), owner);
    const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
    assert.equal(stock.quantidade, 9);
    assert.equal(stock.stockKind, 'simple');
    assert.equal((await base.collection('draft_produtos').doc('p').get()).data().nome, 'Novo');
  }
});

test('P5/P6 NO_CONTROL and INACTIVE editorial', async () => {
  for (const control of [null, {protocolVersion: 1, mode: 'inactive'}]) {
    const {base, lojaId} = await seedStore({
      control,
      omitStockKind: true,
      product: {quantidade: 2, nome: 'Base'},
      withDraft: true,
    });
    await executeStockCommand(db, intent(lojaId, 'editorial', `ed_${control ? 'in' : 'nc'}`, {
      productId: 'p',
    }, {editorial: {nome: 'Editado', publicadoNoCatalogo: true}}), owner);
    const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
    assert.equal(stock.nome, 'Editado');
    // editorial must not backfill stockKind on legacy docs
    assert.equal(stock.stockKind, undefined);
  }
});

test('P7 delete inactive + tombstone', async () => {
  const {base, lojaId} = await seedStore({
    product: {quantidade: 2, stockKind: 'simple', stockRevision: 0},
    withDraft: true,
  });
  await executeStockCommand(db, intent(lojaId, 'delete', 'del1', {
    productId: 'p', expectedRevision: 0,
  }), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().pendingSoftDelete, true);
  assert.equal((await base.collection('exclusao_produto').doc('p').get()).data().p, true);
});

test('P8 duplicate create replay → one product', async () => {
  const {base, lojaId} = await seedStore();
  const cmd = createIntent(lojaId, 'dup1', {quantidade: 1}, {nome: 'Dup'});
  const a = await executeStockCommand(db, cmd, owner);
  const b = await executeStockCommand(db, cmd, owner);
  assert.equal(a.alreadyApplied, false);
  assert.equal(b.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).exists, true);
});

test('P9 create then update (queue ordering fixture)', async () => {
  const {base, lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'cu1', {quantidade: 1}, {nome: 'V1'}), owner);
  await executeStockCommand(db, intent(lojaId, 'replace', 'cu2', {
    productId: 'p', expectedRevision: 0,
  }, {
    definition: {quantidade: 7, tipoProduto: 'simples'},
    editorial: {nome: 'V2', publicadoNoCatalogo: true},
  }), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 7);
  assert.equal((await base.collection('draft_produtos').doc('p').get()).data().nome, 'V2');
});

test('P10 stale replace CAS aborted', async () => {
  const {lojaId} = await seedStore({
    product: {quantidade: 2, stockKind: 'simple', stockRevision: 3},
    withDraft: true,
  });
  await denied(executeStockCommand(db, intent(lojaId, 'replace', 'stale', {
    productId: 'p', expectedRevision: 1,
  }, {
    definition: {quantidade: 99, tipoProduto: 'simples'},
    editorial: {nome: 'X', publicadoNoCatalogo: false},
  }), owner), 'aborted');
});

test('P11 stale create cannot resurrect deleted', async () => {
  const {base, lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'res1', {quantidade: 1}, {nome: 'Live'}), owner);
  await executeStockCommand(db, intent(lojaId, 'delete', 'res2', {
    productId: 'p', expectedRevision: 0,
  }), owner);
  await denied(
    executeStockCommand(db, createIntent(lojaId, 'res3', {quantidade: 5}, {nome: 'Zombie'}), owner),
    'already-exists',
  );
  assert.equal((await base.collection('exclusao_produto').doc('p').get()).data().p, true);
});

test('P12/P13/P14 auth denials for product', async () => {
  const {lojaId} = await seedStore({
    sellers: [
      {uid: 'seller_vendas', permissoes: {vendas: true}},
      {uid: 'seller_cadastro', permissoes: {estoque: true}},
    ],
  });
  await denied(executeStockCommand(db, createIntent(lojaId, 'a1', {quantidade: 1}, {nome: 'X'}), null), 'unauthenticated');
  await denied(executeStockCommand(db, createIntent(lojaId, 'a2', {quantidade: 1}, {nome: 'X'}), {uid: 'intruder'}), 'permission-denied');
  await denied(executeStockCommand(db, createIntent(lojaId, 'a3', {quantidade: 1}, {nome: 'X'}), sellerVendas), 'permission-denied');
  const ok = await executeStockCommand(db, createIntent(lojaId, 'a4', {quantidade: 1}, {nome: 'Cad'}), sellerCadastro);
  assert.equal(ok.alreadyApplied, false);
});

test('P15 ACTIVE create unchanged (grant path)', async () => {
  const {base, lojaId} = await seedActive();
  // product p already exists on ACTIVE seed — create another id
  await executeStockCommand(db, createIntent(lojaId, 'actc', {quantidade: 2}, {nome: 'A'}, 'q'), owner);
  const stock = (await base.collection('estoque_produtos').doc('q').get()).data();
  assert.equal(stock.stockKind, 'simple');
  assert.ok((await base.collection('stock_catalog_dependencies').doc('q').get()).exists);
});

test('P16 new inactive product future-migratable (no control/grants)', async () => {
  const {base, lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'mig', {quantidade: 1}, {nome: 'M'}), owner);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').doc('owner').get()).exists, false);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.stockKind, 'simple');
  assert.equal(typeof stock.stockRevision, 'number');
});

test('P17 invalid/ambiguous fail closed', async () => {
  const {lojaId} = await seedStore({
    product: {
      stockKind: 'simple',
      quantidade: 2,
      variacoes: {37: {a: 1}},
      estoquePorTamanho: {37: 1},
      tamanhos: ['37'],
    },
    withDraft: true,
  });
  await denied(executeStockCommand(db, intent(lojaId, 'editorial', 'bad', {productId: 'p'}, {
    editorial: {nome: 'Nope', publicadoNoCatalogo: true},
  }), owner), 'failed-precondition', 'Simple product has variation data');
});

test('P18 pre-fix queue format: frozen operationId create works', async () => {
  const {base, lojaId} = await seedStore();
  // Mimic client frozen stockIntentJson identity
  const op = 'create_queue_fixture_op';
  await executeStockCommand(db, createIntent(lojaId, op, {quantidade: 2}, {nome: 'Queued'}), owner);
  await executeStockCommand(db, createIntent(lojaId, op, {quantidade: 2}, {nome: 'Queued'}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
});

test('C1/C2 NO_CONTROL and INACTIVE publishOne legacy missing metadata', async () => {
  for (const control of [null, {protocolVersion: 1, mode: 'inactive'}]) {
    const {base, lojaId} = await seedStore({
      control,
      omitStockKind: true,
      product: {quantidade: 4, nome: 'Legado', publicadoNoCatalogo: true},
    });
    const pub = await publishStockProduct(db, lojaId, 'p', owner);
    assert.equal(pub.available, true);
    const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
    assert.equal(stock.stockKind, undefined); // no backfill on publish
    const live = (await base.collection('produtos').doc('p').get()).data();
    assert.equal(live.quantidade, 4);
    assert.equal(live.__custoUnitario, undefined);
    assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, !!control);
  }
});

test('C3/C4 publishAll mixed catalog', async () => {
  const {base, lojaId} = await seedStore({
    omitStockKind: true,
    product: {quantidade: 2, nome: 'A', publicadoNoCatalogo: true},
    productId: 'a',
  });
  await db.collection('lojas').doc(lojaId).collection('estoque_produtos').doc('b').set({
    quantidade: 3,
    stockKind: 'variation',
    stockRevision: 0,
    variacoes: {M: {azul: 3}},
    estoquePorTamanho: {M: 3},
    tamanhos: ['M'],
    nome: 'B',
    publicadoNoCatalogo: true,
  });
  const out = await publishStockAll(db, lojaId, owner);
  assert.ok(out.publishedProductsProcessed >= 2);
  assert.ok((await base.collection('produtos').doc('a').get()).exists);
  assert.ok((await base.collection('produtos').doc('b').get()).exists);
});

test('C5/C6 ACTIVE publish unchanged (requires grant)', async () => {
  const {base, lojaId} = await seedActive({product: {quantidade: 5}});
  const pub = await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal(pub.available, true);
  assert.equal((await base.collection('produtos').doc('p').get()).data().quantidade, 5);
  await denied(publishStockProduct(db, lojaId, 'p', {uid: 'intruder'}), 'permission-denied');
});

test('C7/C8 unauthorized / other-store publish deny', async () => {
  const {lojaId} = await seedStore({
    product: {quantidade: 1, stockKind: 'simple', publicadoNoCatalogo: true},
    sellers: [{uid: 'seller_vendas', permissoes: {vendas: true}}],
  });
  await denied(publishStockProduct(db, lojaId, 'p', null), 'unauthenticated');
  await denied(publishStockProduct(db, lojaId, 'p', {uid: 'intruder'}), 'permission-denied');
  await denied(publishStockProduct(db, lojaId, 'p', sellerVendas), 'permission-denied');
});

test('C9 privacy: private cost never published', async () => {
  const {base, lojaId} = await seedStore({
    product: {
      quantidade: 2,
      stockKind: 'simple',
      stockRevision: 0,
      nome: 'Priv',
      publicadoNoCatalogo: true,
      __custoUnitario: 12.34,
    },
  });
  await publishStockProduct(db, lojaId, 'p', owner);
  const live = (await base.collection('produtos').doc('p').get()).data();
  const json = JSON.stringify(live);
  assert.equal(json.includes('__custoUnitario'), false);
  assert.equal(json.includes('stock_catalog_dependencies'), false);
  assert.equal(json.includes('stock_catalog_control'), false);
  assert.equal(live.stock_catalog_operations, undefined);
});

test('C10/C11 publish idempotent', async () => {
  const {base, lojaId} = await seedStore({
    product: {quantidade: 2, stockKind: 'simple', publicadoNoCatalogo: true, nome: 'Idem'},
  });
  const a = await publishStockProduct(db, lojaId, 'p', owner);
  const b = await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal(a.available, b.available);
  assert.equal((await base.collection('produtos').doc('p').get()).data().quantidade, 2);
  const all1 = await publishStockAll(db, lojaId, owner);
  const all2 = await publishStockAll(db, lojaId, owner);
  assert.equal(all1.publishedProductsProcessed, all2.publishedProductsProcessed);
});

test('C12/C13 legacy missing metadata + new inactive canonical publish', async () => {
  const {base, lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'pubn', {
    quantidade: 5,
  }, {nome: 'Canon', publicadoNoCatalogo: true}), owner);
  const pub = await publishStockProduct(db, lojaId, 'p', owner);
  assert.equal(pub.available, true);
  assert.equal((await base.collection('produtos').doc('p').get()).data().stockKind, 'simple');
});

test('inactive restock restores stock; sale still works', async () => {
  const {base, lojaId} = await seedStore({
    product: {quantidade: 5, stockKind: 'simple', stockRevision: 1},
  });
  await executeStockCommand(db, intent(lojaId, 'restock', 'r1', {quantity: 1}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 6);
  await executeStockCommand(db, intent(lojaId, 'sale', 's1', {quantity: 1}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
});

test('VALID inactive product/publish do not return migration incomplete', async () => {
  const {lojaId} = await seedStore();
  await executeStockCommand(db, createIntent(lojaId, 'ok1', {quantidade: 1}, {nome: 'OK'}), owner);
  await publishStockProduct(db, lojaId, 'p', owner);
});
