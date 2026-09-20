/** Draft-gate: editorial draft optional for internal consignment resolution. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateConsignmentPickerEligibility,
  loadConsignmentStockRecords,
  classifyConsignmentProduct,
} from '../src/consignmentStock.js';
import {CODES} from '../src/consignmentProtocol.js';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const lojaId = 'draft_gate_store';
let seq = 0;

function baseStock(overrides = {}) {
  return {
    quantidade: 3, stockKind: 'simple', stockRevision: 0, variacoes: {},
    nome: 'Produto Interno', preco: 50, lojaId,
    ...overrides,
  };
}

function dep() {
  return {comboIds: []};
}

test('1 authoritative simple + no draft -> resolvable', () => {
  const stock = baseStock();
  const elig = evaluateConsignmentPickerEligibility({
    productId: 's1', lojaId, stock, draft: undefined, dependency: dep(),
  });
  assert.equal(elig.eligible, true);
  assert.equal(elig.name, 'Produto Interno');
  assert.equal(elig.reason, '');
});

test('2 authoritative variation + no draft -> resolvable', () => {
  const stock = baseStock({
    stockKind: 'variation', quantidade: 4,
    variacoes: {'sem-tamanho': {Ouro: 4}},
    nome: 'Var Interna',
  });
  assert.equal(classifyConsignmentProduct(stock).kind, 'variation');
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'v1', lojaId, stock, draft: null, dependency: dep(),
  });
  assert.equal(elig.eligible, true);
  assert.equal(elig.name, 'Var Interna');
});

test('3 authoritative grade + no draft -> resolvable', () => {
  const stock = baseStock({
    stockKind: 'variation', quantidade: 5,
    variacoes: {P: {Azul: 2, Vermelho: 3}},
    tamanhos: ['P'], cores: ['Azul', 'Vermelho'],
    nome: 'Grade Interna',
  });
  assert.equal(classifyConsignmentProduct(stock).kind, 'grade');
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'g1', lojaId, stock, dependency: dep(),
  });
  assert.equal(elig.eligible, true);
});

test('4 missing authoritative product -> PRODUCT_NOT_FOUND', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'missing', lojaId, stock: null, draft: {nome: 'X'}, dependency: dep(),
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'PRODUCT_NOT_FOUND');
});

test('5 cross-store product -> denied', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'x1', lojaId, stock: baseStock({lojaId: 'other'}), dependency: dep(),
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'CROSS_STORE_PRODUCT');
});

test('6 draft absent does not bypass invalid stock', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'inv', lojaId,
    stock: baseStock({pendingSoftDelete: true}),
    dependency: dep(),
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'INVALID_STOCK_STATE');
});

test('7 draft absent does not bypass missing dependency', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'md', lojaId, stock: baseStock(), dependency: null,
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'MISSING_DEPENDENCY');
});

test('8 draft absent does not bypass ambiguous variation / unsafe stockKind', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'amb', lojaId,
    stock: {quantidade: 1, stockRevision: 0, nome: 'X'}, // no stockKind
    dependency: dep(),
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'MISSING_STOCK_METADATA');
});

test('9 draft absent does not bypass invalid grade classify failure', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'badg', lojaId,
    stock: {
      stockKind: 'simple', stockRevision: 0, quantidade: 1,
      variacoes: {P: {Azul: 1}}, nome: 'Conflict',
    },
    dependency: dep(),
  });
  assert.equal(elig.eligible, false);
  assert.ok(['INVALID_STOCK_STATE', 'PRODUCT_STATE_UNSAFE'].includes(elig.reason));
});

test('10 public catalog inactive -> internal product still resolvable', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'pc', lojaId, stock: baseStock(),
    draft: {nome: 'Cat', publicadoNoCatalogo: false, catalog_ativo: false, ativo: false},
    dependency: dep(),
  });
  assert.equal(elig.eligible, true);
});

test('11 draft.ativo=false -> does not by itself block consignment', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'da', lojaId, stock: baseStock(),
    draft: {nome: 'Draft Inativo', ativo: false},
    dependency: dep(),
  });
  assert.equal(elig.eligible, true);
});

test('12 existing normal draft-backed product regression GREEN', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'ok', lojaId, stock: baseStock({nome: 'StockName'}),
    draft: {nome: 'DraftName', preco: 99, publicadoNoCatalogo: true},
    dependency: dep(),
  });
  assert.equal(elig.eligible, true);
  assert.equal(elig.name, 'DraftName');
  assert.equal(elig.price, 99);
});

test('loadConsignmentStockRecords accepts stock without draft', async () => {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('estoque_produtos').doc('nodraft'), baseStock());
  db.seed(base.collection('stock_catalog_dependencies').doc('nodraft'), dep());
  await db.runTransaction(async (tx) => {
    const records = await loadConsignmentStockRecords(tx, base, ['nodraft']);
    assert.equal(records.has('nodraft'), true);
    assert.equal(records.get('nodraft').draftExisted, false);
  });
});

test('loadConsignmentStockRecords still requires authoritative stock', async () => {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('draft_produtos').doc('onlydraft'), {nome: 'Only'});
  db.seed(base.collection('stock_catalog_dependencies').doc('onlydraft'), dep());
  await assert.rejects(
    db.runTransaction((tx) => loadConsignmentStockRecords(tx, base, ['onlydraft'])),
    (e) => e.consignmentCode === CODES.PRODUCT_NOT_FOUND,
  );
});

test('issue works for authoritative product without draft', async () => {
  const db = createConsignmentTestDb();
  const lid = `nd_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lid);
  db.seed(base, {ownerUid: 'owner', lojaId: lid, nome: 'Master'});
  db.seed(base.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  db.seed(base.collection('stock_catalog_access').doc('owner'), {
    enabled: true,
    permissions: {
      sale: true, restock: true, adjust: true, restore: true, editorial: true,
      publish: true, create: true, delete: true, undo: true,
    },
  });
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('estoque_produtos').doc('simple'), baseStock({lojaId: lid, quantidade: 5}));
  db.seed(base.collection('stock_catalog_dependencies').doc('simple'), dep());
  // intentionally NO draft_produtos
  db.seed(base.collection('consignment_resellers').doc('rev1'), {
    storeId: lid, resellerId: 'rev1', displayName: 'Maria', active: true, notes: '',
  });
  const cid = `c_${++seq}`;
  await executeConsignmentCommand(db, {
    protocolVersion: 1, lojaId: lid, operation: 'createDraft', operationId: `op_d_${cid}`,
    consignmentId: cid,
    payload: {
      resellerId: 'rev1', notes: '',
      lines: [{
        productId: 'simple', qtySent: 1, unitSalePrice: 50,
        commissionType: 'SEM_COMISSAO', commissionValue: 0, notes: '',
      }],
    },
  }, owner);
  await executeConsignmentCommand(db, {
    protocolVersion: 1, lojaId: lid, operation: 'issue', operationId: `op_i_${cid}`,
    consignmentId: cid, payload: {},
  }, owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('simple'));
  assert.equal(stock.quantidade, 4);
  // draft must NOT be auto-created by consignment persist
  assert.equal(db.exists(base.collection('draft_produtos').doc('simple')), false);
});
