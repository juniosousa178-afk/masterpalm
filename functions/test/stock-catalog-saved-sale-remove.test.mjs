import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  INACTIVE_COMPAT_ALLOWED_KINDS,
  VARIATION_SALE_PRODUCT_NOT_AUTHORIZED,
  GRADE_SALE_NOT_AUTHORIZED,
} from '../src/stockCatalogAccess.js';

const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) {
  throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
}
const db = new Firestore({projectId: 'demo-saved-sale-remove'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};
const MAX_PRODUCTS = 25;

function commandsSrc() {
  return readFileSync(new URL('../src/stockCatalogCommands.js', import.meta.url), 'utf8');
}
function accessSrc() {
  return readFileSync(new URL('../src/stockCatalogAccess.js', import.meta.url), 'utf8');
}

async function seed({
  productId = 'blocked',
  grant = false,
  stockKind = 'variation',
  variacoes = {P: {'sem-cor': 0}, M: {'sem-cor': 0}, G: {'sem-cor': 0}},
  quantidade = 0,
  extra = false,
} = {}) {
  const lojaId = `ssr_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid: 'owner', name: 'Saved sale remove'});
  const stock = {quantidade, stockKind, stockRevision: 1};
  if (stockKind === 'variation') {
    stock.variacoes = variacoes;
    stock.estoquePorTamanho = Object.fromEntries(
      Object.entries(variacoes).map(([size, colors]) => [size, Object.values(colors).reduce((a, b) => a + b, 0)]),
    );
  }
  if (extra) {
    stock.variacoes = {P: {azul: {fosco: 1}}};
    stock.variacoesExtraTipo = 'acabamento';
  }
  batch.set(base.collection('estoque_produtos').doc(productId), stock);
  batch.set(base.collection('draft_produtos').doc(productId), {nome: productId});
  batch.set(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  if (grant) {
    batch.set(base.collection('variation_sale_product_grants').doc(productId), {enabled: true});
  }
  await batch.commit();
  return {base, lojaId, productId};
}

function cmd(lojaId, kind, operationId, items) {
  return {protocolVersion: 1, lojaId, kind, operationId, items};
}

async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

test('1 existing sale simple item removal restocks', async () => {
  const {base, lojaId} = await seed({productId: 'simple', stockKind: 'simple', quantidade: 4});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'r-simple', [
    {productId: 'simple', quantity: 1},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc('simple').get()).data().quantidade, 5);
});

test('2 existing sale variation item removal restocks without grant', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'r-var', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner);
  const stock = (await base.collection('estoque_produtos').doc('blocked').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 1);
});

test('3 existing sale blocked variation product removal restocks', async () => {
  const {base, lojaId} = await seed({grant: false});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'r-blocked', [
    {productId: 'blocked', quantity: 1, size: 'M', color: 'sem-cor'},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.M['sem-cor'], 1);
});

test('4 blocked variation product decrease qty restocks', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {G: {'sem-cor': 2}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'r-dec', [
    {productId: 'blocked', quantity: 1, size: 'G', color: 'sem-cor'},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.G['sem-cor'], 3);
});

test('5 blocked variation product increase qty denied', async () => {
  const {lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 2}}});
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'inc', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner), 'permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
});

test('6 blocked variation product add denied', async () => {
  const {lojaId} = await seed({grant: false});
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'add', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner), 'permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
});

test('7 blocked variation product new sale denied', async () => {
  const {lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 5}}});
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'new', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner), 'permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
});

test('8 exact stock restored once', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'once', [
    {productId: 'blocked', quantity: 2, size: 'P', color: 'sem-cor'},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.P['sem-cor'], 2);
});

test('9 retry does not double-restock', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  const payload = cmd(lojaId, 'restock', 'idem', [
    {productId: 'blocked', quantity: 3, size: 'P', color: 'sem-cor'},
  ]);
  const first = await executeStockCommand(db, payload, owner);
  const second = await executeStockCommand(db, payload, owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.P['sem-cor'], 3);
});

test('10 sale total recalculated is client-owned; restock does not write sale', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'no-sale-doc', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner);
  assert.equal((await base.collection('estoque_vendas').doc('no-sale-doc').get()).exists, false);
});

test('11 fiado receivable recalculated is client-owned; restock has no receivable write', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'no-cr', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner);
  const cr = await base.collection('contas_receber').limit(1).get();
  assert.equal(cr.empty, true);
});

test('12 cash/Pix/card financial restock does not write lancamentos', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'no-fin', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner);
  const fin = await base.collection('lancamentos_financeiros').limit(1).get();
  assert.equal(fin.empty, true);
});

test('13 mixed sale removal restocks blocked line and leaves grant gate on sale', async () => {
  const {base, lojaId} = await seed({
    productId: 'granted',
    grant: true,
    variacoes: {P: {'sem-cor': 2}},
    quantidade: 2,
  });
  const blockedId = 'blocked-mix';
  await base.collection('estoque_produtos').doc(blockedId).set({
    quantidade: 0, stockKind: 'variation', stockRevision: 1,
    variacoes: {M: {'sem-cor': 0}}, estoquePorTamanho: {M: 0},
  });
  await base.collection('draft_produtos').doc(blockedId).set({nome: blockedId});
  await base.collection('stock_catalog_dependencies').doc(blockedId).set({comboIds: []});
  await executeStockCommand(db, cmd(lojaId, 'restock', 'mix-r', [
    {productId: blockedId, quantity: 1, size: 'M', color: 'sem-cor'},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc(blockedId).get()).data().variacoes.M['sem-cor'], 1);
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'mix-s', [
    {productId: blockedId, quantity: 1, size: 'M', color: 'sem-cor'},
  ]), owner), 'permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
});

test('14 removing 10 lines in one restock is under MAX_PRODUCTS', async () => {
  const {base, lojaId} = await seed({productId: 'p0', grant: false, variacoes: {P: {'sem-cor': 0}}});
  const items = [{productId: 'p0', quantity: 1, size: 'P', color: 'sem-cor'}];
  const batch = db.batch();
  for (let i = 1; i < 10; i++) {
    const id = `p${i}`;
    batch.set(base.collection('estoque_produtos').doc(id), {
      quantidade: 0, stockKind: 'variation', stockRevision: 1,
      variacoes: {P: {'sem-cor': 0}}, estoquePorTamanho: {P: 0},
    });
    batch.set(base.collection('draft_produtos').doc(id), {nome: id});
    batch.set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
    items.push({productId: id, quantity: 1, size: 'P', color: 'sem-cor'});
  }
  await batch.commit();
  await executeStockCommand(db, cmd(lojaId, 'restock', 'ten', items), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p9').get()).data().variacoes.P['sem-cor'], 1);
  assert.equal(new Set(items.map(i => i.productId)).size, 10);
  assert.ok(10 < MAX_PRODUCTS);
});

test('15 delta-limit uses distinct productId not line quantity', async () => {
  assert.match(commandsSrc(), /new Set\(items\.map\(i => i\.productId\)\)\.size > MAX_PRODUCTS/);
  assert.match(commandsSrc(), /const MAX_PRODUCTS = 25/);
});

test('16 over allowed delta is resource-exhausted Too many affected products', async () => {
  const {lojaId, base} = await seed({productId: 'd0', grant: false, variacoes: {P: {'sem-cor': 0}}});
  const items = [{productId: 'd0', quantity: 1, size: 'P', color: 'sem-cor'}];
  const batch = db.batch();
  for (let i = 1; i < 26; i++) {
    const id = `d${i}`;
    batch.set(base.collection('estoque_produtos').doc(id), {
      quantidade: 0, stockKind: 'simple', stockRevision: 1,
    });
    batch.set(base.collection('draft_produtos').doc(id), {nome: id});
    batch.set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
    items.push({productId: id, quantity: 1});
  }
  await batch.commit();
  await denied(executeStockCommand(db, cmd(lojaId, 'restock', 'over', items), owner),
    'resource-exhausted', 'Too many affected products');
});

test('17 historical variation identity ambiguous fails closed without restock', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await denied(executeStockCommand(db, cmd(lojaId, 'restock', 'amb', [
    {productId: 'blocked', quantity: 1, size: 'GG', color: 'sem-cor'},
  ]), owner), 'failed-precondition', 'Variation not found');
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.P['sem-cor'], 0);
});

test('18 no variation synthesis on restock', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  await denied(executeStockCommand(db, cmd(lojaId, 'restock', 'synth', [
    {productId: 'blocked', quantity: 1, size: 'X', color: 'nova'},
  ]), owner), 'failed-precondition', 'Variation not found');
  const stock = (await base.collection('estoque_produtos').doc('blocked').get()).data();
  assert.equal(stock.variacoes.X, undefined);
  assert.equal(Object.keys(stock.variacoes).join(','), 'P');
});

test('19 product-scoped sale gate remains intact for kind=sale only', async () => {
  assert.match(commandsSrc(), /if \(command\.kind === 'sale'\) await authorizeVariationSaleItems/);
  assert.doesNotMatch(commandsSrc(), /kind === 'restock'[\s\S]{0,120}authorizeVariationSaleItems/);
  assert.ok(INACTIVE_COMPAT_ALLOWED_KINDS.includes('restock'));
});

test('20 grade new-sale restriction remains intact', async () => {
  const {lojaId} = await seed({grant: true, extra: true, productId: 'grade'});
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'grade', [
    {productId: 'grade', quantity: 1, size: 'P', color: 'azul', extra: 'fosco'},
  ]), owner), 'permission-denied', GRADE_SALE_NOT_AUTHORIZED);
});

test('21 simple sale regression GREEN', async () => {
  const {base, lojaId} = await seed({productId: 's', stockKind: 'simple', quantidade: 3});
  await executeStockCommand(db, cmd(lojaId, 'sale', 'simple-sale', [
    {productId: 's', quantity: 1},
  ]), owner);
  assert.equal((await base.collection('estoque_produtos').doc('s').get()).data().quantidade, 2);
});

test('22 failed edit zero partial mutation', async () => {
  const {base, lojaId} = await seed({grant: false, variacoes: {P: {'sem-cor': 0}}});
  const before = (await base.collection('estoque_produtos').doc('blocked').get()).data();
  await denied(executeStockCommand(db, cmd(lojaId, 'sale', 'fail-sale', [
    {productId: 'blocked', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner), 'permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
  await denied(executeStockCommand(db, cmd(lojaId, 'adjust', 'fail-adj', [
    {productId: 'blocked', quantity: 9, expectedRevision: 1, size: 'P', color: 'sem-cor'},
  ]), owner), 'failed-precondition', 'Stock protocol unavailable');
  const after = (await base.collection('estoque_produtos').doc('blocked').get()).data();
  assert.equal(after.variacoes.P['sem-cor'], before.variacoes.P['sem-cor']);
  assert.equal(after.stockRevision, before.stockRevision);
  assert.equal((await base.collection('stock_catalog_operations').doc('fail-sale').get()).exists, false);
  assert.match(accessSrc(), /restock is required to remove\/decrease items/);
});
