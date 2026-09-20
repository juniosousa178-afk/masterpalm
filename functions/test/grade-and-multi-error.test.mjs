/** Grade sale + consignment + multi-product PRODUCT_VALIDATION_FAILED. In-memory only. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {CODES} from '../src/consignmentProtocol.js';
import {classifyConsignmentProduct, isTrueGrade} from '../src/consignmentStock.js';
import {PRODUCT_VALIDATION_FAILED} from '../src/productValidationErrors.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, e => e.consignmentCode === code || e.stockCode === code || e.code === code);
}

async function seed({extraProducts = [], simpleQty = 5} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `grade_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  db.seed(base.collection('stock_catalog_access').doc('owner'), {
    enabled: true,
    permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true},
  });
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('estoque_produtos').doc('simple'), {
    quantidade: simpleQty, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc('simple'), {nome: 'Anel', publicadoNoCatalogo: true, preco: 100});
  db.seed(base.collection('stock_catalog_dependencies').doc('simple'), {comboIds: []});
  db.seed(base.collection('consignment_resellers').doc('rev1'), {
    storeId: lojaId, resellerId: 'rev1', displayName: 'Maria', active: true, notes: '',
  });
  for (const p of extraProducts) {
    db.seed(base.collection('estoque_produtos').doc(p.id), p.stock);
    db.seed(base.collection('draft_produtos').doc(p.id), p.draft || {nome: p.id, publicadoNoCatalogo: true, preco: 10});
    db.seed(base.collection('stock_catalog_dependencies').doc(p.id), p.dependency || {comboIds: []});
  }
  return {db, base, lojaId};
}

function gradeStock(overrides = {}) {
  return {
    stockKind: 'variation', stockRevision: 0, quantidade: 5,
    variacoes: {P: {Azul: 2, Vermelho: 3}}, tamanhos: ['P'], cores: ['Azul', 'Vermelho'],
    ...overrides,
  };
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {
    protocolVersion: 1, lojaId, operation, operationId,
    ...(consignmentId ? {consignmentId} : {}),
    payload,
  };
}

async function draftAnd(db, lojaId, lines, consignmentId) {
  const id = consignmentId || `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `op_draft_${id}`, {
    resellerId: 'rev1', notes: '', lines,
  }, id), owner);
  return id;
}

function saleIntent(lojaId, operationId, items) {
  return {protocolVersion: 1, lojaId, kind: 'sale', operationId, items};
}

test('false-grade extra-only is NOT true grade (1D / normal variation shape)', () => {
  const stock = {
    stockKind: 'variation', stockRevision: 0, quantidade: 2,
    variacoes: {'sem-tamanho': {Pedra: 2}},
    variacoesExtraTipo: {Pedra: true},
  };
  assert.equal(isTrueGrade(stock), false);
  assert.equal(classifyConsignmentProduct(stock).kind, 'variation');
});

test('true grade size×color classified as grade', () => {
  assert.equal(classifyConsignmentProduct(gradeStock()).kind, 'grade');
});

// --- GRADE SALE ---
test('1-3 safe grade sale decrements exact cell; sibling unchanged', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  await executeStockCommand(db, saleIntent(lojaId, 's1', [
    {productId: 'g', quantity: 1, size: 'P', color: 'Azul'},
  ]), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('g'));
  assert.equal(stock.variacoes.P.Azul, 1);
  assert.equal(stock.variacoes.P.Vermelho, 3);
  assert.equal(stock.quantidade, 4);
});

test('4 insufficient grade stock', async () => {
  const {db, base, lojaId} = await seed({
    extraProducts: [{id: 'g', stock: gradeStock({variacoes: {P: {Azul: 1, Vermelho: 1}}, quantidade: 2})}],
  });
  const before = db.snapshot();
  await denied(executeStockCommand(db, saleIntent(lojaId, 's_insuf', [
    {productId: 'g', quantity: 5, size: 'P', color: 'Azul'},
  ]), owner), PRODUCT_VALIDATION_FAILED);
  assert.deepEqual(db.snapshot(), before);
});

test('5 incomplete grade selection', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const before = db.snapshot();
  await denied(executeStockCommand(db, saleIntent(lojaId, 's_inc', [
    {productId: 'g', quantity: 1, size: 'P'},
  ]), owner), PRODUCT_VALIDATION_FAILED);
  assert.deepEqual(db.snapshot(), before);
});

test('6 missing grade cell', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const before = db.snapshot();
  await denied(executeStockCommand(db, saleIntent(lojaId, 's_miss', [
    {productId: 'g', quantity: 1, size: 'P', color: 'Verde'},
  ]), owner), PRODUCT_VALIDATION_FAILED);
  assert.deepEqual(db.snapshot(), before);
});

test('8 duplicate sale idempotent', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const intent = saleIntent(lojaId, 's_once', [{productId: 'g', quantity: 1, size: 'P', color: 'Azul'}]);
  const a = await executeStockCommand(db, intent, owner);
  const b = await executeStockCommand(db, intent, owner);
  assert.equal(a.alreadyApplied, false);
  assert.equal(b.alreadyApplied, true);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Azul, 1);
});

test('9 mixed simple + grade sale', async () => {
  const {db, base, lojaId} = await seed({
    simpleQty: 5,
    extraProducts: [{id: 'g', stock: gradeStock()}],
  });
  await executeStockCommand(db, saleIntent(lojaId, 's_mix', [
    {productId: 'simple', quantity: 1},
    {productId: 'g', quantity: 1, size: 'P', color: 'Vermelho'},
  ]), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 4);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Vermelho, 2);
});

test('10 valid + invalid sale -> zero writes + all issues', async () => {
  const {db, base, lojaId} = await seed({
    simpleQty: 5,
    extraProducts: [{id: 'g', stock: gradeStock()}],
  });
  const before = db.snapshot();
  await assert.rejects(executeStockCommand(db, saleIntent(lojaId, 's_partial', [
    {productId: 'simple', quantity: 1},
    {productId: 'g', quantity: 1, size: 'P', color: 'Verde'},
    {productId: 'missing', quantity: 1},
  ]), owner), (e) => {
    assert.equal(e.stockCode, PRODUCT_VALIDATION_FAILED);
    assert.equal(e.issues.length, 2);
    return true;
  });
  assert.deepEqual(db.snapshot(), before);
});

// --- MULTI-ERROR SALE ---
test('21 two invalid sale lines both returned', async () => {
  const {db, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  await assert.rejects(executeStockCommand(db, saleIntent(lojaId, 'm2', [
    {productId: 'g', quantity: 1, size: 'P', color: 'Verde'},
    {productId: 'ghost', quantity: 1},
  ]), owner), (e) => e.issues?.length === 2);
});

test('22 five invalid sale lines all returned', async () => {
  const {db, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  await assert.rejects(executeStockCommand(db, saleIntent(lojaId, 'm5', [
    {productId: 'g', quantity: 1, size: 'P', color: 'X'},
    {productId: 'a', quantity: 1},
    {productId: 'b', quantity: 1},
    {productId: 'c', quantity: 1},
    {productId: 'd', quantity: 1},
  ]), owner), (e) => e.issues?.length === 5);
});

test('26 same product two bad grade cells -> both line issues', async () => {
  const {db, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  await assert.rejects(executeStockCommand(db, saleIntent(lojaId, 'm_same', [
    {productId: 'g', quantity: 1, size: 'P', color: 'X'},
    {productId: 'g', quantity: 1, size: 'M', color: 'Azul'},
  ]), owner), (e) => {
    assert.equal(e.issues.length, 2);
    assert.equal(e.issues[0].lineIndex, 0);
    assert.equal(e.issues[1].lineIndex, 1);
    return true;
  });
});

// --- GRADE CONSIGNMENT ---
test('11-14 safe grade issue: cell down, no sale, no finance', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const id = await draftAnd(db, lojaId, [{
    productId: 'g', qtySent: 1, unitSalePrice: 20, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'Azul', extra: ''},
  }]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('g'));
  assert.equal(stock.variacoes.P.Azul, 1);
  assert.equal(stock.variacoes.P.Vermelho, 3);
  assert.equal(db.exists(base.collection('estoque_vendas').doc(`csgn_${id}`)), false);
  assert.equal(db.exists(base.collection('lancamentos_financeiros').doc(`csgn_fin_${id}`)), false);
});

test('15-18 full return restores; sold settles once with sale+finance', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const gradeLine = (color, price) => ({
    productId: 'g', qtySent: 1, unitSalePrice: price, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color, extra: ''},
  });
  const retId = await draftAnd(db, lojaId, [gradeLine('Vermelho', 30)], `ret_${++seq}`);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${retId}`, {}, retId), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Vermelho, 2);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${retId}`, {
    lines: [{productId: 'g', variationKey: {size: 'P', color: 'Vermelho', extra: ''}, qtySold: 0, qtyReturned: 1}],
  }, retId), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Vermelho, 3);

  const soldId = await draftAnd(db, lojaId, [gradeLine('Azul', 40)], `sold_${++seq}`);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${soldId}`, {}, soldId), owner);
  const beforeSold = db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Azul;
  const settle = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${soldId}`, {
    lines: [{productId: 'g', variationKey: {size: 'P', color: 'Azul', extra: ''}, qtySold: 1, qtyReturned: 0}],
  }, soldId), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Azul, beforeSold);
  assert.equal(settle.saleCreated, true);
  assert.equal(settle.financeCreated, true);
  assert.equal(db.exists(base.collection('estoque_vendas').doc(`csgn_${soldId}`)), true);
});

test('19-20 duplicate issue/settlement idempotent', async () => {
  const {db, base, lojaId} = await seed({extraProducts: [{id: 'g', stock: gradeStock()}]});
  const id = await draftAnd(db, lojaId, [{
    productId: 'g', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'Azul', extra: ''},
  }]);
  const i1 = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const i2 = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(i1.alreadyApplied, false);
  assert.equal(i2.alreadyApplied, true);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('g')).variacoes.P.Azul, 1);
  const settlePayload = {
    lines: [{productId: 'g', variationKey: {size: 'P', color: 'Azul', extra: ''}, qtySold: 1, qtyReturned: 0}],
  };
  const s1 = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, settlePayload, id), owner);
  const s2 = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, settlePayload, id), owner);
  assert.equal(s1.alreadyApplied, false);
  assert.equal(s2.alreadyApplied, true);
});

// --- MULTI-ERROR CONSIGNMENT ---
test('24-25 invalid consignation lines all returned; zero writes', async () => {
  const {db, base, lojaId} = await seed({
    simpleQty: 5,
    extraProducts: [{id: 'g', stock: gradeStock()}],
  });
  const before = db.snapshot();
  await assert.rejects(draftAnd(db, lojaId, [
    {productId: 'simple', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0},
    {productId: 'g', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
      variationKey: {size: 'P', color: 'Verde', extra: ''}},
    {productId: 'ghost', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0},
  ]), (e) => {
    assert.equal(e.consignmentCode || e.stockCode, CODES.PRODUCT_VALIDATION_FAILED);
    assert.ok((e.issues || []).length >= 2, `issues=${JSON.stringify(e.issues)} code=${e.consignmentCode} msg=${e.message}`);
    return true;
  });
  assert.deepEqual(db.snapshot(), before);
});

// --- REGRESSION ---
test('normal variation sale + consignment still green', async () => {
  const {db, base, lojaId} = await seed({
    extraProducts: [{
      id: 'varp',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 4,
        variacoes: {P: {'sem-cor': 4}}, tamanhos: ['P'],
      },
    }],
  });
  await executeStockCommand(db, saleIntent(lojaId, 'var_sale', [
    {productId: 'varp', quantity: 1, size: 'P', color: 'sem-cor'},
  ]), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('varp')).variacoes.P['sem-cor'], 3);
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 1, unitSalePrice: 15, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'sem-cor', extra: ''},
  }]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('varp')).variacoes.P['sem-cor'], 2);
});
