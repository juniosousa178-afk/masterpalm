/** deleteCancelled: soft delete of CANCELLED consignments only. In-memory, no production writes. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {CODES, mapConsignmentHttp} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function seedStore() {
  const lojaId = `del_${++seq}`;
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {
    storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Teste', active: true, notes: '',
  });
  for (const id of ['P1', 'P2']) {
    db.seed(base.collection('estoque_produtos').doc(id), {
      lojaId, quantidade: 3, stockKind: 'simple', tipoProduto: 'simples', stockRevision: 2, variacoes: {},
    });
    db.seed(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 10});
    db.seed(base.collection('produtos').doc(id), {nome: `Produto ${id}`, quantidade: 3, preco: 10});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return {db, base, lojaId};
}

const cmd = (lojaId, operation, operationId, consignmentId, payload = {}) =>
  ({protocolVersion: 1, lojaId, operation, operationId, consignmentId, payload});
const line = productId => ({productId, qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0});

async function draft(db, lojaId) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, id, {
    resellerId: 'r1', notes: '', lines: [line('P1'), line('P2')],
  }), owner);
  return id;
}
async function cancelled(db, lojaId) {
  const id = await draft(db, lojaId);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${id}`, id), owner);
  return id;
}
const del = (db, lojaId, id, opId = `delete_${id}`, auth = owner) =>
  executeConsignmentCommand(db, cmd(lojaId, 'deleteCancelled', opId, id), auth);

function stockState(db, lojaId) {
  return [...db.snapshot()].filter(([path]) =>
    /\/(estoque_produtos|draft_produtos|produtos|stock_catalog_operations|stock_catalog_dependencies)\//.test(path)
    && path.startsWith(`lojas/${lojaId}/`));
}
const collection = (db, lojaId, name) =>
  [...db.snapshot()].filter(([path]) => path.startsWith(`lojas/${lojaId}/${name}/`));
const isNotAllowed = e => e.consignmentCode === CODES.CONSIGNMENT_DELETE_NOT_ALLOWED && e.code === 'failed-precondition';

test('cancelled consignment is soft-deleted; document, history and stock preserved', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await cancelled(db, lojaId);
  const before = db.getData(base.collection('consignments').doc(id));
  const stockBefore = stockState(db, lojaId);
  const opsBefore = collection(db, lojaId, 'consignment_operations');

  const res = await del(db, lojaId, id);
  assert.equal(res.isDeleted, true);
  assert.equal(res.alreadyApplied, false);
  assert.deepEqual(db.lastCommit, {writes: 3, transforms: 3}, 'consignment + audit + operation only');

  const after = db.getData(base.collection('consignments').doc(id));
  assert.equal(after.status, 'CANCELLED');
  assert.equal(after.isDeleted, true);
  assert.equal(after.deletedBy, 'owner');
  assert.ok(after.deletedAt instanceof Date);
  assert.equal(after.revision, before.revision + 1);
  assert.deepEqual(after.lines, before.lines);
  assert.deepEqual(after.additions, before.additions);
  assert.equal(after.issueOperationId, null);

  assert.deepEqual(stockState(db, lojaId), stockBefore, 'STOCK_COMMAND_COUNT=0');
  for (const [path, data] of opsBefore) assert.deepEqual(db._store.get(path), data, 'earlier operations untouched');
  const audit = db.getData(base.collection('consignment_audit').doc(`delete_${id}`));
  assert.equal(audit.type, 'CONSIGNMENT_DELETE_CANCELLED');
  assert.deepEqual(audit.affectedProducts, []);
  assert.equal(audit.consignmentId, id);
});

test('repeated delete is idempotent (same and new operation ids)', async () => {
  const {db, lojaId} = seedStore();
  const id = await cancelled(db, lojaId);
  await del(db, lojaId, id);
  const snap = db.snapshot();
  const replay = await del(db, lojaId, id);
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), snap);

  const other = await del(db, lojaId, id, `delete_${id}_again`);
  assert.equal(other.isDeleted, true);
  assert.equal(collection(db, lojaId, 'consignment_audit').length, 1, 'no second audit entry');
  assert.deepEqual(stockState(db, lojaId), [...snap].filter(([p]) =>
    /\/(estoque_produtos|draft_produtos|produtos|stock_catalog_operations|stock_catalog_dependencies)\//.test(p)));
});

test('DRAFT delete blocked before any write', async () => {
  const {db, lojaId} = seedStore();
  const id = await draft(db, lojaId);
  const snap = db.snapshot();
  await assert.rejects(del(db, lojaId, id), isNotAllowed);
  assert.deepEqual(db.snapshot(), snap);
});

test('ISSUED delete blocked; stock untouched', async () => {
  const {db, lojaId} = seedStore();
  const id = await draft(db, lojaId);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, id), owner);
  const snap = db.snapshot();
  await assert.rejects(del(db, lojaId, id), isNotAllowed);
  assert.deepEqual(db.snapshot(), snap);
});

test('SETTLED delete blocked', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await draft(db, lojaId);
  const doc = db.getData(base.collection('consignments').doc(id));
  db.seed(base.collection('consignments').doc(id), {...doc, status: 'SETTLED'});
  const snap = db.snapshot();
  await assert.rejects(del(db, lojaId, id), isNotAllowed);
  assert.deepEqual(db.snapshot(), snap);
});

test('cross-tenant delete denied', async () => {
  const a = seedStore();
  const id = await cancelled(a.db, a.lojaId);
  const db = a.db;
  const otherLoja = `del_other_${++seq}`;
  const other = db.collection('lojas').doc(otherLoja);
  db.seed(other, {ownerUid: 'intruder', lojaId: otherLoja});
  db.seed(other.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  const snap = db.snapshot();

  await assert.rejects(del(db, a.lojaId, id, `delete_${id}`, {uid: 'intruder'}),
    e => e.consignmentCode === CODES.AUTH && e.code === 'permission-denied');
  await assert.rejects(del(db, otherLoja, id, `delete_${id}`, {uid: 'intruder'}),
    e => e.consignmentCode === CODES.NOT_FOUND);
  const foreign = `foreign_${seq}`;
  db.seed(a.base.collection('consignments').doc(foreign), {id: foreign, storeId: otherLoja, status: 'CANCELLED', revision: 2});
  await assert.rejects(del(db, a.lojaId, foreign), e => e.consignmentCode === CODES.AUTH);
  const {isDeleted} = db.getData(a.base.collection('consignments').doc(id));
  assert.equal(isDeleted, undefined);
  assert.equal(snap.get(`lojas/${a.lojaId}/consignments/${id}`).isDeleted, undefined);
});

test('delete error maps to failed-precondition without SERVER', () => {
  const mapped = mapConsignmentHttp(Object.assign(new Error('x'), {consignmentCode: CODES.CONSIGNMENT_DELETE_NOT_ALLOWED}));
  assert.equal(mapped.http, 'failed-precondition');
  assert.equal(mapped.details.consignmentCode, CODES.CONSIGNMENT_DELETE_NOT_ALLOWED);
});
