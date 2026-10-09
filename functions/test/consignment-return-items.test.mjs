import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand, FIXED_WRITE_UNITS} from '../src/consignmentCommand.js';
import {CODES, MAX_TRANSACTION_WRITE_UNITS, WRITE_UNITS_PER_STOCK_RECORD} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, e => e.consignmentCode === code || e.code === code);
}

function seedProduct(db, base, id, stock, draft = {}) {
  db.seed(base.collection('estoque_produtos').doc(id), {stockRevision: 0, variacoes: {}, ...stock});
  db.seed(base.collection('draft_produtos').doc(id), {
    nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 100, ...draft,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: stock.comboIds ?? []});
}

function seedStore({ids = ['A', 'B', 'C', 'F'], qty = 10} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `ret_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('maria'), {
    storeId: lojaId, resellerId: 'maria', displayName: 'Maria', active: true, notes: '',
  });
  for (const id of ids) seedProduct(db, base, id, {quantidade: qty, stockKind: 'simple'});
  return {db, base, lojaId};
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {
    protocolVersion: 1, lojaId, operation, operationId,
    ...(consignmentId ? {consignmentId} : {}),
    payload,
  };
}

function line(productId, qty, price = 100, variationKey = undefined) {
  return {
    productId, qtySent: qty, unitSalePrice: price,
    commissionType: 'PERCENTUAL', commissionValue: 10,
    ...(variationKey ? {variationKey} : {}),
  };
}

const stockOf = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const stockQty = (db, base, id) => stockOf(db, base, id)?.quantidade;
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));

async function issue(db, lojaId, lines) {
  const id = `c_maria_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'maria', notes: '', lines,
  }, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  return id;
}

function returnRow(l, qty) {
  return {lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty};
}

function returnItems(db, lojaId, id, rows, {opId, expectedRevision, base} = {}) {
  const rev = expectedRevision ?? consignment(db, base, id).revision;
  return executeConsignmentCommand(db, cmd(lojaId, 'returnItems', opId ?? `consignment_return_${id}_${++seq}`, {
    expectedRevision: rev, lines: rows,
  }, id), owner);
}

function settleRows(doc, decide) {
  return doc.lines.map(l => {
    const [qtySold, qtyReturned] = decide(l);
    return {lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qtySold, qtyReturned};
  });
}

test('21 partial quantity: 2 issued, return 1 -> outstanding 1, stock +1', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2)]);
  assert.equal(stockQty(db, base, 'A'), 8);
  const before = consignment(db, base, id);
  const res = await returnItems(db, lojaId, id, [returnRow(before.lines[0], 1)], {base});
  assert.equal(res.saleCreated, false);
  assert.equal(res.financeCreated, false);
  assert.equal(stockQty(db, base, 'A'), 9);
  const doc = consignment(db, base, id);
  assert.equal(doc.status, 'ISSUED');
  assert.equal(doc.lines[0].qtySent, 2, 'original qty preserved');
  assert.equal(doc.lines[0].qtyWithdrawn, 1);
  assert.equal(doc.totalItemsSent, 2, 'ORIGINAL_TOTAL_PRESERVED');
  assert.equal(doc.potentialGrossAmount, before.potentialGrossAmount);
  assert.equal(doc.totalItemsWithdrawn, 1);
  assert.equal(doc.totalItemsOutstanding, 1, 'CURRENT_OUTSTANDING_TOTAL_UPDATED');
  assert.equal(doc.outstandingGrossAmount, 100);
  assert.equal(doc.outstandingCommissionAmount, 10);
  assert.equal(doc.outstandingNetAmount, 90);
  assert.equal(doc.withdrawnGrossAmount, 100);
  assert.equal(doc.revision, before.revision + 1);
  assert.deepEqual(doc.additions, before.additions, 'issue history untouched');
  assert.equal(doc.withdrawals.length, 1);
  const w = doc.withdrawals[0];
  assert.equal(w.kind, 'WITHDRAWAL');
  assert.equal(w.reason, 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT');
  assert.equal(w.createdBy, 'owner');
  assert.ok(w.createdAt);
  assert.equal(w.lines[0].qtyWithdrawn, 1);
  assert.equal(w.lines[0].qtyOutstandingBefore, 2);
  assert.equal(w.lines[0].qtyOutstandingAfter, 1);
  assert.equal(w.lines[0].stockRevisionAfter, w.lines[0].stockRevisionBefore + 1);
  const audit = db.getData(base.collection('consignment_audit').doc(res.operationId));
  assert.equal(audit.type, 'CONSIGNMENT_RETURN_BEFORE_SETTLEMENT');
  assert.equal(audit.saleId, null);
  assert.equal(audit.financeId, null);
  assert.equal(stockOf(db, base, 'A').stockOperationId, res.operationId);
  const sales = await base.collection('estoque_vendas').get();
  assert.equal(sales.size, 0, 'no sale created');
  const fin = await base.collection('lancamentos_financeiros').get();
  assert.equal(fin.size, 0, 'no finance created');
});

test('22 full line: 1 issued, return 1 -> outstanding 0, line preserved', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 1), line('B', 1)]);
  const doc0 = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(doc0.lines[0], 1)], {base});
  const doc = consignment(db, base, id);
  assert.equal(doc.lines.length, 2, 'line kept');
  assert.equal(doc.lines[0].qtySent, 1);
  assert.equal(doc.lines[0].qtyWithdrawn, 1);
  assert.equal(doc.totalItemsOutstanding, 1);
  assert.equal(stockQty(db, base, 'A'), 10);
  await denied(returnItems(db, lojaId, id, [returnRow(doc.lines[0], 1)], {base}), CODES.RETURN_EXCEEDS_OUTSTANDING);
});

test('23 exact variation: Tam20/Rubelita +1, Tam22/Cristal unchanged', async () => {
  const {db, base, lojaId} = seedStore();
  seedProduct(db, base, 'anel', {
    stockKind: 'variation', quantidade: 6,
    variacoes: {'20': {Rubelita: 2, Cristal: 1}, '22': {Cristal: 3}},
    tamanhos: ['20', '22'], cores: ['Rubelita', 'Cristal'],
  });
  const id = await issue(db, lojaId, [
    line('anel', 1, 80, {size: '20', color: 'Rubelita', extra: ''}),
    line('anel', 2, 80, {size: '22', color: 'Cristal', extra: ''}),
  ]);
  const issued = stockOf(db, base, 'anel');
  assert.equal(issued.variacoes['20'].Rubelita, 1);
  assert.equal(issued.variacoes['22'].Cristal, 1);
  const doc0 = consignment(db, base, id);
  const rubelita = doc0.lines.find(l => l.variationKey.color === 'Rubelita');
  await returnItems(db, lojaId, id, [returnRow(rubelita, 1)], {base});
  const after = stockOf(db, base, 'anel');
  assert.equal(after.variacoes['20'].Rubelita, 2);
  assert.equal(after.variacoes['20'].Cristal, 1);
  assert.equal(after.variacoes['22'].Cristal, 1);
  assert.equal(after.quantidade, issued.quantidade + 1);
  const doc = consignment(db, base, id);
  assert.equal(doc.lines.find(l => l.variationKey.color === 'Cristal').qtyWithdrawn ?? 0, 0);
});

test('23b identity must match the stored line (productId and exact cell)', async () => {
  const {db, base, lojaId} = seedStore();
  seedProduct(db, base, 'anel', {
    stockKind: 'variation', quantidade: 6,
    variacoes: {'20': {Rubelita: 2, Cristal: 1}, '22': {Cristal: 3}},
    tamanhos: ['20', '22'], cores: ['Rubelita', 'Cristal'],
  });
  const id = await issue(db, lojaId, [line('anel', 1, 80, {size: '20', color: 'Rubelita', extra: ''}), line('A', 1)]);
  const doc = consignment(db, base, id);
  const l = doc.lines[0];
  const snap = db.snapshot();
  await denied(returnItems(db, lojaId, id, [{...returnRow(l, 1), variationKey: {size: '22', color: 'Cristal', extra: ''}}], {base}), CODES.INVALID_ARGUMENT);
  await denied(returnItems(db, lojaId, id, [{...returnRow(l, 1), productId: 'A'}], {base}), CODES.INVALID_ARGUMENT);
  await denied(returnItems(db, lojaId, id, [{...returnRow(l, 1), lineId: 'nope'}], {base}), CODES.INVALID_ARGUMENT);
  await denied(returnItems(db, lojaId, id, [returnRow(l, 0)], {base}), CODES.INVALID_ARGUMENT);
  await denied(returnItems(db, lojaId, id, [returnRow(l, 1), returnRow(l, 1)], {base}), CODES.INVALID_ARGUMENT);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'returnItems', `bad_reason_${id}`, {
    expectedRevision: doc.revision, lines: [returnRow(l, 1)], reason: 'SALE',
  }, id), owner), CODES.INVALID_ARGUMENT);
  assert.deepEqual(db.snapshot(), snap);
});

test('24 multi-item atomicity: forced failure on last line -> zero changes', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2), line('B', 2), line('C', 1)]);
  const doc = consignment(db, base, id);
  const snap = db.snapshot();
  await denied(returnItems(db, lojaId, id, [
    returnRow(doc.lines[0], 1), returnRow(doc.lines[1], 2), returnRow(doc.lines[2], 2),
  ], {base}), CODES.RETURN_EXCEEDS_OUTSTANDING);
  assert.deepEqual(db.snapshot(), snap);
  db.seed(base.collection('exclusao_produto').doc('C'), {p: true});
  const snap2 = db.snapshot();
  await denied(returnItems(db, lojaId, id, [
    returnRow(doc.lines[0], 1), returnRow(doc.lines[1], 2), returnRow(doc.lines[2], 1),
  ], {base}), CODES.PRODUCT_STATE_UNSAFE);
  assert.deepEqual(db.snapshot(), snap2, 'no stock, history, audit or operation written');
});

test('25 retry: same operationId applies once; different payload fails closed', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 3)]);
  const doc = consignment(db, base, id);
  const opId = `consignment_return_${id}_fixed`;
  const payload = {expectedRevision: doc.revision, lines: [returnRow(doc.lines[0], 1)]};
  const r1 = await executeConsignmentCommand(db, cmd(lojaId, 'returnItems', opId, payload, id), owner);
  const stockAfter = stockOf(db, base, 'A');
  const r2 = await executeConsignmentCommand(db, cmd(lojaId, 'returnItems', opId, payload, id), owner);
  assert.equal(r1.alreadyApplied, false);
  assert.equal(r2.alreadyApplied, true);
  assert.deepEqual(stockOf(db, base, 'A'), stockAfter, 'stock incremented once');
  const after = consignment(db, base, id);
  assert.equal(after.withdrawals.length, 1, 'history appended once');
  assert.equal(after.lines[0].qtyWithdrawn, 1);
  const audits = (await base.collection('consignment_audit').get()).docs
    .filter(d => d.data().type === 'CONSIGNMENT_RETURN_BEFORE_SETTLEMENT');
  assert.equal(audits.length, 1, 'audit once');
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'returnItems', opId, {
    ...payload, lines: [returnRow(doc.lines[0], 2)],
  }, id), owner), CODES.IDEMPOTENCY_CONFLICT);
  assert.equal(stockQty(db, base, 'A'), 8);
});

test('26 settlement after return: A,B,C; withdraw B; sold A; returned C', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 1), line('B', 1), line('C', 1)]);
  const doc0 = consignment(db, base, id);
  const bLine = doc0.lines.find(l => l.productId === 'B');
  await returnItems(db, lojaId, id, [returnRow(bLine, 1)], {base});
  assert.equal(stockQty(db, base, 'B'), 10);
  const doc = consignment(db, base, id);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_bad_${id}`, {
    lines: settleRows(doc, l => l.productId === 'B' ? [1, 0] : l.productId === 'A' ? [1, 0] : [0, 1]),
  }, id), owner), CODES.INVALID_SETTLEMENT_TOTAL);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: settleRows(doc, l => l.productId === 'A' ? [1, 0] : l.productId === 'C' ? [0, 1] : [0, 0]),
  }, id), owner);
  const settled = consignment(db, base, id);
  assert.equal(settled.status, 'SETTLED');
  assert.equal(settled.totalItemsSent, 3, 'issued 3');
  assert.equal(settled.totalItemsWithdrawn, 1, 'withdrawn 1');
  assert.equal(settled.totalItemsSold + settled.totalItemsReturned, 2, 'settled universe 2');
  assert.equal(settled.totalItemsSold, 1);
  assert.equal(settled.totalItemsReturned, 1);
  const b = settled.lines.find(l => l.productId === 'B');
  assert.equal(b.qtySold, 0);
  assert.equal(b.qtyReturned, 0);
  assert.equal(b.qtyWithdrawn, 1);
  assert.equal(settled.withdrawals.length, 1, 'history preserved through settlement');
  assert.equal(stockQty(db, base, 'A'), 9);
  assert.equal(stockQty(db, base, 'B'), 10, 'withdrawn piece not returned twice');
  assert.equal(stockQty(db, base, 'C'), 10);
  const sale = db.getData(base.collection('estoque_vendas').doc(`csgn_${id}`));
  assert.deepEqual(sale.itens.map(i => i.productId), ['A']);
  assert.equal(sale.quantidade, 1);
  await denied(returnItems(db, lojaId, id, [returnRow(settled.lines[0], 1)], {base}), CODES.CONSIGNMENT_ALREADY_SETTLED);
});

test('26b stale settlement computed before a withdrawal is rejected', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2)]);
  const stale = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(stale.lines[0], 1)], {base});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_stale_${id}`, {
    lines: settleRows(stale, () => [1, 1]),
  }, id), owner), CODES.INVALID_SETTLEMENT_TOTAL);
  assert.equal(stockQty(db, base, 'A'), 9);
});

test('27 return then add: distinct movements', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('B', 2)]);
  const doc0 = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(doc0.lines[0], 1)], {base});
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: [line('B', 2, 110)],
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.lines.length, 2);
  assert.equal(doc.lines[0].qtyWithdrawn, 1);
  assert.equal(doc.lines[1].qtyWithdrawn ?? 0, 0);
  assert.equal(doc.additions.length, 2);
  assert.equal(doc.withdrawals.length, 1);
  assert.equal(doc.totalItemsSent, 4);
  assert.equal(doc.totalItemsWithdrawn, 1);
  assert.equal(doc.totalItemsOutstanding, 3);
  assert.equal(doc.outstandingGrossAmount, 320);
  assert.equal(stockQty(db, base, 'B'), 7);
});

test('28 add then return from the added lot', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('B', 2)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: [line('B', 3, 110)],
  }, id), owner);
  const doc0 = consignment(db, base, id);
  assert.equal(stockQty(db, base, 'B'), 5);
  await returnItems(db, lojaId, id, [returnRow(doc0.lines[1], 2)], {base});
  const doc = consignment(db, base, id);
  assert.equal(doc.lines[0].qtyWithdrawn ?? 0, 0);
  assert.equal(doc.lines[1].qtyWithdrawn, 2);
  assert.equal(doc.totalItemsOutstanding, 3);
  assert.equal(doc.withdrawnGrossAmount, 220);
  assert.equal(stockQty(db, base, 'B'), 7);
  assert.equal(doc.additions.length, 2);
});

test('29 status blocks: draft, settled, cancelled, deleted, stale revision', async () => {
  const {db, base, lojaId} = seedStore();
  const draftId = `c_draft_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `d_${draftId}`, {
    resellerId: 'maria', notes: '', lines: [line('A', 1)],
  }, draftId), owner);
  const draft = consignment(db, base, draftId);
  await denied(returnItems(db, lojaId, draftId, [returnRow(draft.lines[0], 1)], {base}), CODES.FAILED_PRECONDITION);

  const cancelId = `c_cancel_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `d_${cancelId}`, {
    resellerId: 'maria', notes: '', lines: [line('A', 1)],
  }, cancelId), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `x_${cancelId}`, {}, cancelId), owner);
  const cancelled = consignment(db, base, cancelId);
  await denied(returnItems(db, lojaId, cancelId, [returnRow(cancelled.lines[0], 1)], {base}), CODES.CONSIGNMENT_CANCELLED);
  await executeConsignmentCommand(db, cmd(lojaId, 'deleteCancelled', `del_${cancelId}`, {}, cancelId), owner);
  await denied(returnItems(db, lojaId, cancelId, [returnRow(cancelled.lines[0], 1)], {base}), CODES.FAILED_PRECONDITION);

  const settledId = await issue(db, lojaId, [line('A', 1)]);
  const s = consignment(db, base, settledId);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${settledId}`, {
    lines: settleRows(s, () => [1, 0]),
  }, settledId), owner);
  await denied(returnItems(db, lojaId, settledId, [returnRow(s.lines[0], 1)], {base}), CODES.CONSIGNMENT_ALREADY_SETTLED);

  const issuedId = await issue(db, lojaId, [line('B', 2)]);
  const i = consignment(db, base, issuedId);
  await denied(returnItems(db, lojaId, issuedId, [returnRow(i.lines[0], 1)], {base, expectedRevision: i.revision - 1}),
    CODES.CONSIGNMENT_REVISION_CONFLICT);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'returnItems', `norev_${issuedId}`, {
    lines: [returnRow(i.lines[0], 1)],
  }, issuedId), owner), CODES.INVALID_ARGUMENT);
  assert.equal(stockQty(db, base, 'B'), 8);
});

test('29b concurrent addItems after a stale read conflicts with return', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2)]);
  const stale = consignment(db, base, id);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: stale.revision, lines: [line('B', 1)],
  }, id), owner);
  await denied(returnItems(db, lojaId, id, [returnRow(stale.lines[0], 1)], {base, expectedRevision: stale.revision}),
    CODES.CONSIGNMENT_REVISION_CONFLICT);
  assert.equal(stockQty(db, base, 'A'), 8);
});

// Firestore serializes conflicting transactions; each pair is exercised in both commit orders
// with the losing client holding the view it read before the winner committed.
test('race: return vs settlement, both orders', async () => {
  const {db, base, lojaId} = seedStore();
  const a = await issue(db, lojaId, [line('A', 2)]);
  const viewA = consignment(db, base, a);
  await returnItems(db, lojaId, a, [returnRow(viewA.lines[0], 1)], {base, expectedRevision: viewA.revision});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${a}`, {
    lines: settleRows(viewA, () => [2, 0]),
  }, a), owner), CODES.INVALID_SETTLEMENT_TOTAL);
  assert.equal(consignment(db, base, a).status, 'ISSUED');
  assert.equal(stockQty(db, base, 'A'), 9);

  const b = await issue(db, lojaId, [line('B', 2)]);
  const viewB = consignment(db, base, b);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${b}`, {
    lines: settleRows(viewB, () => [1, 1]),
  }, b), owner);
  await denied(returnItems(db, lojaId, b, [returnRow(viewB.lines[0], 1)], {base, expectedRevision: viewB.revision}),
    CODES.CONSIGNMENT_ALREADY_SETTLED);
  assert.equal(stockQty(db, base, 'B'), 9, 'only the settlement return applied');
  assert.equal(consignment(db, base, b).withdrawals, undefined);
});

test('race: return vs addItems, both orders', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2)]);
  const view = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(view.lines[0], 1)], {base, expectedRevision: view.revision});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: view.revision, lines: [line('B', 1)],
  }, id), owner), CODES.CONSIGNMENT_REVISION_CONFLICT);
  assert.equal(stockQty(db, base, 'B'), 10);
  assert.equal(consignment(db, base, id).additions.length, 1);
  assert.equal(consignment(db, base, id).withdrawals.length, 1);
});

test('race: return vs cancel, both orders', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await issue(db, lojaId, [line('A', 2)]);
  const view = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(view.lines[0], 1)], {base, expectedRevision: view.revision});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${id}`, {}, id), owner),
    CODES.CONSIGNMENT_ALREADY_ISSUED);
  assert.equal(consignment(db, base, id).status, 'ISSUED');

  const draftId = `c_draft_race_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `d_${draftId}`, {
    resellerId: 'maria', notes: '', lines: [line('C', 1)],
  }, draftId), owner);
  const draftView = consignment(db, base, draftId);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${draftId}`, {}, draftId), owner);
  await denied(returnItems(db, lojaId, draftId, [returnRow(draftView.lines[0], 1)], {base, expectedRevision: draftView.revision}),
    CODES.CONSIGNMENT_CANCELLED);
  assert.equal(stockQty(db, base, 'C'), 10);
});

test('30 cross-tenant denied', async () => {
  const {db, lojaId} = seedStore();
  const foreignId = `foreign_${++seq}`;
  const foreignBase = db.collection('lojas').doc(foreignId);
  db.seed(foreignBase, {ownerUid: 'owner', lojaId: foreignId, nome: 'Other'});
  db.seed(foreignBase.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  const stolenId = `stolen_${++seq}`;
  db.seed(foreignBase.collection('consignments').doc(stolenId), {
    id: stolenId, storeId: lojaId, resellerId: 'maria', status: 'ISSUED', revision: 2,
    lines: [{lineId: 'A::\u001e\u001e', productId: 'A', variationKey: {size: '', color: '', extra: ''}, qtySent: 1}],
    additions: [],
  });
  await denied(executeConsignmentCommand(db, cmd(foreignId, 'returnItems', `xs_${stolenId}`, {
    expectedRevision: 2,
    lines: [{lineId: 'A::\u001e\u001e', productId: 'A', variationKey: {size: '', color: '', extra: ''}, qty: 1}],
  }, stolenId), owner), CODES.AUTH);

  const {db: db2, base: base2, lojaId: loja2} = seedStore();
  const id = await issue(db2, loja2, [line('A', 1)]);
  const d = consignment(db2, base2, id);
  await denied(executeConsignmentCommand(db2, cmd(loja2, 'returnItems', `stranger_${id}`, {
    expectedRevision: d.revision, lines: [returnRow(d.lines[0], 1)],
  }, id), {uid: 'stranger'}), CODES.AUTH);
});

test('17 catalog policy: unpublished stays unpublished; published reappears when qty > 0', async () => {
  const {db, base, lojaId} = seedStore({ids: []});
  seedProduct(db, base, 'hidden', {quantidade: 1, stockKind: 'simple'}, {publicadoNoCatalogo: false});
  seedProduct(db, base, 'shown', {quantidade: 1, stockKind: 'simple'});
  const id = await issue(db, lojaId, [line('hidden', 1), line('shown', 1)]);
  assert.equal(db.exists(base.collection('produtos').doc('shown')), false, 'sold out while consigned');
  const doc = consignment(db, base, id);
  await returnItems(db, lojaId, id, doc.lines.map(l => returnRow(l, 1)), {base});
  assert.equal(db.exists(base.collection('produtos').doc('hidden')), false, 'never auto-published');
  assert.equal(db.getData(base.collection('draft_produtos').doc('hidden')).publicar, false);
  const live = db.getData(base.collection('produtos').doc('shown'));
  assert.equal(live.estoque, 1);
  assert.equal(live.publicar, true);
});

test('18 fixed combo recalculated through the authoritative mechanism', async () => {
  const {db, base, lojaId} = seedStore({ids: []});
  seedProduct(db, base, 'P', {quantidade: 3, stockKind: 'simple', comboIds: ['K']});
  seedProduct(db, base, 'K', {
    quantidade: 3, stockKind: 'combo', tipoProduto: 'combo',
    itensCombo: [{productId: 'P', quantidade: 1}],
  });
  const id = await issue(db, lojaId, [line('P', 2)]);
  assert.equal(stockQty(db, base, 'K'), 1);
  const doc = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(doc.lines[0], 1)], {base});
  assert.equal(stockQty(db, base, 'P'), 2);
  assert.equal(stockQty(db, base, 'K'), 2);
});

async function capacity(n) {
  const ids = Array.from({length: n}, (_, i) => `p${i}`);
  const {db, base, lojaId} = seedStore({ids, qty: 5});
  const id = await issue(db, lojaId, ids.map(p => line(p, 1)));
  const doc = consignment(db, base, id);
  await returnItems(db, lojaId, id, doc.lines.map(l => returnRow(l, 1)), {base});
  return db.lastCommit.writes + db.lastCommit.transforms;
}

test('31 capacity: RETURN_WRITES_1 / 10 / 50 within transaction budget', async () => {
  const one = await capacity(1);
  const ten = await capacity(10);
  const fifty = await capacity(50);
  const fixed = FIXED_WRITE_UNITS.returnItems;
  assert.equal(one, WRITE_UNITS_PER_STOCK_RECORD + fixed);
  assert.equal(ten, 10 * WRITE_UNITS_PER_STOCK_RECORD + fixed);
  assert.equal(fifty, 50 * WRITE_UNITS_PER_STOCK_RECORD + fixed);
  assert.ok(fifty <= MAX_TRANSACTION_WRITE_UNITS);
  assert.ok(60 * WRITE_UNITS_PER_STOCK_RECORD + fixed <= MAX_TRANSACTION_WRITE_UNITS, 'combo fan-out cap still fits');
  console.log(`RETURN_WRITES_1=${one} RETURN_WRITES_10=${ten} RETURN_WRITES_50=${fifty}`);
});

test('31b capacity: worst combo fan-out (60 stock records) measured within budget', async () => {
  const {db, base, lojaId} = seedStore({ids: []});
  const combos = Array.from({length: 59}, (_, i) => `K${i}`);
  seedProduct(db, base, 'P', {quantidade: 10, stockKind: 'simple', comboIds: combos});
  for (const k of combos) {
    seedProduct(db, base, k, {
      quantidade: 10, stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: 'P', quantidade: 1}],
    });
  }
  const id = await issue(db, lojaId, [line('P', 2)]);
  const doc = consignment(db, base, id);
  await returnItems(db, lojaId, id, [returnRow(doc.lines[0], 1)], {base});
  const units = db.lastCommit.writes + db.lastCommit.transforms;
  assert.equal(units, 60 * WRITE_UNITS_PER_STOCK_RECORD + FIXED_WRITE_UNITS.returnItems);
  assert.ok(units <= MAX_TRANSACTION_WRITE_UNITS);
  assert.equal(stockQty(db, base, 'P'), 9);
  assert.equal(stockQty(db, base, 'K0'), 9);
  console.log(`RETURN_WRITES_WORST_COMBO_FANOUT=${units}`);
});
