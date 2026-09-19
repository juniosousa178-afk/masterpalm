import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  VARIATION_SALE_PRODUCT_GRANT,
  VARIATION_SALE_PRODUCT_GRANTS_COLLECTION,
  VARIATION_SALE_PRODUCT_NOT_AUTHORIZED,
  GRADE_SALE_NOT_AUTHORIZED,
  VARIATION_PRODUCT_STATE_UNSAFE,
  VARIATION_IDENTITY_NOT_RESOLVED,
  isWildcardProductId,
} from '../src/stockCatalogAccess.js';

const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
const db = new Firestore({projectId: 'demo-variation-sale-grant'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};
const customer = {uid: 'customer'};
const variation = {P: {'sem-cor': 2}};

function accessSrc() {
  return readFileSync(new URL('../src/stockCatalogAccess.js', import.meta.url), 'utf8');
}
function commandsSrc() {
  return readFileSync(new URL('../src/stockCatalogCommands.js', import.meta.url), 'utf8');
}
function rulesSrc() {
  return readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
}

async function seed(opts = {}) {
  const lojaId = opts.lojaId ?? `vsg_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const productId = opts.productId ?? 'safe';
  const batch = db.batch();
  batch.set(base, {ownerUid: opts.ownerUid ?? 'owner', name: 'Grant Fixture'});
  const stock = {
    quantidade: opts.quantidade ?? 2,
    stockKind: opts.stockKind ?? 'variation',
    stockRevision: opts.stockRevision ?? 1,
    ...(opts.stock || {}),
  };
  if ((opts.stockKind ?? 'variation') !== 'simple') {
    if (!('variacoes' in stock)) stock.variacoes = opts.variacoes ?? variation;
    if (!('estoquePorTamanho' in stock)) stock.estoquePorTamanho = opts.estoquePorTamanho ?? {P: 2};
  }
  batch.set(base.collection('estoque_produtos').doc(productId), stock);
  batch.set(base.collection('draft_produtos').doc(productId), {nome: 'Peca', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  if (opts.simpleProductId) {
    batch.set(base.collection('estoque_produtos').doc(opts.simpleProductId), {
      quantidade: 3, stockKind: 'simple', stockRevision: 1,
    });
    batch.set(base.collection('draft_produtos').doc(opts.simpleProductId), {nome: 'Simples'});
    batch.set(base.collection('stock_catalog_dependencies').doc(opts.simpleProductId), {comboIds: []});
  }
  if (opts.blockedProductId) {
    batch.set(base.collection('estoque_produtos').doc(opts.blockedProductId), {
      quantidade: 2, stockKind: 'variation', stockRevision: 1,
      variacoes: {M: {'sem-cor': 2}}, estoquePorTamanho: {M: 2},
      variationSaleBlocked: true,
    });
    batch.set(base.collection('draft_produtos').doc(opts.blockedProductId), {nome: 'Bloqueado'});
    batch.set(base.collection('stock_catalog_dependencies').doc(opts.blockedProductId), {comboIds: []});
  }
  if (opts.protocol === 'active') {
    batch.set(base.collection('stock_catalog_control').doc('state'), {
      protocolVersion: 1, mode: 'active', migrationComplete: true,
    });
    batch.set(base.collection('stock_catalog_access').doc('owner'), {
      enabled: true, permissions: {sale: true, restock: true, adjust: true, restore: true},
    });
  }
  if (opts.grant === true) {
    batch.set(base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(productId), {enabled: true});
  } else if (opts.grant && typeof opts.grant === 'object') {
    batch.set(base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(productId), opts.grant);
  }
  if (opts.otherStoreGrant) {
    const other = db.collection('lojas').doc(opts.otherStoreGrant);
    batch.set(other, {ownerUid: 'owner', name: 'Other'});
    batch.set(other.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(productId), {enabled: true});
  }
  await batch.commit();
  return {base, lojaId, productId};
}

function sale(lojaId, operationId, item = {}) {
  const row = {
    productId: item.productId ?? 'safe',
    quantity: item.quantity ?? 1,
    size: item.size ?? 'P',
    color: item.color ?? 'sem-cor',
  };
  if (item.extra) row.extra = item.extra;
  return {
    protocolVersion: 1,
    lojaId,
    kind: 'sale',
    operationId,
    items: [row],
  };
}

async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

test('capability name is variationSaleProductGrant', () => {
  assert.equal(VARIATION_SALE_PRODUCT_GRANT, 'variationSaleProductGrant');
  assert.equal(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION, 'variation_sale_product_grants');
  assert.match(accessSrc(), /variationSaleProductGrant/);
  assert.match(commandsSrc(), /authorizeVariationSaleItems/);
  assert.equal(isWildcardProductId('*'), true);
  assert.equal(isWildcardProductId('safe'), false);
});

test('1 allowed store + allowed product variation sale authorization passes', async () => {
  const {base, lojaId} = await seed({grant: true});
  await executeStockCommand(db, sale(lojaId, 'ok'), owner);
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 1);
  assert.equal(stock.quantidade, 1);
  assert.equal(stock.stockRevision, 2);
});

test('2 allowed store + blocked product denied', async () => {
  const {base, lojaId} = await seed({grant: true, blockedProductId: 'blocked'});
  await denied(executeStockCommand(db, sale(lojaId, 'blk', {productId: 'blocked', size: 'M'}), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.equal((await base.collection('estoque_produtos').doc('blocked').get()).data().variacoes.M['sem-cor'], 2);
});

test('3 wrong store denied', async () => {
  const a = await seed({grant: true, lojaId: `vsg_${runId}_storeA`});
  const b = await seed({grant: false, lojaId: `vsg_${runId}_storeB`, productId: 'safe', ownerUid: 'other-owner'});
  await denied(executeStockCommand(db, sale(b.lojaId, 'ws'), owner),
    'permission-denied', 'Stock operation not authorized for this store');
  assert.equal((await b.base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
  assert.equal((await a.base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc('safe').get()).data().enabled, true);
});

test('4 unknown product denied', async () => {
  const {lojaId} = await seed({grant: true});
  await denied(executeStockCommand(db, sale(lojaId, 'unk', {productId: 'unknown-product'}), owner),
    'failed-precondition');
});

test('5 grant missing healthy product allowed', async () => {
  const {base, lojaId} = await seed({grant: false});
  await executeStockCommand(db, sale(lojaId, 'miss'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 1);
});

test('6 grant false healthy product allowed', async () => {
  const {base, lojaId} = await seed({grant: {enabled: false}});
  await executeStockCommand(db, sale(lojaId, 'falsy'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 1);
});

test('7 customer cannot self-grant', () => {
  assert.match(rulesSrc(), /match \/\{\s*document=\*\*\s*\}\s*\{\s*allow read, write: if false;/);
  assert.doesNotMatch(rulesSrc(), /variation_sale_product_grants/);
  assert.doesNotMatch(accessSrc(), /collection\(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION\).*set\(/);
  assert.doesNotMatch(commandsSrc(), /variation_sale_product_grants'\)\.doc\([^)]+\)\s*,/);
});

test('7b no client grant mutation API in stock command', () => {
  assert.doesNotMatch(accessSrc(), /export async function setVariationSale/);
  assert.doesNotMatch(commandsSrc(), /kind === 'grantVariationSale'/);
  assert.doesNotMatch(commandsSrc(), /kind === 'replace'[\s\S]{0,120}VARIATION_SALE_PRODUCT_GRANTS_COLLECTION/);
});

test('8 grade sale remains denied', async () => {
  const {base, lojaId} = await seed({
    grant: true,
    variacoes: {P: {Azul: {A: 2}}},
    estoquePorTamanho: {P: 2},
  });
  await denied(executeStockCommand(db, sale(lojaId, 'grd', {color: 'Azul', extra: 'A'}), owner),
    'permission-denied', GRADE_SALE_NOT_AUTHORIZED);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('9 no wildcard fallback', async () => {
  const {base, lojaId, productId} = await seed({
    grant: false,
    stock: {variationSaleBlocked: true, quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2}},
  });
  await base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc('*').set({enabled: true});
  await denied(executeStockCommand(db, sale(lojaId, 'wild'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.equal(isWildcardProductId('*'), true);
  assert.equal((await base.collection('estoque_produtos').doc(productId).get()).data().quantidade, 2);
});

test('10 no cross-store leak', async () => {
  const {base, lojaId} = await seed({
    grant: false,
    otherStoreGrant: `vsg_${runId}_leak`,
    stock: {variationSaleBlocked: true, quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2}},
  });
  await denied(executeStockCommand(db, sale(lojaId, 'leak'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('11 simple sale unaffected', async () => {
  const {base, lojaId} = await seed({
    grant: false, simpleProductId: 'plain', stockKind: 'variation',
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sim',
    items: [{productId: 'plain', quantity: 1}],
  }, owner);
  assert.equal((await base.collection('estoque_produtos').doc('plain').get()).data().quantidade, 2);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('13 failed variation sale zero partial mutation', async () => {
  const {base, lojaId} = await seed({grant: true, quantidade: 0, variacoes: {P: {'sem-cor': 0}}, estoquePorTamanho: {P: 0}, stockRevision: 4});
  await denied(executeStockCommand(db, sale(lojaId, 'zero'), owner), 'failed-precondition');
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 0);
  assert.equal(stock.stockRevision, 4);
  assert.equal((await base.collection('stock_catalog_operations').doc('zero').get()).exists, false);
});

test('14 qty decrement exact and 15 stockRevision preserved', async () => {
  const {base, lojaId} = await seed({grant: true, stockRevision: 7, quantidade: 2, variacoes: {P: {'sem-cor': 2}}});
  await executeStockCommand(db, sale(lojaId, 'dec'), owner);
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 1);
  assert.equal(stock.quantidade, 1);
  assert.equal(stock.estoquePorTamanho.P, 1);
  assert.equal(stock.stockRevision, 8);
});

test('16 queue replay unaffected', async () => {
  const {base, lojaId} = await seed({grant: true});
  await executeStockCommand(db, sale(lojaId, 'rp'), owner);
  const again = await executeStockCommand(db, sale(lojaId, 'rp'), owner);
  assert.equal(again.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().variacoes.P['sem-cor'], 1);
});

test('17 replace authorization unaffected', async () => {
  const {base, lojaId} = await seed({grant: false, stockRevision: 1});
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'rep',
    items: [{productId: 'safe', expectedRevision: 1}],
    editorial: {},
    definition: {quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2}},
  }, owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().variacoes.P['sem-cor'], 2);
});

test('18 restock authorization unaffected', async () => {
  const {lojaId} = await seed({grant: false, stockKind: 'simple', quantidade: 1, variacoes: undefined, estoquePorTamanho: {}});
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'restock', operationId: 'rs',
    items: [{productId: 'safe', quantity: 1}],
  }, owner), 'failed-precondition');
});

test('19 reconcile grant unaffected', async () => {
  const {lojaId} = await seed({grant: true, stockRevision: 1});
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'reconcile', operationId: 'rc', reconciliationId: 'rc',
    countedAt: '2026-09-19T12:00:00.000Z',
    items: [{productId: 'safe', expectedRevision: 1, confirmedPhysicalQty: 1, size: 'P', color: 'sem-cor'}],
  }, owner), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('20 historical blocked product ids denied', async () => {
  const blocked = [
    'hive-126', 'hive-132', 'hive-133', 'hive-154', 'hive-172',
    'hive-175', 'hive-194', 'hive-227', 'hive-231',
  ];
  const {lojaId} = await seed({grant: true, productId: 'safe'});
  for (const id of blocked) {
    await denied(executeStockCommand(db, sale(lojaId, `b-${id}`, {productId: id, size: 'M'}), owner),
      'failed-precondition');
  }
});

test('empty allowlist allows healthy variation on NO_CONTROL', async () => {
  const {base, lojaId} = await seed({grant: false});
  await executeStockCommand(db, sale(lojaId, 'empty'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().stockRevision, 2);
});

test('grant does not authorize replace of ungranted store variation', async () => {
  assert.match(commandsSrc(), /if \(command\.kind === 'sale'\) await authorizeVariationSaleItems/);
  assert.doesNotMatch(commandsSrc(), /kind === 'replace'[\s\S]{0,80}authorizeVariationSaleItems/);
});
