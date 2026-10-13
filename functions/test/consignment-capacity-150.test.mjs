/** 150 distinct products per consignment: atomicity, exact cells, idempotency, concurrency, projection, sizes. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand, FIXED_WRITE_UNITS} from '../src/consignmentCommand.js';
import {projectConsignmentCatalog} from '../src/consignmentCatalogProjection.js';
import {
  CODES, MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT, MAX_LINES, MAX_STOCK_RECORDS_PER_TRANSACTION,
  MAX_TRANSACTION_WRITE_UNITS, MAX_CONSIGNMENT_DOC_BYTES, MAX_SETTLEMENT_COMMAND_BYTES, MAX_COMMAND_BYTES,
  WRITE_UNITS_PER_STOCK_RECORD, firestoreDocumentBytes, settlementCommandBytes,
} from '../src/consignmentProtocol.js';
import {commandCommit, commitUnits, createConsignmentTestDb, stockCommitsSince} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const N = MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT;
let seq = 0;

// Realistic production-shaped ids (slug products, long names, barcodes).
const pid = i => `nathy-pratas-e-folheados-colar-letra-${String(i).padStart(3, '0')}`;
const pids = n => Array.from({length: n}, (_, i) => pid(i + 1));

function newStore() {
  const db = createConsignmentTestDb();
  const lojaId = `cap150_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {
    storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Teste', active: true, notes: '',
  });
  return {db, base, lojaId};
}

function seedProduct(db, base, lojaId, id, stock, {draft = true, comboIds = []} = {}) {
  db.seed(base.collection('estoque_produtos').doc(id), {lojaId, stockRevision: 3, variacoes: {}, ...stock});
  if (draft) {
    db.seed(base.collection('draft_produtos').doc(id), {
      nome: `Colar Letra Cravejada Prata 925 Banho Ródio Modelo ${id.slice(-3)}`,
      codigoBarras: `789${id.slice(-3).padStart(10, '0')}`, publicadoNoCatalogo: true, preco: 89.9,
    });
    db.seed(base.collection('produtos').doc(id), {nome: id, quantidade: stock.quantidade, preco: 89.9});
  }
  db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds});
}

function seedSimple(db, base, lojaId, ids, qty) {
  for (const id of ids) seedProduct(db, base, lojaId, id, {quantidade: qty, stockKind: 'simple', tipoProduto: 'simples'});
}

const sum = cells => Object.values(cells).reduce((s, c) => s + Object.values(c).reduce((a, b) => a + b, 0), 0);
function seedCells(db, base, lojaId, id, variacoes, extra = {}) {
  seedProduct(db, base, lojaId, id, {stockKind: 'variation', quantidade: sum(variacoes), variacoes, ...extra});
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {protocolVersion: 1, lojaId, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload};
}

const line = (productId, qtySent = 1, variationKey) => ({
  productId, qtySent, unitSalePrice: 89.9, commissionType: 'PERCENTUAL', commissionValue: 30,
  ...(variationKey ? {variationKey} : {}),
});
const stock = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const consignment = (db, base, id) => db.getData(base.collection('consignments').doc(id));
const opDoc = (db, base, opId) => db.getData(base.collection('consignment_operations').doc(opId));
const run = (db, c) => executeConsignmentCommand(db, c, owner);

async function draftAndIssue(db, lojaId, lines) {
  const id = `c150_${++seq}`;
  await run(db, cmd(lojaId, 'createDraft', `draft_${id}`, {resellerId: 'r1', notes: '', lines}, id));
  const res = await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  return {id, res};
}

async function createDraft(db, lojaId, lines) {
  const id = `c150_${++seq}`;
  await run(db, cmd(lojaId, 'createDraft', `draft_${id}`, {resellerId: 'r1', notes: '', lines}, id));
  return id;
}

function issued150(qty = 2) {
  const s = newStore();
  seedSimple(s.db, s.base, s.lojaId, pids(N), qty);
  return s;
}

function stockOnlyChanges(before, after, allowed) {
  const changed = [];
  for (const key of new Set([...before.keys(), ...after.keys()])) {
    if (JSON.stringify(before.get(key)) !== JSON.stringify(after.get(key))) changed.push(key);
  }
  return changed.filter(k => !allowed(k));
}

// §7 distinct product contract
test('§7 distinct products counted by canonical productId: 150 x 2 variations allowed, 151 rejected before writes', async () => {
  const {db, base, lojaId} = newStore();
  for (const id of pids(N + 1)) seedCells(db, base, lojaId, id, {P: {'sem-cor': 1}, M: {'sem-cor': 1}});
  const lines = pids(N).flatMap(id => ['P', 'M'].map(size => line(id, 1, {size, color: 'sem-cor', extra: ''})));
  const {id, res} = await draftAndIssue(db, lojaId, lines);
  assert.equal(res.status, 'ISSUED');
  assert.equal(consignment(db, base, id).lines.length, 2 * N);
  const snapshot = db.snapshot();
  const over = [...lines.slice(0, 2), line(pid(N + 1), 1, {size: 'P', color: 'sem-cor', extra: ''})];
  await assert.rejects(createDraft(db, lojaId, [...lines.slice(3), ...over]),
    e => e.consignmentCode === CODES.CONSIGNMENT_PRODUCT_LIMIT);
  assert.deepEqual(db.snapshot(), snapshot);
});

// §9 exact cells
test('§9 EXACT_CELL_150: Tam20/Rubelita, letter J and color Gold decrement only their canonical cell', async () => {
  const {db, base, lojaId} = newStore();
  seedSimple(db, base, lojaId, pids(N - 3), 2);
  seedCells(db, base, lojaId, 'anel-rubelita', {'20': {Rubelita: 3, Esmeralda: 2}, '22': {Rubelita: 1}},
    {tamanhos: ['20', '22'], cores: ['Rubelita', 'Esmeralda']});
  seedCells(db, base, lojaId, 'pingente-letra', {J: {'sem-cor': 2}, K: {'sem-cor': 2}});
  seedCells(db, base, lojaId, 'brinco-cor', {'sem-tamanho': {Gold: 2, Silver: 2}});
  const lines = [
    ...pids(N - 3).map(id => line(id)),
    line('anel-rubelita', 2, {size: '20', color: 'Rubelita', extra: ''}),
    line('pingente-letra', 1, {size: 'J', color: 'sem-cor', extra: ''}),
    line('brinco-cor', 1, {size: 'sem-tamanho', color: 'Gold', extra: ''}),
  ];
  const {id, res} = await draftAndIssue(db, lojaId, lines);
  assert.equal(res.status, 'ISSUED');
  assert.equal(new Set(consignment(db, base, id).lines.map(l => l.productId)).size, N);
  const anel = stock(db, base, 'anel-rubelita');
  assert.deepEqual(anel.variacoes, {'20': {Rubelita: 1, Esmeralda: 2}, '22': {Rubelita: 1}});
  assert.equal(anel.quantidade, 4);
  const letra = stock(db, base, 'pingente-letra');
  assert.deepEqual(letra.variacoes, {J: {'sem-cor': 1}, K: {'sem-cor': 2}});
  const cor = stock(db, base, 'brinco-cor');
  assert.deepEqual(cor.variacoes, {'sem-tamanho': {Gold: 1, Silver: 2}});
  for (const p of pids(N - 3)) assert.equal(stock(db, base, p).quantidade, 1);
  const audit = db.getData(base.collection('consignment_audit').doc(`issue_${id}`));
  const anelAudit = audit.affectedProducts.find(a => a.productId === 'anel-rubelita');
  assert.deepEqual(anelAudit.cells, [{size: '20', color: 'Rubelita', extra: '', before: 3, after: 1}]);
  assert.equal(anelAudit.stockRevisionBefore + 1, anelAudit.stockRevision);
  console.log('EXACT_CELL_150_TEST_PASS=true');
});

test('§9 missing exact cell fails the whole 150 issue with zero changes (no sem-cor fallback)', async () => {
  const {db, base, lojaId} = newStore();
  seedSimple(db, base, lojaId, pids(N - 1), 2);
  seedCells(db, base, lojaId, 'pingente-letra', {J: {'sem-cor': 2}});
  const id = await createDraft(db, lojaId, [...pids(N - 1).map(p => line(p)),
    line('pingente-letra', 1, {size: 'J', color: 'sem-cor', extra: ''})]);
  const draft = consignment(db, base, id);
  draft.lines[N - 1].variationKey = {size: 'K', color: 'sem-cor', extra: ''};
  db.seed(base.collection('consignments').doc(id), draft);
  const snapshot = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id)),
    e => e.consignmentCode === CODES.VARIATION_NOT_FOUND);
  assert.deepEqual(db.snapshot(), snapshot);
});

// §5 write units, combos
test('§4/§5 150 products + max combo fan-out: fixed combos recalculated in the same commit within budget', async () => {
  const {db, base, lojaId} = newStore();
  const combos = MAX_STOCK_RECORDS_PER_TRANSACTION - N;
  pids(N).forEach((id, i) => seedProduct(db, base, lojaId, id, {quantidade: 3, stockKind: 'simple'},
    {comboIds: i < combos ? [`kit-${i}`] : []}));
  for (let i = 0; i < combos; i++) {
    seedProduct(db, base, lojaId, `kit-${i}`, {
      quantidade: 3, stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: pid(i + 1), quantidade: 1}],
    });
  }
  const {id, res} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 2)));
  assert.equal(res.status, 'ISSUED');
  const commit = commandCommit(db, `issue_${id}`);
  assert.equal(commitUnits(commit), MAX_STOCK_RECORDS_PER_TRANSACTION * WRITE_UNITS_PER_STOCK_RECORD + FIXED_WRITE_UNITS.issue);
  assert.ok(commitUnits(commit) <= MAX_TRANSACTION_WRITE_UNITS);
  assert.equal(commit.ops.filter(o => o.path.includes('/estoque_produtos/kit-')).length, combos);
  for (let i = 0; i < combos; i++) assert.equal(stock(db, base, `kit-${i}`).quantidade, 1);
  console.log(`ISSUE_150_PLUS_MAX_COMBO_WRITE_UNITS=${commitUnits(commit)}`);
});

test('§4 combo fan-out beyond MAX_STOCK_RECORDS_PER_TRANSACTION fails before writes', async () => {
  const {db, base, lojaId} = newStore();
  const combos = MAX_STOCK_RECORDS_PER_TRANSACTION - N + 1;
  pids(N).forEach((id, i) => seedProduct(db, base, lojaId, id, {quantidade: 3, stockKind: 'simple'},
    {comboIds: i < combos ? [`kit-${i}`] : []}));
  for (let i = 0; i < combos; i++) {
    seedProduct(db, base, lojaId, `kit-${i}`, {
      quantidade: 3, stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: pid(i + 1), quantidade: 1}],
    });
  }
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const snapshot = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id)),
    e => e.consignmentCode === CODES.RESOURCE_EXHAUSTED);
  assert.deepEqual(db.snapshot(), snapshot);
});

test('§4 addItems on an issued consignment recalculates fixed combos of the added products', async () => {
  const {db, base, lojaId} = newStore();
  seedProduct(db, base, lojaId, 'base-a', {quantidade: 3, stockKind: 'simple'});
  seedProduct(db, base, lojaId, 'base-b', {quantidade: 3, stockKind: 'simple'}, {comboIds: ['kit-b']});
  seedProduct(db, base, lojaId, 'kit-b', {
    quantidade: 3, stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: 'base-b', quantidade: 1}],
  });
  const {id} = await draftAndIssue(db, lojaId, [line('base-a')]);
  await run(db, cmd(lojaId, 'addItems', `add_${id}`, {
    expectedRevision: consignment(db, base, id).revision, lines: [line('base-b', 2)],
  }, id));
  assert.equal(stock(db, base, 'base-b').quantidade, 1);
  assert.equal(stock(db, base, 'kit-b').quantidade, 1);
});

// §10 forced failure at product 150
test('§10 ISSUE_150_ATOMIC_FAILURE: failure injected at the 150th stock write leaves 0 changes', async () => {
  const {db, base, lojaId} = issued150();
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const snapshot = db.snapshot();
  let stockWrites = 0;
  db.faultInjector = ({path}) => {
    if (path.includes('/estoque_produtos/') && ++stockWrites === N) throw new Error('injected failure at product 150');
  };
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id)), /product 150/);
  db.faultInjector = null;
  assert.equal(stockWrites, N);
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
  assert.equal(db.exists(base.collection('consignment_operations').doc(`issue_${id}`)), false);
  assert.equal(db.exists(base.collection('consignment_audit').doc(`issue_${id}`)), false);
  console.log('ISSUE_150_ATOMIC_FAILURE_TEST_PASS=true');
});

// §11 idempotency
test('§11 ISSUE_150_IDEMPOTENT: replay = 1 consignment, 1 decrement per product, 1 audit; altered payload fails closed', async () => {
  const {db, base, lojaId} = issued150(3);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p)));
  const after = db.snapshot();
  const replay = await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), after);
  for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 2);
  const keys = [...db._store.keys()];
  assert.equal(keys.filter(k => k.startsWith(`lojas/${lojaId}/consignments/`)).length, 1);
  assert.equal(keys.filter(k => k.startsWith(`lojas/${lojaId}/consignment_audit/`)).length, 1);
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {unexpected: true}, id)),
    e => e.consignmentCode === CODES.IDEMPOTENCY_CONFLICT);
  await assert.rejects(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), {uid: 'other'}));
  assert.deepEqual(db.snapshot(), after);
});

// §12 concurrency
test('§12 concurrent stock change that removes availability aborts the whole 150 issue atomically', async () => {
  const {db, base, lojaId} = issued150(1);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const lastRef = base.collection('estoque_produtos').doc(pid(N));
  let raced = false;
  db.onRead = (path, attempt) => {
    if (!raced && attempt === 1 && path === lastRef.path) {
      raced = true;
      db.concurrentWrite(lastRef, {...db.getData(lastRef), quantidade: 0, stockRevision: 4, stockOperationId: 'pdv_sale'});
    }
  };
  const before = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id)),
    e => e.consignmentCode === CODES.INSUFFICIENT_STOCK || e.consignmentCode === CODES.PRODUCT_VALIDATION_FAILED);
  db.onRead = null;
  assert.ok(raced);
  const changed = stockOnlyChanges(before, db.snapshot(), k => k === lastRef.path);
  assert.deepEqual(changed, []);
  assert.equal(stock(db, base, pid(N)).stockOperationId, 'pdv_sale');
  for (const p of pids(N - 1)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
  console.log('CONCURRENT_STOCK_CHANGE_150_ATOMIC=true');
});

test('§12 concurrent stock change that keeps availability: transaction retries on fresh canonical state, no lost update', async () => {
  const {db, base, lojaId} = issued150(5);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const lastRef = base.collection('estoque_produtos').doc(pid(N));
  let raced = false;
  db.onRead = (path, attempt) => {
    if (!raced && attempt === 1 && path === lastRef.path) {
      raced = true;
      db.concurrentWrite(lastRef, {...db.getData(lastRef), quantidade: 4, stockRevision: 4, stockOperationId: 'pdv_sale'});
    }
  };
  const res = await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  db.onRead = null;
  assert.ok(raced);
  assert.equal(res.status, 'ISSUED');
  assert.equal(stock(db, base, pid(N)).quantidade, 3);
  assert.equal(stock(db, base, pid(N)).stockRevision, 5);
  for (const p of pids(N - 1)) assert.equal(stock(db, base, p).quantidade, 4);
});

// §13 insufficient stock at product 149
test('§13 product 149 with insufficient stock: 150 issue fails with zero changes', async () => {
  const {db, base, lojaId} = issued150(1);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const ref149 = base.collection('estoque_produtos').doc(pid(149));
  db.seed(ref149, {...db.getData(ref149), quantidade: 0, stockRevision: 4});
  const snapshot = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id)),
    e => e.consignmentCode === CODES.INSUFFICIENT_STOCK);
  assert.deepEqual(db.snapshot(), snapshot);
  console.log('ISSUE_150_INSUFFICIENT_149_ZERO_CHANGES=true');
});

// §15 addItems contract
test('§15 addItems: 140 + 10 new; at 150 more qty and a new variation allowed; +1 new product blocked', async () => {
  const {db, base, lojaId} = newStore();
  seedSimple(db, base, lojaId, pids(N - 1), 5);
  seedSimple(db, base, lojaId, [pid(N + 1)], 5);
  seedCells(db, base, lojaId, pid(N), {P: {'sem-cor': 3}, M: {'sem-cor': 3}});
  const first = [...pids(140).map(p => line(p))];
  const {id} = await draftAndIssue(db, lojaId, first);
  const rev = () => consignment(db, base, id).revision;
  await run(db, cmd(lojaId, 'addItems', `add10_${id}`, {
    expectedRevision: rev(),
    lines: [...pids(N - 1).slice(140).map(p => line(p)), line(pid(N), 1, {size: 'P', color: 'sem-cor', extra: ''})],
  }, id));
  assert.equal(new Set(consignment(db, base, id).lines.map(l => l.productId)).size, N);
  await run(db, cmd(lojaId, 'addItems', `addqty_${id}`, {expectedRevision: rev(), lines: [line(pid(1), 2)]}, id));
  assert.equal(stock(db, base, pid(1)).quantidade, 2);
  await run(db, cmd(lojaId, 'addItems', `addvar_${id}`, {
    expectedRevision: rev(), lines: [line(pid(N), 1, {size: 'M', color: 'sem-cor', extra: ''})],
  }, id));
  assert.deepEqual(stock(db, base, pid(N)).variacoes, {P: {'sem-cor': 2}, M: {'sem-cor': 2}});
  const snapshot = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'addItems', `addnew_${id}`, {
    expectedRevision: rev(), lines: [line(pid(N + 1))],
  }, id)), e => e.consignmentCode === CODES.CONSIGNMENT_PRODUCT_LIMIT);
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(stock(db, base, pid(N + 1)).quantidade, 5);
});

// §16 partial return
for (const k of [1, 50, N]) {
  test(`§16 returnItems ${k} of 150 products: one atomic commit, exact restore`, async () => {
    const {db, base, lojaId} = issued150(3);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 2)));
    const doc = consignment(db, base, id);
    const rows = doc.lines.slice(0, k).map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1}));
    const before = db.commits.length;
    const res = await run(db, cmd(lojaId, 'returnItems', `ret_${id}`, {expectedRevision: doc.revision, lines: rows}, id));
    assert.equal(stockCommitsSince(db, before).length, 1);
    assert.equal(commitUnits(commandCommit(db, res.operationId)), k * WRITE_UNITS_PER_STOCK_RECORD + FIXED_WRITE_UNITS.returnItems);
    pids(N).forEach((p, i) => assert.equal(stock(db, base, p).quantidade, i < k ? 2 : 1));
    assert.equal(consignment(db, base, id).totalItemsWithdrawn, k);
  });
}

test('§16 return 150: failure injected at the 150th stock write leaves 0 changes', async () => {
  const {db, base, lojaId} = issued150(3);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 2)));
  const doc = consignment(db, base, id);
  const rows = doc.lines.map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1}));
  const snapshot = db.snapshot();
  let stockWrites = 0;
  db.faultInjector = ({path}) => {
    if (path.includes('/estoque_produtos/') && ++stockWrites === N) throw new Error('injected failure at product 150');
  };
  await assert.rejects(run(db, cmd(lojaId, 'returnItems', `ret_${id}`, {expectedRevision: doc.revision, lines: rows}, id)));
  db.faultInjector = null;
  assert.deepEqual(db.snapshot(), snapshot);
  console.log('RETURN_150_ATOMIC=true');
});

// §17 settlement
async function settle(db, base, lojaId, id, decide, opId = `settle_${id}`) {
  const doc = consignment(db, base, id);
  const lines = doc.lines.map((l, i) => {
    const [qtySold, qtyReturned] = decide(l, i);
    return {lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qtySold, qtyReturned};
  });
  return run(db, cmd(lojaId, 'settle', opId, {lines}, id));
}

const outstanding = l => l.qtySent - (l.qtyWithdrawn ?? 0);

test('§17 settle 150 all sold: sale + finance, no stock change, one commit', async () => {
  const {db, base, lojaId} = issued150(2);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p)));
  const before = db.snapshot();
  const res = await settle(db, base, lojaId, id, l => [outstanding(l), 0]);
  assert.equal(res.status, 'SETTLED');
  const commit = commandCommit(db, `settle_${id}`);
  assert.equal(commitUnits(commit), FIXED_WRITE_UNITS.settle);
  for (const p of pids(N)) assert.deepEqual(stock(db, base, p), before.get(`lojas/${lojaId}/estoque_produtos/${p}`));
  const sale = db.getData(base.collection('estoque_vendas').doc(res.saleId));
  assert.equal(sale.itens.length, N);
  assert.equal(sale.quantidade, N);
});

test('§17 settle 150 all returned / mixed / with withdrawals: atomic, exact, NO_DOUBLE_RETURN', async () => {
  // all returned
  {
    const {db, base, lojaId} = issued150(2);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p)));
    await settle(db, base, lojaId, id, l => [0, outstanding(l)]);
    for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 2);
    assert.equal(commitUnits(commandCommit(db, `settle_${id}`)), N * WRITE_UNITS_PER_STOCK_RECORD + 6);
  }
  // mixed
  {
    const {db, base, lojaId} = issued150(2);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 2)));
    const res = await settle(db, base, lojaId, id, () => [1, 1]);
    for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 1);
    assert.equal(commitUnits(commandCommit(db, `settle_${id}`)), N * WRITE_UNITS_PER_STOCK_RECORD + FIXED_WRITE_UNITS.settle);
    assert.equal(res.totalItemsSold, N);
    assert.equal(res.totalItemsReturned, N);
  }
  // with withdrawals
  {
    const {db, base, lojaId} = issued150(3);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 3)));
    const doc = consignment(db, base, id);
    const rows = doc.lines.slice(0, 50).map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 2}));
    await run(db, cmd(lojaId, 'returnItems', `ret_${id}`, {expectedRevision: doc.revision, lines: rows}, id));
    const snapshot = db.snapshot();
    await assert.rejects(settle(db, base, lojaId, id, l => [0, l.qtySent]),
      e => e.consignmentCode === CODES.INVALID_SETTLEMENT_TOTAL);
    assert.deepEqual(db.snapshot(), snapshot);
    await settle(db, base, lojaId, id, l => [1, outstanding(l) - 1]);
    pids(N).forEach((p, i) => assert.equal(stock(db, base, p).quantidade, 2, `product ${i}`));
    const after = db.snapshot();
    const replay = await settle(db, base, lojaId, id, l => [1, outstanding(l) - 1]);
    assert.equal(replay.alreadyApplied, true);
    assert.deepEqual(db.snapshot(), after);
    const fresh = consignment(db, base, id);
    await assert.rejects(run(db, cmd(lojaId, 'returnItems', `ret2_${id}`, {
      expectedRevision: fresh.revision,
      lines: [{lineId: fresh.lines[0].lineId, productId: fresh.lines[0].productId, variationKey: fresh.lines[0].variationKey, qty: 1}],
    }, id)), e => e.consignmentCode === CODES.CONSIGNMENT_ALREADY_SETTLED);
    assert.deepEqual(db.snapshot(), after);
  }
  console.log('SETTLEMENT_150_CAPACITY_SAFE=true NO_DOUBLE_RETURN=true');
});

test('§17 SETTLEMENT_150_ATOMIC: failure at the last write of a 150 mixed settlement leaves 0 changes', async () => {
  const {db, base, lojaId} = issued150(2);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 2)));
  const snapshot = db.snapshot();
  db.faultInjector = ({path}) => {
    if (path.includes('/consignment_operations/')) throw new Error('injected failure at final write');
  };
  await assert.rejects(settle(db, base, lojaId, id, () => [1, 1]), /final write/);
  db.faultInjector = null;
  assert.deepEqual(db.snapshot(), snapshot);
  assert.equal(consignment(db, base, id).status, 'ISSUED');
  console.log('SETTLEMENT_150_ATOMIC=true');
});

// §18 cancellation
test('§18 cancel 150: issued cannot be cancelled directly; full-return settlement restores all 150 atomically', async () => {
  const {db, base, lojaId} = issued150(2);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p)));
  const snapshot = db.snapshot();
  await assert.rejects(run(db, cmd(lojaId, 'cancelDraft', `cancel_${id}`, {}, id)),
    e => e.consignmentCode === CODES.CONSIGNMENT_ALREADY_ISSUED);
  assert.deepEqual(db.snapshot(), snapshot);
  let stockWrites = 0;
  db.faultInjector = ({path}) => {
    if (path.includes('/estoque_produtos/') && ++stockWrites === N) throw new Error('injected failure at product 150');
  };
  await assert.rejects(settle(db, base, lojaId, id, l => [0, outstanding(l)], `cancel_settle_${id}`));
  db.faultInjector = null;
  assert.deepEqual(db.snapshot(), snapshot);
  await settle(db, base, lojaId, id, l => [0, outstanding(l)], `cancel_settle_${id}`);
  for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 2);
  assert.equal(consignment(db, base, id).status, 'SETTLED');
  console.log('CANCEL_150_CAPACITY_SAFE=true CANCEL_150_ATOMIC=true');
});

// §3 post-commit projection
test('§3 projection failure never fails the committed stock operation; retry completes it idempotently', async () => {
  const {db, base, lojaId} = issued150(2);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  db.faultInjector = ({path}) => {
    if (path.includes('/draft_produtos/')) throw new Error('injected projection failure');
  };
  const res = await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  db.faultInjector = null;
  assert.equal(res.status, 'ISSUED');
  for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(opDoc(db, base, `issue_${id}`).projection.status, 'PENDING');
  assert.equal(db.getData(base.collection('draft_produtos').doc(pid(1))).catalogStockRevision, undefined);

  const first = await projectConsignmentCatalog(db, lojaId, `issue_${id}`);
  assert.equal(first.status, 'DONE');
  assert.equal(first.written, N);
  for (const p of pids(N)) {
    const draft = db.getData(base.collection('draft_produtos').doc(p));
    assert.equal(draft.catalogStockRevision, stock(db, base, p).stockRevision);
    assert.equal(draft.estoque, 1);
    assert.equal(db.getData(base.collection('produtos').doc(p)).quantidade, 1);
  }
  const settled = db.snapshot();
  assert.equal((await projectConsignmentCatalog(db, lojaId, `issue_${id}`)).status, 'SKIPPED');
  assert.deepEqual(db.snapshot(), settled);
  console.log('POST_COMMIT_PROJECTION_IDEMPOTENT=true');
});

test('§3 projection derives from current canonical stock, not the issue snapshot', async () => {
  const {db, base, lojaId} = issued150(2);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  db.faultInjector = ({path}) => { if (path.includes('/draft_produtos/')) throw new Error('defer'); };
  await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  db.faultInjector = null;
  const ref = base.collection('estoque_produtos').doc(pid(7));
  db.concurrentWrite(ref, {...db.getData(ref), quantidade: 6, stockRevision: 9, stockOperationId: 'restock'});
  await projectConsignmentCatalog(db, lojaId, `issue_${id}`);
  const draft = db.getData(base.collection('draft_produtos').doc(pid(7)));
  assert.equal(draft.estoque, 6);
  assert.equal(draft.catalogStockRevision, 9);
  console.log('CATALOG_NOT_STOCK_AUTHORITY=true');
});

test('§3 replay of the same operationId completes a PENDING projection; drafts are never recreated', async () => {
  const {db, base, lojaId} = newStore();
  seedSimple(db, base, lojaId, pids(N - 1), 2);
  seedProduct(db, base, lojaId, 'sem-draft', {quantidade: 2, stockKind: 'simple'}, {draft: false});
  const id = await createDraft(db, lojaId, [...pids(N - 1).map(p => line(p)), line('sem-draft')]);
  db.faultInjector = ({path}) => { if (path.includes('/draft_produtos/')) throw new Error('defer'); };
  await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  db.faultInjector = null;
  const op = opDoc(db, base, `issue_${id}`);
  assert.equal(op.projection.productIds.includes('sem-draft'), false);
  const replay = await run(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id));
  assert.equal(replay.alreadyApplied, true);
  assert.equal(opDoc(db, base, `issue_${id}`).projection.status, 'DONE');
  assert.equal(db.exists(base.collection('draft_produtos').doc('sem-draft')), false);
  assert.equal(db.exists(base.collection('produtos').doc('sem-draft')), false);
  assert.equal(stock(db, base, 'sem-draft').quantidade, 1);
});

test('§3 STOCK_SUCCESS_INDEPENDENT_OF_PROJECTION_LATENCY: a hung projection does not delay or fail the response', async () => {
  const {db, base, lojaId} = issued150(2);
  const id = await createDraft(db, lojaId, pids(N).map(p => line(p)));
  const realRun = db.runTransaction.bind(db);
  let committed = false;
  db.runTransaction = fn => (committed ? new Promise(() => {}) : realRun(fn).then(r => {
    committed = Boolean(commandCommit(db, `issue_${id}`));
    return r;
  }));
  const started = Date.now();
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner,
    {projectionBudgetMs: 50});
  assert.ok(Date.now() - started < 2000);
  db.runTransaction = realRun;
  assert.equal(res.status, 'ISSUED');
  for (const p of pids(N)) assert.equal(stock(db, base, p).quantidade, 1);
  assert.equal(opDoc(db, base, `issue_${id}`).projection.status, 'PENDING');
  console.log('STOCK_SUCCESS_INDEPENDENT_OF_PROJECTION_LATENCY=true');
});

// §8 document sizes. History = 1 addition of 150 lines + full-width withdrawals of all 300 lines.
const HISTORY_WITHDRAWALS = 1;
test('§8 document sizes at 150 products (simple, variated, with history) stay under the growth guard', async () => {
  const sizes = {};
  {
    const {db, base, lojaId} = issued150(2);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p)));
    const ref = base.collection('consignments').doc(id);
    sizes.DOC_SIZE_150_SIMPLE = firestoreDocumentBytes(ref.path, db.getData(ref));
  }
  {
    const {db, base, lojaId} = newStore();
    for (const id of pids(N)) seedCells(db, base, lojaId, id, {'20': {Rubelita: 2}, '22': {Rubelita: 2}},
      {tamanhos: ['20', '22'], cores: ['Rubelita']});
    const lines = pids(N).flatMap(id => ['20', '22'].map(size => line(id, 1, {size, color: 'Rubelita', extra: ''})));
    const {id} = await draftAndIssue(db, lojaId, lines);
    const ref = base.collection('consignments').doc(id);
    sizes.DOC_SIZE_150_VARIATED = firestoreDocumentBytes(ref.path, db.getData(ref));
    assert.equal(db.getData(ref).lines.length, MAX_LINES);
    sizes.SETTLE_COMMAND_BYTES_VARIATED = settlementCommandBytes(lojaId, id, db.getData(ref).lines);
  }
  {
    const {db, base, lojaId} = issued150(20);
    const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 8)));
    const addId = `consignment_add_${id}_k3J9xQ2mWv8LpR4tZy7N`;
    await run(db, cmd(lojaId, 'addItems', addId, {
      expectedRevision: consignment(db, base, id).revision, lines: pids(N).map(p => line(p, 8)),
    }, id));
    for (let w = 0; w < HISTORY_WITHDRAWALS; w++) {
      const doc = consignment(db, base, id);
      const rows = doc.lines.map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1}));
      await run(db, cmd(lojaId, 'returnItems', `consignment_return_${id}_${w}_aB3dE5fG7hJ9kL1mN3pQ`, {
        expectedRevision: doc.revision, lines: rows,
      }, id));
    }
    const ref = base.collection('consignments').doc(id);
    const doc = db.getData(ref);
    assert.equal(doc.lines.length, MAX_LINES);
    assert.equal(doc.withdrawals.length, HISTORY_WITHDRAWALS);
    sizes.DOC_SIZE_150_WITH_HISTORY = firestoreDocumentBytes(ref.path, doc);
    sizes.SETTLE_COMMAND_BYTES_WITH_HISTORY = settlementCommandBytes(lojaId, id, doc.lines);
    await settle(db, base, lojaId, id, l => [1, outstanding(l) - 1]);
    sizes.DOC_SIZE_150_WITH_HISTORY_SETTLED = firestoreDocumentBytes(ref.path, db.getData(ref));
    const audit = db.getData(base.collection('consignment_audit').doc(`settle_${id}`));
    sizes.AUDIT_SIZE_150_SETTLE = firestoreDocumentBytes('a', audit);
    sizes.OP_SIZE_150_SETTLE = firestoreDocumentBytes('a', opDoc(db, base, `settle_${id}`));
  }
  for (const k of ['DOC_SIZE_150_SIMPLE', 'DOC_SIZE_150_VARIATED', 'DOC_SIZE_150_WITH_HISTORY']) {
    assert.ok(sizes[k] < MAX_CONSIGNMENT_DOC_BYTES, `${k}=${sizes[k]}`);
  }
  assert.ok(sizes.DOC_SIZE_150_WITH_HISTORY_SETTLED < 1024 * 1024);
  assert.ok(sizes.SETTLE_COMMAND_BYTES_WITH_HISTORY < MAX_SETTLEMENT_COMMAND_BYTES);
  assert.ok(sizes.AUDIT_SIZE_150_SETTLE < 256 * 1024);
  assert.ok(sizes.OP_SIZE_150_SETTLE < 256 * 1024);
  console.log(`DOC_SIZES ${JSON.stringify(sizes)}`);
});

test('§8 growth guard: history that would leave settlement without room is rejected with 0 changes; settle still works', async () => {
  const {db, base, lojaId} = issued150(200);
  const {id} = await draftAndIssue(db, lojaId, pids(N).map(p => line(p, 100)));
  await run(db, cmd(lojaId, 'addItems', `consignment_add_${id}_x`, {
    expectedRevision: consignment(db, base, id).revision, lines: pids(N).map(p => line(p, 50)),
  }, id));
  let rejected = false;
  for (let w = 0; w < 40 && !rejected; w++) {
    const doc = consignment(db, base, id);
    const rows = doc.lines.map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1}));
    const snapshot = db.snapshot();
    try {
      await run(db, cmd(lojaId, 'returnItems', `ret_${id}_${w}`, {expectedRevision: doc.revision, lines: rows}, id));
    } catch (e) {
      assert.equal(e.consignmentCode, CODES.RESOURCE_EXHAUSTED);
      assert.match(e.message, /document capacity/);
      assert.deepEqual(db.snapshot(), snapshot);
      rejected = true;
    }
  }
  assert.ok(rejected, 'guard must trigger before 1 MiB');
  const ref = base.collection('consignments').doc(id);
  assert.ok(firestoreDocumentBytes(ref.path, db.getData(ref)) <= MAX_CONSIGNMENT_DOC_BYTES);
  const res = await settle(db, base, lojaId, id, l => [0, outstanding(l)]);
  assert.equal(res.status, 'SETTLED');
  assert.ok(firestoreDocumentBytes(ref.path, db.getData(ref)) < 1024 * 1024);
});

test('§8 settlement-command guard: lines whose settle payload would not fit are rejected at draft time', async () => {
  const {db, base, lojaId} = newStore();
  const longId = i => `${'p'.repeat(240)}-${String(i).padStart(3, '0')}`;
  const size = s => `${s}${'x'.repeat(200)}`;
  for (let i = 1; i <= N; i++) {
    seedCells(db, base, lojaId, longId(i), {[size('A')]: {'sem-cor': 1}, [size('B')]: {'sem-cor': 1}});
  }
  const lines = Array.from({length: N}, (_, i) => ['A', 'B'].map(s => line(longId(i + 1), 1, {size: size(s), color: 'sem-cor', extra: ''}))).flat();
  const snapshot = db.snapshot();
  await assert.rejects(createDraft(db, lojaId, lines),
    e => e.consignmentCode === CODES.RESOURCE_EXHAUSTED && /settlement command/.test(e.message));
  assert.deepEqual(db.snapshot(), snapshot);
  assert.ok(MAX_SETTLEMENT_COMMAND_BYTES < MAX_COMMAND_BYTES);
});
