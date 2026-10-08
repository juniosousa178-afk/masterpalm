import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {CODES, MAX_PRODUCTS_PER_CONSIGNMENT, mapConsignmentHttp} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

const ids = n => Array.from({length: n}, (_, i) => `P${String(i + 1).padStart(2, '0')}`);

function seedStore(productCount, qty = 1) {
  const lojaId = `plimit_${++seq}`;
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {
    storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Teste', active: true, notes: '',
  });
  for (const id of ids(productCount)) {
    db.seed(base.collection('estoque_produtos').doc(id), {
      lojaId, quantidade: qty, stockKind: 'simple', tipoProduto: 'simples', stockRevision: 3, variacoes: {},
    });
    db.seed(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 10});
    db.seed(base.collection('produtos').doc(id), {nome: `Produto ${id}`, quantidade: qty, preco: 10});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return {db, base, lojaId};
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {protocolVersion: 1, lojaId, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload};
}

const line = productId => ({productId, qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0});
const stock = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));
const isLimit = e => e.consignmentCode === CODES.CONSIGNMENT_PRODUCT_LIMIT && e.code === 'resource-exhausted';

async function createDraft(db, lojaId, productIds) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'r1', notes: '', lines: productIds.map(line),
  }, id), owner);
  return id;
}

test('limit matches the stock transaction budget', () => {
  assert.equal(MAX_PRODUCTS_PER_CONSIGNMENT, 25);
  const mapped = mapConsignmentHttp(Object.assign(new Error('x'), {consignmentCode: CODES.CONSIGNMENT_PRODUCT_LIMIT}));
  assert.equal(mapped.http, 'resource-exhausted');
  assert.equal(mapped.details.consignmentCode, CODES.CONSIGNMENT_PRODUCT_LIMIT);
});

test('createDraft with 26 distinct products is rejected without writes', async () => {
  const {db, lojaId} = seedStore(26);
  const snapshot = db.snapshot();
  await assert.rejects(createDraft(db, lojaId, ids(26)), isLimit);
  assert.deepEqual(db.snapshot(), snapshot);
});

test('25 distinct products can be drafted and issued in one transaction', async () => {
  const {db, base, lojaId} = seedStore(25);
  const id = await createDraft(db, lojaId, ids(25));
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(res.status, 'ISSUED');
  for (const p of ids(25)) assert.equal(stock(db, base, p).quantidade, 0);
  assert.equal(consignment(db, base, id).totalItemsSent, 25);
});

test('updateDraft above the limit is rejected without writes', async () => {
  const {db, base, lojaId} = seedStore(26);
  const id = await createDraft(db, lojaId, ids(3));
  const snapshot = db.snapshot();
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'updateDraft', `upd_${id}`, {lines: ids(26).map(line)}, id), owner),
    isLimit,
  );
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(consignment(db, base, id).lines.length, 3);
});

test('addItems on a draft cannot cross the limit', async () => {
  const {db, base, lojaId} = seedStore(26);
  const id = await createDraft(db, lojaId, ids(25));
  const snapshot = db.snapshot();
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
      expectedRevision: consignment(db, base, id).revision, lines: [line('P26')],
    }, id), owner),
    isLimit,
  );
  assert.deepEqual(db.snapshot(), snapshot);
});

test('addItems on an issued consignment cannot cross the limit and keeps stock', async () => {
  const {db, base, lojaId} = seedStore(26, 2);
  const id = await createDraft(db, lojaId, ids(25));
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const snapshot = db.snapshot();
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
      expectedRevision: consignment(db, base, id).revision, lines: [line('P26')],
    }, id), owner),
    isLimit,
  );
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(stock(db, base, 'P26').quantidade, 2);
});

test('addItems of more units of an existing product is still allowed at the limit', async () => {
  const {db, base, lojaId} = seedStore(25, 3);
  const id = await createDraft(db, lojaId, ids(25));
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: [line('P01')],
  }, id), owner);
  assert.equal(stock(db, base, 'P01').quantidade, 1);
  assert.equal(consignment(db, base, id).totalItemsSent, 26);
});

test('issuing a legacy draft above the limit fails with the specific code and no writes', async () => {
  const {db, base, lojaId} = seedStore(32);
  const id = await createDraft(db, lojaId, ids(25));
  const draft = consignment(db, base, id);
  const extra = ids(32).slice(25).map((productId, i) => ({...draft.lines[0], productId, lineId: `${productId}::legacy${i}`}));
  db.seed(base.collection('consignments').doc(id), {...draft, lines: [...draft.lines, ...extra]});
  const snapshot = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), isLimit);
  assert.deepEqual(db.snapshot(), snapshot);
  for (const p of ids(32)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(db.exists(base.collection('consignment_operations').doc(`issue_${id}`)), false);
});
