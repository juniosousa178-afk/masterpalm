/** hideTotalReturn: soft hide of SETTLED consignments closed with total return only. In-memory, no production writes. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand, totalReturnIneligibility} from '../src/consignmentCommand.js';
import {CODES} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function seedStore() {
  const db = createConsignmentTestDb();
  const lojaId = `hide_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('maria'), {
    storeId: lojaId, resellerId: 'maria', displayName: 'Maria', active: true, notes: '',
  });
  for (const id of ['A', 'B', 'C']) {
    db.seed(base.collection('estoque_produtos').doc(id), {quantidade: 10, stockKind: 'simple', stockRevision: 0, variacoes: {}});
    db.seed(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 100});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return {db, base, lojaId};
}

const cmd = (lojaId, operation, operationId, consignmentId, payload = {}) =>
  ({protocolVersion: 1, lojaId, operation, operationId, consignmentId, payload});
const line = (productId, qty) =>
  ({productId, qtySent: qty, unitSalePrice: 100, commissionType: 'PERCENTUAL', commissionValue: 10});
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));

async function draft(db, lojaId, lines) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, id, {resellerId: 'maria', notes: '', lines}), owner);
  return id;
}
async function issued(db, lojaId, lines) {
  const id = await draft(db, lojaId, lines);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, id), owner);
  return id;
}
async function withdraw(db, base, lojaId, id, lineIndex, qty) {
  const doc = consignment(db, base, id);
  const l = doc.lines[lineIndex];
  await executeConsignmentCommand(db, cmd(lojaId, 'returnItems', `consignment_return_${id}_${++seq}`, id, {
    expectedRevision: doc.revision,
    lines: [{lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty}],
  }), owner);
}
async function settle(db, base, lojaId, id, sold = () => 0) {
  const doc = consignment(db, base, id);
  const lines = doc.lines.map((l, i) => {
    const outstanding = l.qtySent - (l.qtyWithdrawn || 0);
    const qtySold = sold(i, outstanding);
    return {lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qtySold, qtyReturned: outstanding - qtySold};
  });
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, id, {lines}), owner);
}
const hide = (db, lojaId, id, opId = `hide_total_return_${id}`, auth = owner) =>
  executeConsignmentCommand(db, cmd(lojaId, 'hideTotalReturn', opId, id), auth);

const collection = (db, lojaId, name) =>
  [...db.snapshot()].filter(([path]) => path.startsWith(`lojas/${lojaId}/${name}/`));
const STOCK = /\/(estoque_produtos|draft_produtos|produtos|stock_catalog_operations|stock_catalog_dependencies)\//;
const SALES = /\/(estoque_vendas|vendas|lancamentos_financeiros|contas_receber)\//;
const stockState = (db, lojaId) => [...db.snapshot()].filter(([p]) => STOCK.test(p) && p.startsWith(`lojas/${lojaId}/`));
const salesState = (db, lojaId) => [...db.snapshot()].filter(([p]) => SALES.test(p) && p.startsWith(`lojas/${lojaId}/`));
const notAllowed = e => e.consignmentCode === CODES.CONSIGNMENT_DELETE_NOT_ALLOWED && e.code === 'failed-precondition';

async function assertRejectedWithoutWrites(db, promise, reason = '') {
  const snap = db.snapshot();
  await assert.rejects(promise, e => notAllowed(e) && e.message.includes(reason));
  assert.deepEqual(db.snapshot(), snap, 'no write on rejection');
}

test('settled total return is hidden; only consignment metadata, audit and operation are written', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 2), line('B', 1)]);
  await settle(db, base, lojaId, id);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('A')).quantidade, 10, 'settlement restored stock');
  const before = consignment(db, base, id);
  const stockBefore = stockState(db, lojaId);
  const salesBefore = salesState(db, lojaId);
  const opsBefore = collection(db, lojaId, 'consignment_operations');
  const auditsBefore = collection(db, lojaId, 'consignment_audit');

  const res = await hide(db, lojaId, id);
  assert.equal(res.isDeleted, true);
  assert.equal(res.status, 'SETTLED');
  assert.deepEqual(db.lastCommit, {writes: 3, transforms: 3}, 'consignment + audit + operation only');

  assert.deepEqual(stockState(db, lojaId), stockBefore, 'STOCK_WRITE_COUNT_ON_HIDE=0');
  assert.deepEqual(salesState(db, lojaId), salesBefore, 'SALE/FINANCIAL_WRITE_COUNT_ON_HIDE=0');
  for (const [path, data] of [...opsBefore, ...auditsBefore]) assert.deepEqual(db._store.get(path), data, 'history untouched');

  const after = consignment(db, base, id);
  assert.ok(after, 'HARD_DELETE_COUNT=0');
  assert.equal(after.isDeleted, true);
  assert.equal(after.deletedBy, 'owner');
  assert.equal(after.deletedReason, 'TOTAL_RETURN');
  assert.ok(after.deletedAt instanceof Date);
  assert.equal(after.revision, before.revision + 1);
  const {isDeleted, deletedAt, deletedBy, deletedReason, revision, ...kept} = after;
  const {revision: _r, ...keptBefore} = before;
  assert.deepEqual(kept, keptBefore, 'lines, additions, withdrawals and settlement data preserved');

  const audit = db.getData(base.collection('consignment_audit').doc(`hide_total_return_${id}`));
  assert.equal(audit.type, 'CONSIGNMENT_HIDE_TOTAL_RETURN');
  assert.equal(audit.settlementOperationId, `settle_${id}`);
  assert.equal(audit.returned, 3);
  assert.deepEqual(audit.affectedProducts, []);
});

test('total return through pre-settlement withdrawal plus settlement return', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 3), line('B', 1)]);
  await withdraw(db, base, lojaId, id, 0, 2);
  await settle(db, base, lojaId, id);
  const stockBefore = stockState(db, lojaId);
  await hide(db, lojaId, id);
  assert.equal(consignment(db, base, id).isDeleted, true);
  assert.deepEqual(stockState(db, lojaId), stockBefore);
});

test('total return where every piece was withdrawn before a zero settlement', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 1)]);
  await withdraw(db, base, lojaId, id, 0, 1);
  await settle(db, base, lojaId, id);
  await hide(db, lojaId, id);
  assert.equal(consignment(db, base, id).isDeleted, true);
});

test('settled with any sold piece cannot be hidden', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 2), line('B', 1)]);
  await settle(db, base, lojaId, id, i => (i === 1 ? 1 : 0));
  await assertRejectedWithoutWrites(db, hide(db, lojaId, id), 'HAS_SALE');
});

test('open consignments cannot be hidden: DRAFT, ISSUED and partially withdrawn ISSUED', async () => {
  const {db, base, lojaId} = seedStore();
  const d = await draft(db, lojaId, [line('A', 1)]);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, d));
  const i = await issued(db, lojaId, [line('A', 2)]);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, i));
  await withdraw(db, base, lojaId, i, 0, 1);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, i));
});

test('cancelled consignments keep using deleteCancelled; each command refuses the other state', async () => {
  const {db, base, lojaId} = seedStore();
  const c = await draft(db, lojaId, [line('A', 1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${c}`, c), owner);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, c));
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'deleteCancelled', `delete_${c}`, c), owner);
  assert.equal(res.isDeleted, true);
  assert.equal(db.getData(base.collection('consignment_audit').doc(`delete_${c}`)).type, 'CONSIGNMENT_DELETE_CANCELLED');

  const s = await issued(db, lojaId, [line('B', 1)]);
  await settle(db, base, lojaId, s);
  await assertRejectedWithoutWrites(db, executeConsignmentCommand(db, cmd(lojaId, 'deleteCancelled', `delete_${s}`, s), owner));
});

test('forged documents are refused by the server even when the label says SETTLED', async () => {
  const {db, base, lojaId} = seedStore();
  const ref = id => base.collection('consignments').doc(id);

  // Sold settlement rewritten to look like a total return: audit, sale and finance still prove the sale.
  const sold = await issued(db, lojaId, [line('A', 2)]);
  await settle(db, base, lojaId, sold, () => 1);
  const soldDoc = consignment(db, base, sold);
  db.seed(ref(sold), {
    ...soldDoc, saleId: null, financeId: null, totalItemsSold: 0, totalItemsReturned: 2,
    grossSoldAmount: 0, commissionAmount: 0, netAmount: 0,
    lines: soldDoc.lines.map(l => ({...l, qtySold: 0, qtyReturned: 2})),
  });
  await assertRejectedWithoutWrites(db, hide(db, lojaId, sold), 'SETTLEMENT_AUDIT_MISMATCH');
  const soldAudit = base.collection('consignment_audit').doc(`settle_${sold}`);
  db.seed(soldAudit, {...db.getData(soldAudit), sold: 0, returned: 2, saleId: null, financeId: null});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, sold), 'HAS_SALE');

  // Status flipped to SETTLED without any settlement operation.
  const flipped = await issued(db, lojaId, [line('B', 1)]);
  const flippedDoc = consignment(db, base, flipped);
  db.seed(ref(flipped), {
    ...flippedDoc, status: 'SETTLED', settlementOperationId: `settle_${flipped}`,
    lines: flippedDoc.lines.map(l => ({...l, qtySold: 0, qtyReturned: l.qtySent})), totalItemsReturned: 1,
  });
  await assertRejectedWithoutWrites(db, hide(db, lojaId, flipped), 'SETTLEMENT_AUDIT_MISMATCH');

  // Withdrawal recorded on the line but missing from the withdrawal history.
  const w = await issued(db, lojaId, [line('C', 2)]);
  await withdraw(db, base, lojaId, w, 0, 1);
  await settle(db, base, lojaId, w);
  const wDoc = consignment(db, base, w);
  db.seed(ref(w), {...wDoc, withdrawals: []});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, w), 'WITHDRAWAL_MISMATCH');
  const wAudit = base.collection('consignment_audit').doc(wDoc.withdrawals[0].withdrawalId);
  db.seed(ref(w), wDoc);
  db.seed(wAudit, {...db.getData(wAudit), returnedItems: 2});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, w), 'WITHDRAWAL_AUDIT_MISMATCH');
});

test('repeated hide is idempotent (same and new operation ids)', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 1)]);
  await settle(db, base, lojaId, id);
  await hide(db, lojaId, id);
  const snap = db.snapshot();
  const replay = await hide(db, lojaId, id);
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), snap);
  const again = await hide(db, lojaId, id, `hide_total_return_${id}_again`);
  assert.equal(again.isDeleted, true);
  assert.equal(collection(db, lojaId, 'consignment_audit').filter(([, d]) => d.type === 'CONSIGNMENT_HIDE_TOTAL_RETURN').length, 1);
  assert.deepEqual(stockState(db, lojaId), [...snap].filter(([p]) => STOCK.test(p)));
});

test('hidden consignment stays closed: settle and returnItems still refused', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 1)]);
  await settle(db, base, lojaId, id);
  await hide(db, lojaId, id);
  const doc = consignment(db, base, id);
  const l = doc.lines[0];
  const snap = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle2_${id}`, id, {lines: []}), owner));
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'returnItems', `ret_${id}`, id, {
    expectedRevision: doc.revision, lines: [{lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1}],
  }), owner));
  assert.deepEqual(db.snapshot(), snap);
});

test('cross-tenant hide denied', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 1)]);
  await settle(db, base, lojaId, id);
  const otherLoja = `hide_other_${++seq}`;
  const other = db.collection('lojas').doc(otherLoja);
  db.seed(other, {ownerUid: 'intruder', lojaId: otherLoja});
  db.seed(other.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  const snap = db.snapshot();
  await assert.rejects(hide(db, lojaId, id, `hide_total_return_${id}`, {uid: 'intruder'}),
    e => e.consignmentCode === CODES.AUTH);
  await assert.rejects(hide(db, otherLoja, id, `hide_total_return_${id}`, {uid: 'intruder'}),
    e => e.consignmentCode === CODES.NOT_FOUND);
  assert.deepEqual(db.snapshot(), snap);
});

test('fail-closed matrix A-I: every refusal writes nothing', async () => {
  const {db, base, lojaId} = seedStore();
  const ref = id => base.collection('consignments').doc(id);
  const totalReturn = async () => {
    const id = await issued(db, lojaId, [line('A', 1)]);
    await settle(db, base, lojaId, id);
    return id;
  };

  const a = await issued(db, lojaId, [line('A', 1)]);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, a));
  const b = await draft(db, lojaId, [line('A', 1)]);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, b));
  const c = await issued(db, lojaId, [line('B', 2)]);
  await settle(db, base, lojaId, c, () => 1);
  await assertRejectedWithoutWrites(db, hide(db, lojaId, c), 'HAS_SALE');
  const d = await totalReturn();
  db.seed(ref(d), {...consignment(db, base, d), grossSoldAmount: 0.01});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, d), 'HAS_SALE');
  const e = await issued(db, lojaId, [line('C', 2)]);
  await withdraw(db, base, lojaId, e, 0, 1);
  await settle(db, base, lojaId, e);
  const eAudit = base.collection('consignment_audit').doc(consignment(db, base, e).withdrawals[0].withdrawalId);
  db.seed(eAudit, {...db.getData(eAudit), consignmentId: 'other'});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, e), 'WITHDRAWAL_AUDIT_MISMATCH');
  const f = await totalReturn();
  const fAudit = base.collection('consignment_audit').doc(`settle_${f}`);
  db.seed(fAudit, {...db.getData(fAudit), sold: 1});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, f), 'SETTLEMENT_AUDIT_MISMATCH');
  const g = await totalReturn();
  db.seed(base.collection('estoque_vendas').doc(`csgn_${g}`), {origem: 'consignacao'});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, g), 'HAS_SALE');
  const h = await totalReturn();
  db.seed(base.collection('lancamentos_financeiros').doc(`csgn_fin_${h}`), {origem: 'consignacao'});
  await assertRejectedWithoutWrites(db, hide(db, lojaId, h), 'HAS_SALE');
  const i = await totalReturn();
  const snap = db.snapshot();
  await assert.rejects(hide(db, lojaId, i, `hide_total_return_${i}`, {uid: 'intruder'}), err => err.consignmentCode === CODES.AUTH);
  assert.deepEqual(db.snapshot(), snap);

  for (const id of [a, b, c, d, e, f, g, h, i]) assert.notEqual(consignment(db, base, id).isDeleted, true, id);
});

test('concurrent hides apply once; a sale created mid-transaction makes the retry refuse', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issued(db, lojaId, [line('A', 1)]);
  await settle(db, base, lojaId, id);
  const settledRevision = consignment(db, base, id).revision;
  const results = await Promise.all([
    hide(db, lojaId, id, `hide_total_return_${id}`),
    hide(db, lojaId, id, `hide_total_return_${id}_tab2`),
  ]);
  assert.ok(results.every(r => r.isDeleted === true));
  assert.equal(collection(db, lojaId, 'consignment_audit').filter(([, d]) => d.type === 'CONSIGNMENT_HIDE_TOTAL_RETURN').length, 1);
  assert.equal(consignment(db, base, id).revision, settledRevision + 1);

  const raced = await issued(db, lojaId, [line('B', 1)]);
  await settle(db, base, lojaId, raced);
  const saleRef = base.collection('estoque_vendas').doc(`csgn_${raced}`);
  db.onRead = (path, attempt) => {
    if (attempt === 1 && path === saleRef.path) db.concurrentWrite(saleRef, {origem: 'consignacao'});
  };
  const before = db.commits.length;
  await assert.rejects(hide(db, lojaId, raced), e => notAllowed(e) && e.message.includes('HAS_SALE'));
  db.onRead = null;
  assert.equal(db.commits.length, before, 'no commit after the conflicting retry');
  assert.notEqual(consignment(db, base, raced).isDeleted, true);
});

test('IS_TOTAL_RETURN rule table', () => {
  const lineOf = (o = {}) => ({lineId: 'l1', qtySent: 2, qtySold: 0, qtyReturned: 2, ...o});
  const ok = {
    status: 'SETTLED', settlementOperationId: 'settle_x', saleId: null, financeId: null,
    totalItemsSold: 0, grossSoldAmount: 0, commissionAmount: 0, netAmount: 0, totalItemsReturned: 2,
    lines: [lineOf()], withdrawals: [],
  };
  assert.equal(totalReturnIneligibility(ok), null);
  const withdrawn = {
    ...ok, totalItemsReturned: 1, lines: [lineOf({qtyWithdrawn: 1, qtyReturned: 1})],
    withdrawals: [{withdrawalId: 'w1', lines: [{lineId: 'l1', qtyWithdrawn: 1}]}],
  };
  assert.equal(totalReturnIneligibility(withdrawn), null);
  const cases = {
    NOT_SETTLED: [{...ok, status: 'ISSUED'}, {...ok, status: 'CANCELLED'}, {...ok, status: 'DRAFT'}],
    NO_SETTLEMENT_OPERATION: [{...ok, settlementOperationId: null}],
    HAS_SALE: [{...ok, saleId: 'csgn_x'}, {...ok, financeId: 'f'}, {...ok, totalItemsSold: 1}, {...ok, grossSoldAmount: 1}],
    NO_LINES: [{...ok, lines: []}],
    LINE_NOT_RETURNED: [
      {...ok, lines: [lineOf({qtySold: 1, qtyReturned: 1})]},
      {...ok, lines: [lineOf({qtyReturned: 1})]},
      {...ok, lines: [lineOf({qtySold: undefined})]},
    ],
    WITHDRAWAL_MISMATCH: [
      {...withdrawn, withdrawals: []},
      {...ok, withdrawals: [{withdrawalId: 'w1', lines: [{lineId: 'l1', qtyWithdrawn: 1}]}]},
      {...withdrawn, withdrawals: [...withdrawn.withdrawals, ...withdrawn.withdrawals]},
    ],
    TOTALS_MISMATCH: [{...ok, totalItemsReturned: 3}],
  };
  for (const [reason, docs] of Object.entries(cases)) {
    for (const d of docs) assert.equal(totalReturnIneligibility(d), reason, JSON.stringify(d));
  }
});
