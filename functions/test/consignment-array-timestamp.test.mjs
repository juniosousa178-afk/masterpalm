import test from 'node:test';
import assert from 'node:assert/strict';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {CODES, describeUnclassifiedConsignmentError, mapConsignmentHttp} from '../src/consignmentProtocol.js';
import {assertValidFirestoreData, createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const MIR_PRICES = {P1: 72, P2: 149, P3: 88, P4: 70, P5: 98, P6: 77};
let seq = 0;

function seedStore(prices = MIR_PRICES, qty = 1, lojaId = `arrts_${++seq}`) {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {
    storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Teste', active: true, notes: '',
  });
  for (const [id, preco] of Object.entries(prices)) {
    db.seed(base.collection('estoque_produtos').doc(id), {
      lojaId, quantidade: qty, stockKind: 'simple', tipoProduto: 'simples', stockRevision: 3, variacoes: {},
    });
    db.seed(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco});
    db.seed(base.collection('produtos').doc(id), {nome: `Produto ${id}`, quantidade: qty, preco});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  let transactions = 0;
  const run = db.runTransaction.bind(db);
  db.runTransaction = fn => { transactions++; return run(fn); };
  return {db, base, lojaId, transactions: () => transactions};
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {protocolVersion: 1, lojaId, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload};
}

function line(productId, price, qty = 1) {
  return {productId, qtySent: qty, unitSalePrice: price, commissionType: 'SEM_COMISSAO', commissionValue: 0};
}

async function createDraft(db, lojaId, prices) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'r1', notes: '', lines: Object.entries(prices).map(([p, price]) => line(p, price)),
  }, id), owner);
  return id;
}

const stock = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));

test('fake rejects Firestore transforms inside arrays like the Admin SDK', () => {
  assert.throws(
    () => assertValidFirestoreData({additions: [{createdAt: FieldValue.serverTimestamp()}]}),
    /FieldValue\.serverTimestamp\(\) cannot be used inside of an array \(found in field "additions\.`0`\.createdAt"\)/,
  );
  assert.throws(() => assertValidFirestoreData({a: [{n: FieldValue.increment(1)}]}), /inside of an array/);
  assert.throws(() => assertValidFirestoreData({a: [[FieldValue.arrayUnion('x')]]}), /inside of an array/);
  assert.throws(() => assertValidFirestoreData({a: {b: undefined}}), /Cannot use "undefined"/);
  assert.doesNotThrow(() => assertValidFirestoreData({
    issuedAt: FieldValue.serverTimestamp(),
    additions: [{createdAt: Timestamp.now()}],
  }));
});

test('Mir-equivalent six-item issue succeeds in one transaction with Timestamp history', async () => {
  const {db, base, lojaId, transactions} = seedStore();
  const id = await createDraft(db, lojaId, MIR_PRICES);
  const draft = consignment(db, base, id);
  assert.equal(draft.status, 'DRAFT');
  assert.equal(draft.potentialGrossAmount, 554);
  assert.equal(draft.potentialCommissionAmount, 0);
  for (const p of Object.keys(MIR_PRICES)) assert.equal(stock(db, base, p).quantidade, 1, 'draft must not mutate stock');

  const before = transactions();
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(transactions() - before, 1);
  assert.equal(res.status, 'ISSUED');

  for (const p of Object.keys(MIR_PRICES)) {
    const s = stock(db, base, p);
    assert.equal(s.quantidade, 0);
    assert.equal(s.stockRevision, 4);
    assert.equal(s.stockOperationId, `issue_${id}`);
    assert.equal(db.exists(base.collection('produtos').doc(p)), false, 'zero stock leaves public catalog');
  }
  const doc = consignment(db, base, id);
  assert.equal(doc.status, 'ISSUED');
  assert.equal(doc.issueOperationId, `issue_${id}`);
  assert.equal(doc.lines.length, 6);
  assert.equal(doc.totalItemsSent, 6);
  assert.equal(doc.potentialGrossAmount, 554);
  assert.equal(doc.potentialCommissionAmount, 0);
  assert.ok(doc.issuedAt instanceof Date, 'root issuedAt stays a server timestamp');
  assert.equal(doc.additions.length, 1);
  assert.equal(doc.additions[0].kind, 'INITIAL');
  assert.ok(doc.additions[0].createdAt instanceof Timestamp);
  assert.equal(doc.additions[0].lines.length, 6);
  const audit = db.getData(base.collection('consignment_audit').doc(`issue_${id}`));
  assert.equal(audit.type, 'CONSIGNMENT_ISSUE');
  assert.equal(audit.affectedProducts.length, 6);
});

test('single-item issue succeeds', async () => {
  const {db, base, lojaId} = seedStore({P1: 72});
  const id = await createDraft(db, lojaId, {P1: 72});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.status, 'ISSUED');
  assert.ok(doc.additions[0].createdAt instanceof Timestamp);
  assert.equal(stock(db, base, 'P1').quantidade, 0);
});

test('addItems on issued consignment appends Timestamp history and decrements once', async () => {
  const {db, base, lojaId, transactions} = seedStore({P1: 72, P2: 149}, 2);
  const id = await createDraft(db, lojaId, {P1: 72});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const issued = consignment(db, base, id);
  const before = transactions();
  const add = await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: issued.revision, lines: [line('P2', 149)],
  }, id), owner);
  assert.equal(transactions() - before, 1);
  assert.equal(add.revision, issued.revision + 1);
  const doc = consignment(db, base, id);
  assert.equal(doc.additions.length, 2);
  assert.equal(doc.additions[1].kind, 'ADDITION');
  assert.ok(doc.additions[0].createdAt instanceof Timestamp);
  assert.ok(doc.additions[1].createdAt instanceof Timestamp);
  assert.equal(stock(db, base, 'P1').quantidade, 1);
  assert.equal(stock(db, base, 'P2').quantidade, 1);

  const replay = await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: issued.revision, lines: [line('P2', 149)],
  }, id), owner);
  assert.equal(replay.alreadyApplied, true);
  assert.equal(stock(db, base, 'P2').quantidade, 1);
  assert.equal(consignment(db, base, id).additions.length, 2);
});

test('addItems on draft keeps stock untouched and history valid', async () => {
  const {db, base, lojaId} = seedStore({P1: 72, P2: 149});
  const id = await createDraft(db, lojaId, {P1: 72});
  const draft = consignment(db, base, id);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: draft.revision, lines: [line('P2', 149)],
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.status, 'DRAFT');
  assert.ok(doc.additions.every(a => a.createdAt === null || a.createdAt instanceof Date || a.createdAt instanceof Timestamp));
  assert.equal(doc.additions.at(-1).kind, 'DRAFT_ADD');
  assert.equal(stock(db, base, 'P1').quantidade, 1);
  assert.equal(stock(db, base, 'P2').quantidade, 1);
});

test('issue failure late in the transaction leaves no partial writes', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await createDraft(db, lojaId, MIR_PRICES);
  db.seed(base.collection('consignment_audit').doc(`issue_${id}`), {type: 'PREEXISTING'});
  const snapshot = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner));
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
  for (const p of Object.keys(MIR_PRICES)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(db.exists(base.collection('consignment_operations').doc(`issue_${id}`)), false);
});

test('issue retry with same operationId replays without second decrement', async () => {
  const {db, base, lojaId} = seedStore();
  const id = await createDraft(db, lojaId, MIR_PRICES);
  const first = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const afterFirst = db.snapshot();
  const second = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(second.result.status, 'ISSUED');
  assert.deepEqual(db.snapshot(), afterFirst, 'replay writes nothing');
  for (const p of Object.keys(MIR_PRICES)) assert.equal(stock(db, base, p).quantidade, 0);
  const issuedDocs = [...db._store.keys()].filter(k => k.startsWith(`lojas/${lojaId}/consignments/`));
  assert.equal(issuedDocs.length, 1);
});

test('distinct issue operation after issue is blocked', async () => {
  const {db, lojaId} = seedStore({P1: 72});
  const id = await createDraft(db, lojaId, {P1: 72});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_other_${id}`, {}, id), owner),
    e => e.consignmentCode === CODES.CONSIGNMENT_ALREADY_ISSUED,
  );
});

test('issue request hash does not depend on wall clock', async () => {
  const hashes = [];
  for (let i = 0; i < 2; i++) {
    const {db, base, lojaId} = seedStore({P1: 72}, 1, 'arrts_fixed');
    const id = 'c_fixed';
    await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
      resellerId: 'r1', notes: '', lines: [line('P1', 72)],
    }, id), owner);
    await new Promise(r => setTimeout(r, 5));
    await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
    hashes.push(db.getData(base.collection('consignment_operations').doc(`issue_${id}`)).requestHash);
    assert.equal(lojaId, 'arrts_fixed');
  }
  assert.equal(typeof hashes[0], 'string');
  assert.equal(hashes[0], hashes[1]);
});

test('unclassified error log fields carry no payload or PII', () => {
  const err = new Error('boom for maria@example.com phone 11 99999-8888 cpf 123.456.789-09');
  const raw = {
    operation: 'issue', lojaId: 's', operationId: 'issue_x',
    payload: {resellerId: 'r1', displayName: 'Maria Secreta', lines: [{productId: 'P1'}]},
  };
  assert.equal(mapConsignmentHttp(err).details.consignmentCode, 'SERVER');
  const out = describeUnclassifiedConsignmentError(err, raw);
  assert.deepEqual(Object.keys(out).sort(), ['action', 'at', 'consignmentCode', 'errorCode', 'errorName', 'message']);
  assert.equal(out.action, 'issue');
  const text = JSON.stringify(out);
  for (const secret of ['maria@example.com', '99999-8888', '123.456.789-09', 'Maria Secreta', 'P1', 'r1']) {
    assert.equal(text.includes(secret), false, secret);
  }
  assert.equal(describeUnclassifiedConsignmentError({code: 10}, {operation: 'x<script>'}).action, 'unknown');
});
