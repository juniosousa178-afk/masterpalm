import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {consignmentSizePrices, evaluateConsignmentPickerEligibility} from '../src/consignmentStock.js';
import {
  diagnoseConsignment, expectedVariationPrice, summarizeConsignmentDiagnostics,
} from '../src/consignmentVariationPriceDiagnostic.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const PRICES = {'15': 25.9, '16': 27.9, '17': 30.9};
let seq = 0;

function seedStore() {
  const db = createConsignmentTestDb();
  const lojaId = `varprice_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('maria'), {
    storeId: lojaId, resellerId: 'maria', displayName: 'Maria', active: true, notes: '',
  });
  db.seed(base.collection('estoque_produtos').doc('anel'), {
    lojaId, stockKind: 'variation', stockRevision: 0, quantidade: 9,
    variacoes: {'15': {'sem-cor': 3}, '16': {'sem-cor': 3}, '17': {'sem-cor': 3}},
  });
  db.seed(base.collection('draft_produtos').doc('anel'), {
    nome: 'Anel', publicadoNoCatalogo: true, preco: 25.9, precoPorTamanho: {...PRICES},
  });
  db.seed(base.collection('stock_catalog_dependencies').doc('anel'), {comboIds: []});
  return {db, base, lojaId};
}

const cmd = (lojaId, operation, operationId, payload = {}, consignmentId = null) => ({
  protocolVersion: 1, lojaId, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload,
});
const anelLine = (size, qty = 1) => ({
  productId: 'anel', qtySent: qty, unitSalePrice: PRICES[size],
  commissionType: 'SEM_COMISSAO', commissionValue: 0,
  variationKey: {size, color: 'sem-cor', extra: ''},
});
const doc = (db, base, id) => db.getData(base.collection('consignments').doc(id));
const cellQty = (db, base, size) =>
  db.getData(base.collection('estoque_produtos').doc('anel')).variacoes[size]['sem-cor'];

async function issueAnel(db, lojaId, lines) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {resellerId: 'maria', notes: '', lines}, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  return id;
}

test('picker exposes the store precoPorTamanho (draft first, invalid kept as null)', async () => {
  const {db, lojaId} = seedStore();
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'listEligibleProducts', 'picker_1'), owner);
  const anel = res.products.find(p => p.productId === 'anel');
  assert.deepEqual(anel.precoPorTamanho, PRICES);
  assert.equal(anel.price, 25.9, 'product price unchanged (only inherited by sizes without own price)');
  assert.deepEqual(consignmentSizePrices({precoPorTamanho: {P: 'x', M: 0, G: 12.345}}, null), {P: null, M: null, G: 12.35});
  assert.deepEqual(consignmentSizePrices({}, {precoPorTamanho: {P: 10}}), {P: 10}, 'legacy stock fallback');
  assert.equal(consignmentSizePrices({precoPorTamanho: null}, {precoPorTamanho: {P: 10}}), null, 'draft wins');
});

test('cross-store product never exposes its prices', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'anel', lojaId: 'B',
    stock: {lojaId: 'A', stockKind: 'variation', stockRevision: 0, quantidade: 1, variacoes: {'15': {'sem-cor': 1}}},
    draft: {precoPorTamanho: PRICES}, dependency: {comboIds: []},
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'CROSS_STORE_PRODUCT');
  assert.equal(elig.precoPorTamanho, undefined);
});

test('Anel 15/16/17: one line per variation, own snapshot, total 84.70, stock per cell', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issueAnel(db, lojaId, [anelLine('15'), anelLine('16'), anelLine('17')]);
  const c = doc(db, base, id);
  assert.equal(c.lines.length, 3);
  const bySize = Object.fromEntries(c.lines.map(l => [l.variationKey.size, l]));
  assert.equal(bySize['15'].unitSalePriceSnapshot, 25.9);
  assert.equal(bySize['16'].unitSalePriceSnapshot, 27.9);
  assert.equal(bySize['17'].unitSalePriceSnapshot, 30.9);
  assert.equal(c.potentialGrossAmount, 84.7);
  for (const s of ['15', '16', '17']) assert.equal(cellQty(db, base, s), 2, `cell ${s} moved by 1`);
});

test('qty > 1 multiplies the same variation price; same-price variations stay separate', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issueAnel(db, lojaId, [
    anelLine('17', 2),
    {...anelLine('15'), unitSalePrice: 27.9},
    anelLine('16'),
  ]);
  const c = doc(db, base, id);
  assert.equal(c.lines.length, 3, 'never merged by price');
  assert.equal(c.lines.find(l => l.variationKey.size === '17').potentialGrossAmount, 61.8);
  assert.equal(c.potentialGrossAmount, 117.6);
  assert.equal(cellQty(db, base, '17'), 1);
});

test('price changes after issue never alter the consignment; withdraw + settle use snapshots', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issueAnel(db, lojaId, [anelLine('15'), anelLine('16'), anelLine('17')]);
  const before = doc(db, base, id);
  db.seed(base.collection('draft_produtos').doc('anel'), {
    nome: 'Anel', publicadoNoCatalogo: true, preco: 99, precoPorTamanho: {'15': 50, '16': 60, '17': 70},
  });
  assert.deepEqual(doc(db, base, id).lines, before.lines, 'no recalculation on read');

  const l17 = before.lines.find(l => l.variationKey.size === '17');
  await executeConsignmentCommand(db, cmd(lojaId, 'returnItems', `consignment_return_${id}_1`, {
    expectedRevision: before.revision, reason: 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT',
    lines: [{lineId: l17.lineId, productId: 'anel', variationKey: l17.variationKey, qty: 1}],
  }, id), owner);
  const afterReturn = doc(db, base, id);
  assert.equal(afterReturn.withdrawnGrossAmount, 30.9);
  assert.equal(afterReturn.withdrawals[0].lines[0].unitSalePriceSnapshot, 30.9);
  assert.equal(cellQty(db, base, '17'), 3, 'returned to its own cell');

  const settle = cmd(lojaId, 'settle', `settle_${id}`, {
    lines: afterReturn.lines.map(l => ({
      lineId: l.lineId, productId: l.productId, variationKey: l.variationKey,
      qtySold: l.variationKey.size === '17' ? 0 : 1, qtyReturned: 0,
    })),
  }, id);
  await executeConsignmentCommand(db, settle, owner);
  const sale = db.getData(base.collection('estoque_vendas').doc(`csgn_${id}`));
  assert.equal(sale.total, 53.8);
  assert.deepEqual(sale.itens.map(i => [i.tamanho, i.precoUnitario, i.precoTotal]).sort(),
    [['15', 25.9, 25.9], ['16', 27.9, 27.9]]);
  const settled = doc(db, base, id);
  assert.equal(settled.grossSoldAmount, 53.8);

  await executeConsignmentCommand(db, settle, owner);
  assert.deepEqual(doc(db, base, id), settled, 'settle retry is a replay');
  assert.equal((await base.collection('estoque_vendas').get()).size, 1);
});

test('diagnostic mirrors the resolver: exact, normalized, inherited, ambiguous', () => {
  assert.deepEqual(expectedVariationPrice({table: PRICES, size: '16', basePrice: 25.9}), {price: 27.9, source: 'VARIATION'});
  assert.deepEqual(expectedVariationPrice({table: {'Tam 1': 10}, size: 'tam1', basePrice: 5}), {price: 10, source: 'VARIATION'});
  assert.deepEqual(expectedVariationPrice({table: PRICES, size: '18', basePrice: 25.9}), {price: 25.9, source: 'INHERITED'});
  assert.equal(expectedVariationPrice({table: {'15': null}, size: '15', basePrice: 25.9}).price, null);
  assert.equal(expectedVariationPrice({table: {'p ': 10, ' p': 11}, size: 'P', basePrice: 5}).price, null);
  assert.equal(expectedVariationPrice({table: PRICES, size: '18', basePrice: 0}).price, null);
});

test('diagnostic is read-only and flags old min-priced consignments only', () => {
  const products = new Map([['anel', {draft: {preco: 25.9, precoPorTamanho: PRICES}, stock: null}]]);
  const legacy = {
    status: 'ISSUED',
    lines: ['15', '16', '17'].map(size => ({
      productId: 'anel', qtySent: 1, unitSalePriceSnapshot: 25.9, variationKey: {size, color: 'sem-cor', extra: ''},
    })),
  };
  const frozen = JSON.stringify(legacy);
  const bad = diagnoseConsignment(legacy, products);
  assert.equal(JSON.stringify(legacy), frozen, 'input untouched');
  assert.equal(bad.affected, true);
  assert.equal(bad.mismatchedLines, 2);
  assert.equal(bad.sameSnapshotGroups, 1);
  assert.equal(bad.divergenceCents, 200 + 500);

  const fixed = {
    status: 'SETTLED',
    lines: ['15', '16', '17'].map(size => ({
      productId: 'anel', qtySent: 1, unitSalePriceSnapshot: PRICES[size], variationKey: {size, color: 'sem-cor', extra: ''},
    })),
  };
  const simple = {status: 'ISSUED', lines: [{productId: 'x', qtySent: 2, unitSalePriceSnapshot: 10}]};
  const summary = summarizeConsignmentDiagnostics([
    {status: legacy.status, result: bad},
    {status: fixed.status, result: diagnoseConsignment(fixed, products)},
    {status: simple.status, result: diagnoseConsignment(simple, products)},
  ]);
  assert.equal(summary.consignmentsScanned, 3);
  assert.equal(summary.consignmentsWithVariationProducts, 2);
  assert.equal(summary.potentiallyAffectedConsignments, 1);
  assert.deepEqual(summary.affectedByStatus, {ISSUED: 1});
});
