import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand, FIXED_WRITE_UNITS} from '../src/consignmentCommand.js';
import {
  CODES, MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT, MAX_STOCK_RECORDS_PER_TRANSACTION,
  MAX_TRANSACTION_WRITE_UNITS, WRITE_UNITS_PER_STOCK_RECORD, mapConsignmentHttp,
} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const LIMIT = MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT;
const FIRESTORE_COMMIT_WRITE_LIMIT = 500;
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

function seedVariation(db, base, lojaId, id, cells) {
  db.seed(base.collection('estoque_produtos').doc(id), {
    lojaId, stockKind: 'variation', stockRevision: 0,
    quantidade: Object.values(cells).reduce((s, n) => s + n, 0),
    variacoes: Object.fromEntries(Object.entries(cells).map(([size, n]) => [size, {'sem-cor': n}])),
  });
  db.seed(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 10});
  db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {protocolVersion: 1, lojaId, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload};
}

const line = productId => ({productId, qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0});
const cell = (productId, size) => ({...line(productId), variationKey: {size, color: 'sem-cor', extra: ''}});
const stock = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));
const isLimit = e => e.consignmentCode === CODES.CONSIGNMENT_PRODUCT_LIMIT && e.code === 'resource-exhausted';

async function createDraft(db, lojaId, lines) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'r1', notes: '', lines: lines.map(l => typeof l === 'string' ? line(l) : l),
  }, id), owner);
  return id;
}

async function issueFresh(n, qty = 1) {
  const {db, base, lojaId} = seedStore(n, qty);
  const id = await createDraft(db, lojaId, ids(n));
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  return {db, base, lojaId, id, res};
}

test('contract: 50 distinct products, resource-exhausted mapping', () => {
  assert.equal(LIMIT, 50);
  const mapped = mapConsignmentHttp(Object.assign(new Error('x'), {consignmentCode: CODES.CONSIGNMENT_PRODUCT_LIMIT}));
  assert.equal(mapped.http, 'resource-exhausted');
  assert.equal(mapped.details.consignmentCode, CODES.CONSIGNMENT_PRODUCT_LIMIT);
});

test('capacity: worst-case write units stay under Firestore commit limit with margin', () => {
  assert.ok(MAX_STOCK_RECORDS_PER_TRANSACTION >= LIMIT);
  const worstFixed = Math.max(...Object.values(FIXED_WRITE_UNITS));
  const worst = MAX_STOCK_RECORDS_PER_TRANSACTION * WRITE_UNITS_PER_STOCK_RECORD + worstFixed;
  assert.equal(worst, 374);
  assert.ok(worst <= MAX_TRANSACTION_WRITE_UNITS);
  assert.ok(MAX_TRANSACTION_WRITE_UNITS <= FIRESTORE_COMMIT_WRITE_LIMIT * 0.8);
});

for (const n of [25, 32, 40, 50]) {
  test(`issue ${n} distinct products, worst case (live doc rewritten): writes 3n+3, transforms 3n+3`, async () => {
    const {db, base, id, res} = await issueFresh(n, 2);
    assert.equal(res.status, 'ISSUED');
    assert.deepEqual(db.lastCommit, {writes: 3 * n + 3, transforms: 3 * n + 3});
    assert.equal(db.lastCommit.writes + db.lastCommit.transforms, WRITE_UNITS_PER_STOCK_RECORD * n + FIXED_WRITE_UNITS.issue);
    assert.ok(db.lastCommit.writes + db.lastCommit.transforms <= MAX_TRANSACTION_WRITE_UNITS);
    for (const p of ids(n)) assert.equal(stock(db, base, p).quantidade, 1);
    const doc = consignment(db, base, id);
    assert.equal(doc.totalItemsSent, n);
    assert.equal(doc.additions[0].lines.length, n);
  });
}

test('issue to zero stock deletes live docs: transforms drop to 2n+3', async () => {
  const {db, base, res} = await issueFresh(50, 1);
  assert.equal(res.status, 'ISSUED');
  assert.deepEqual(db.lastCommit, {writes: 153, transforms: 103});
  for (const p of ids(50)) {
    assert.equal(stock(db, base, p).quantidade, 0);
    assert.equal(db.exists(base.collection('produtos').doc(p)), false);
  }
});

test('50 products x 3 variations (150 lines): issue fits the 1 MiB document limit', async () => {
  const {db, base, lojaId} = seedStore(0);
  const products = ids(50).map(p => `V${p}`);
  for (const p of products) seedVariation(db, base, lojaId, p, {P: 1, M: 1, G: 1});
  const lines = products.flatMap(p => ['P', 'M', 'G'].map(s => ({
    ...cell(p, s), notes: 'x'.repeat(120),
  })));
  const id = await createDraft(db, lojaId, lines);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.lines.length, 150);
  const docBytes = Buffer.byteLength(JSON.stringify(doc));
  const auditBytes = Buffer.byteLength(JSON.stringify(db.getData(base.collection('consignment_audit').doc(`issue_${id}`))));
  assert.ok(docBytes < 512 * 1024, `consignment doc ${docBytes} bytes`);
  assert.ok(auditBytes < 512 * 1024, `audit doc ${auditBytes} bytes`);
});

test('issue 51 distinct products is rejected before writes', async () => {
  const {db, base, lojaId} = seedStore(51);
  const id = await createDraft(db, lojaId, ids(50));
  const draft = consignment(db, base, id);
  const extra = {...draft.lines[0], productId: 'P51', lineId: 'P51::legacy'};
  db.seed(base.collection('consignments').doc(id), {...draft, lines: [...draft.lines, extra]});
  const snapshot = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), isLimit);
  assert.deepEqual(db.snapshot(), snapshot);
  for (const p of ids(51)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(db.exists(base.collection('consignment_operations').doc(`issue_${id}`)), false);
});

test('createDraft: 50 allowed, 51 rejected without writes', async () => {
  const {db, lojaId} = seedStore(51);
  await createDraft(db, lojaId, ids(50));
  const snapshot = db.snapshot();
  await assert.rejects(createDraft(db, lojaId, ids(51)), isLimit);
  assert.deepEqual(db.snapshot(), snapshot);
});

test('updateDraft above the limit is rejected without writes', async () => {
  const {db, base, lojaId} = seedStore(51);
  const id = await createDraft(db, lojaId, ids(3));
  const snapshot = db.snapshot();
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'updateDraft', `upd_${id}`, {lines: ids(51).map(line)}, id), owner),
    isLimit,
  );
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(consignment(db, base, id).lines.length, 3);
});

test('Mir-shaped draft (32 distinct products in 33 pieces) is valid and issues', async () => {
  const {db, base, lojaId} = seedStore(31);
  seedVariation(db, base, lojaId, 'COLAR', {A: 1, B: 1});
  const id = await createDraft(db, lojaId, [...ids(31), cell('COLAR', 'A'), cell('COLAR', 'B')]);
  const draft = consignment(db, base, id);
  assert.equal(new Set(draft.lines.map(l => l.productId)).size, 32);
  assert.equal(draft.totalItemsSent, 33);
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(res.status, 'ISSUED');
  assert.equal(stock(db, base, 'COLAR').quantidade, 0);
});

test('issue 50: failure at the end of the transaction leaves 0 partial writes', async () => {
  const {db, base, lojaId} = seedStore(50);
  const id = await createDraft(db, lojaId, ids(50));
  db.seed(base.collection('consignment_audit').doc(`issue_${id}`), {type: 'PREEXISTING'});
  const snapshot = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner));
  assert.deepEqual(db.snapshot(), snapshot);
  for (const p of ids(50)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
});

test('issue 50: same operationId replay writes nothing and does not decrement again', async () => {
  const {db, base, lojaId, id} = await issueFresh(50);
  const after = db.snapshot();
  const replay = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), after);
  for (const p of ids(50)) assert.equal(stock(db, base, p).quantidade, 0);
  const docs = [...db._store.keys()].filter(k => k.startsWith(`lojas/${lojaId}/consignments/`));
  assert.equal(docs.length, 1);
});

test('addItems: 45 issued + 5 new distinct allowed', async () => {
  const {db, base, lojaId} = seedStore(50);
  const id = await createDraft(db, lojaId, ids(45));
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: ids(50).slice(45).map(line),
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(new Set(doc.lines.map(l => l.productId)).size, 50);
  for (const p of ids(50)) assert.equal(stock(db, base, p).quantidade, 0);
});

test('addItems: at 50 a new distinct product is blocked without writes', async () => {
  const {db, base, lojaId} = seedStore(51, 2);
  const id = await createDraft(db, lojaId, ids(50));
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const snapshot = db.snapshot();
  await assert.rejects(
    executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
      expectedRevision: consignment(db, base, id).revision, lines: [line('P51')],
    }, id), owner),
    isLimit,
  );
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(stock(db, base, 'P51').quantidade, 2);
});

test('addItems: at 50, more units and another variation of existing products are allowed', async () => {
  const {db, base, lojaId} = seedStore(49, 3);
  seedVariation(db, base, lojaId, 'VAR', {P: 2, M: 2});
  const id = await createDraft(db, lojaId, [...ids(49), cell('VAR', 'P')]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: [line('P01'), cell('VAR', 'M')],
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(new Set(doc.lines.map(l => l.productId)).size, 50);
  assert.equal(doc.totalItemsSent, 52);
  assert.equal(stock(db, base, 'P01').quantidade, 1);
  const v = stock(db, base, 'VAR');
  assert.deepEqual([v.variacoes.P['sem-cor'], v.variacoes.M['sem-cor']], [1, 1]);
});

test('settle 50 with full return: one commit within budget, stock restored', async () => {
  const {db, base, lojaId, id} = await issueFresh(50);
  const doc = consignment(db, base, id);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: doc.lines.map(l => ({lineId: l.lineId, qtySold: 0, qtyReturned: l.qtySent})),
  }, id), owner);
  assert.equal(consignment(db, base, id).status, 'SETTLED');
  assert.ok(db.lastCommit.writes + db.lastCommit.transforms <= MAX_TRANSACTION_WRITE_UNITS);
  for (const p of ids(50)) assert.equal(stock(db, base, p).quantidade, 1);
});
