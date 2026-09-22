/**
 * NO_CONTROL legacy sale/restore bridge — in-memory only (no production writes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  classifyStockControlState,
  INACTIVE_COMPAT_ALLOWED_KINDS,
  STOCK_PROTOCOL_VERSION,
} from '../src/stockCatalogAccess.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, (e) => e.code === code);
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {
    protocolVersion: 1,
    lojaId,
    kind,
    operationId,
    items: [{productId: item.productId || 'lacinho', quantity: item.quantity ?? 1, ...item}],
    ...extra,
  };
}

async function seedNoControl({
  storeHint = 'nathy',
  productId = 'nathy-pratas-e-folheados-anel-lacinho-encanto',
  variation = true,
  withDraft = false,
  withDep = false,
  ownerUid = 'owner',
  control = null,
  grant = null,
} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `${storeHint}_nocontrol_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid, lojaId, nome: storeHint});
  if (control) {
    db.seed(base.collection('stock_catalog_control').doc('state'), control);
  }
  if (grant) {
    db.seed(base.collection('stock_catalog_access').doc(ownerUid), grant);
  }
  const stock = variation
    ? {
        nome: 'Anel Lacinho Encanto',
        quantidade: 2,
        stockKind: 'variation',
        stockRevision: 8,
        stockOperationId: 'a8f4df1a-3b8f-4412-b470-be4ee5b3d6a0',
        variacoes: {'15': {'sem-cor': 1}, '22': {'sem-cor': 1}},
        estoquePorTamanho: {'15': 1, '22': 1},
        tamanhos: ['15', '22'],
      }
    : {
        nome: 'Simples',
        quantidade: 3,
        stockKind: 'simple',
        stockRevision: 1,
        variacoes: {},
      };
  db.seed(base.collection('estoque_produtos').doc(productId), stock);
  if (withDraft) {
    db.seed(base.collection('draft_produtos').doc(productId), {
      nome: stock.nome, publicadoNoCatalogo: true,
    });
  }
  if (withDep) {
    db.seed(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  }
  return {db, base, lojaId, productId};
}

test('classify: absent=NO_CONTROL; active; invalid shapes fail closed', () => {
  assert.equal(classifyStockControlState({exists: false}), 'NO_CONTROL');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 1, mode: 'active', migrationComplete: true}),
  }), 'ACTIVE');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 2, mode: 'active', migrationComplete: true}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 1, mode: 'inactive'}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 1, mode: 'active', migrationComplete: false}),
  }), 'INVALID');
  assert.deepEqual([...INACTIVE_COMPAT_ALLOWED_KINDS], ['sale', 'restore']);
  assert.equal(STOCK_PROTOCOL_VERSION, 1);
});

test('NATHY NO_CONTROL sale size15 Lacinho', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({storeHint: 'nathy'});
  const r = await executeStockCommand(db, intent(lojaId, 'sale', 's15', {
    productId, quantity: 1, size: '15', color: 'sem-cor',
  }), owner);
  assert.equal(r.alreadyApplied, false);
  const after = db.getData(base.collection('estoque_produtos').doc(productId));
  assert.equal(after.quantidade, 1);
  assert.equal(after.variacoes['15']['sem-cor'], 0);
  assert.equal(after.variacoes['22']['sem-cor'], 1);
  assert.equal(after.stockRevision, 9);
  const op = db.getData(base.collection('stock_catalog_operations').doc('s15'));
  assert.equal(op.legacyCompat, true);
});

test('NATHY NO_CONTROL sale size22 Lacinho', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({storeHint: 'nathy'});
  await executeStockCommand(db, intent(lojaId, 'sale', 's22', {
    productId, quantity: 1, size: '22', color: 'sem-cor',
  }), owner);
  const after = db.getData(base.collection('estoque_produtos').doc(productId));
  assert.equal(after.quantidade, 1);
  assert.equal(after.variacoes['15']['sem-cor'], 1);
  assert.equal(after.variacoes['22']['sem-cor'], 0);
});

test('MIRJOIAS NO_CONTROL sale auth + simple decrement', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({
    storeHint: 'mirjoias',
    productId: 'mirjoias-brinco-bolinha-p-semijoia-4',
    variation: false,
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'ms1', {
    productId, quantity: 1,
  }), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc(productId)).quantidade, 2);
});

test('NO_CONTROL restore after sale', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({variation: false});
  await executeStockCommand(db, intent(lojaId, 'sale', 'sale1', {productId, quantity: 1}), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc(productId)).quantidade, 2);
  await executeStockCommand(db, intent(lojaId, 'restore', 'rest1', {productId}, {
    sourceOperationId: 'sale1',
  }), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc(productId)).quantidade, 3);
});

test('NO_CONTROL adjust/replace/unknown blocked', async () => {
  const {db, lojaId, productId} = await seedNoControl({variation: false});
  await denied(executeStockCommand(db, intent(lojaId, 'adjust', 'a1', {
    productId, quantity: 9, expectedRevision: 1,
  }), owner), 'failed-precondition');
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'rep1',
    items: [{productId, expectedRevision: 1}],
    editorial: {nome: 'x'},
    definition: {quantidade: 9, tipoProduto: 'simples'},
  }, owner), 'failed-precondition');
  await denied(executeStockCommand(db, intent(lojaId, 'restock', 'rs1', {
    productId, quantity: 1,
  }), owner), 'failed-precondition');
});

test('ACTIVE sale with grant; without grant denied', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({
    variation: false,
    withDraft: true,
    withDep: true,
    control: {protocolVersion: 1, mode: 'active', migrationComplete: true},
    grant: {enabled: true, permissions: {sale: true, restore: true}},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'act1', {productId, quantity: 1}), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc(productId)).quantidade, 2);
  assert.equal(db.getData(base.collection('stock_catalog_operations').doc('act1')).legacyCompat, false);

  const other = await seedNoControl({
    variation: false,
    withDraft: true,
    withDep: true,
    control: {protocolVersion: 1, mode: 'active', migrationComplete: true},
    grant: null,
  });
  await denied(executeStockCommand(db, intent(other.lojaId, 'sale', 'act2', {
    productId: other.productId, quantity: 1,
  }), owner), 'permission-denied');
});

test('control present wrong version / inactive / migration false blocked', async () => {
  for (const control of [
    {protocolVersion: 2, mode: 'active', migrationComplete: true},
    {protocolVersion: 1, mode: 'inactive'},
    {protocolVersion: 1, mode: 'active', migrationComplete: false},
  ]) {
    const {db, lojaId, productId} = await seedNoControl({
      variation: false, withDraft: true, withDep: true, control,
      grant: {enabled: true, permissions: {sale: true}},
    });
    await denied(executeStockCommand(db, intent(lojaId, 'sale', `bad_${control.mode}_${control.protocolVersion}`, {
      productId, quantity: 1,
    }), owner), 'failed-precondition');
  }
});

test('unauthenticated / wrong tenant blocked', async () => {
  const {db, lojaId, productId} = await seedNoControl({variation: false});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 'u1', {productId}), null), 'unauthenticated');
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 'u2', {productId}), {uid: 'intruder'}), 'permission-denied');
  // Bound to another store id via users doc must not authorize this loja
  db.seed(db.collection('users').doc('other'), {store_id: 'some-other-store'});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 'u3', {productId}), {uid: 'other'}), 'permission-denied');
});

test('sale idempotency same operationId', async () => {
  const {db, base, lojaId, productId} = await seedNoControl({variation: false});
  const cmd = intent(lojaId, 'sale', 'once', {productId, quantity: 1});
  const r1 = await executeStockCommand(db, cmd, owner);
  const r2 = await executeStockCommand(db, cmd, owner);
  assert.equal(r1.alreadyApplied, false);
  assert.equal(r2.alreadyApplied, true);
  assert.equal(db.getData(base.collection('estoque_produtos').doc(productId)).quantidade, 2);
});

test('multi-item NO_CONTROL sale', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `multi_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('estoque_produtos').doc('a'), {
    quantidade: 2, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  db.seed(base.collection('estoque_produtos').doc('b'), {
    quantidade: 5, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'm1',
    items: [
      {productId: 'a', quantity: 1},
      {productId: 'b', quantity: 2},
    ],
  }, owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('a')).quantidade, 1);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('b')).quantidade, 3);
});
