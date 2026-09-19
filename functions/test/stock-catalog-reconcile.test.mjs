import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore, Timestamp} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';
import {emitRestoreAppliedSaleRequiredLog, sanitizeRestorePreconditionLog} from '../src/stockCatalogObservability.js';

const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
const db = new Firestore({projectId: 'demo-stock-reconcile'});
after(() => db.terminate());
const runId = Date.now().toString(36);
let sequence = 0;
const COUNTED = '2026-09-18T12:00:00.000Z';
const BEFORE_COUNT = Timestamp.fromDate(new Date('2026-09-18T11:00:00.000Z'));
const AFTER_COUNT = Timestamp.fromDate(new Date('2026-09-18T13:00:00.000Z'));
const owner = {uid: 'owner'};

async function seed(product = {}) {
  const lojaId = `rec_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const stock = {
    quantidade: 0,
    stockKind: 'simple',
    stockRevision: 0,
    stockUpdatedAt: BEFORE_COUNT,
    ...product,
  };
  const batch = db.batch();
  batch.set(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
  batch.set(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true}});
  batch.set(base.collection('stock_reconciliation_control').doc('state'), {reconciliationEnabled: true, reference: 'emulator-reconcile-suite'});
  batch.set(base.collection('stock_reconciliation_operators').doc('owner'), {enabled: true});
  batch.set(base.collection('estoque_produtos').doc('p'), stock);
  batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Peca Tecnica', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  await batch.commit();
  return {base, lojaId};
}

function reconcile(lojaId, operationId, item = {}, extra = {}) {
  const row = {productId: 'p', expectedRevision: 0, ...item};
  if (!('confirmedPhysicalQty' in row) && extra.omitQty !== true) row.confirmedPhysicalQty = 0;
  if (extra.omitQty) delete row.confirmedPhysicalQty;
  const cmd = {
    protocolVersion: 1,
    lojaId,
    kind: 'reconcile',
    operationId,
    reconciliationId: extra.reconciliationId ?? operationId,
    items: [row],
  };
  if (extra.omitCountedAt !== true) cmd.countedAt = extra.countedAt ?? COUNTED;
  if (extra.definition) cmd.definition = extra.definition;
  if (extra.quantidade != null) cmd.quantidade = extra.quantidade;
  return cmd;
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {protocolVersion: 1, lojaId, kind, operationId, items: [{productId: 'p', quantity: 1, ...item}], ...extra};
}

async function stockOf(base, id = 'p') {
  return (await base.collection('estoque_produtos').doc(id).get()).data();
}
async function denied(promise, code, message) {
  await assert.rejects(promise, e => e.code === code && (message == null || e.message === message));
}
function captureInfo(run) {
  const lines = [];
  const orig = console.info;
  console.info = (...args) => lines.push(args.map(String).join(' '));
  return Promise.resolve().then(run).finally(() => { console.info = orig; }).then(result => ({result, lines}));
}

test('1 confirmed qty 0 accepted', async () => {
  const {base, lojaId} = await seed({quantidade: 2});
  const r = await executeStockCommand(db, reconcile(lojaId, 'r0', {confirmedPhysicalQty: 0}), owner);
  assert.equal((await stockOf(base)).quantidade, 0);
  assert.equal(r.confirmedQty, 0);
  assert.equal(r.delta, -2);
});

test('2 positive integer accepted', async () => {
  const {base, lojaId} = await seed();
  const r = await executeStockCommand(db, reconcile(lojaId, 'rpos', {confirmedPhysicalQty: 3}), owner);
  assert.equal((await stockOf(base)).quantidade, 3);
  assert.equal(r.confirmedQty, 3);
});

test('3 negative rejected', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'rneg', {confirmedPhysicalQty: -1}), owner), 'invalid-argument');
});

test('4 decimal rejected', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'rdec', {confirmedPhysicalQty: 1.5}), owner), 'invalid-argument');
});

test('5 missing qty rejected', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'rmiss', {}, {omitQty: true}), owner), 'invalid-argument');
});

test('6 missing countedAt rejected', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'rtime', {confirmedPhysicalQty: 1}, {omitCountedAt: true}), owner), 'invalid-argument');
});

test('7 invalid variation key rejected', async () => {
  const {lojaId} = await seed({stockKind: 'variation', quantidade: 1, variacoes: {'18': {rosa: 1}}});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'rkey', {confirmedPhysicalQty: 2, size: 'P', color: 'Azul'}), owner),
    'failed-precondition',
    'RECONCILIATION_VARIATION_IDENTITY',
  );
});

test('8 wrong product rejected', async () => {
  const {lojaId} = await seed();
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'rprod', {productId: 'missing', confirmedPhysicalQty: 1}), owner),
    'failed-precondition',
  );
});

test('9 wrong store blocked', async () => {
  const {lojaId} = await seed();
  const other = await seed();
  await other.base.collection('stock_catalog_access').doc('owner').delete();
  await other.base.collection('stock_reconciliation_control').doc('state').delete();
  await other.base.collection('stock_reconciliation_operators').doc('owner').delete();
  await denied(executeStockCommand(db, reconcile(other.lojaId, 'rstore', {confirmedPhysicalQty: 1}), owner), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  await executeStockCommand(db, reconcile(lojaId, 'rok', {confirmedPhysicalQty: 1}), owner);
});

test('10 expected revision match succeeds', async () => {
  const {base, lojaId} = await seed({quantidade: 1, stockRevision: 4});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rcas', {confirmedPhysicalQty: 2, expectedRevision: 4}), owner);
  assert.equal((await stockOf(base)).quantidade, 2);
  assert.equal(r.expectedRevision, 4);
  assert.equal(r.resultingRevision, 5);
});

test('11 stale revision blocked', async () => {
  const {base, lojaId} = await seed({quantidade: 1, stockRevision: 2});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'rstale', {confirmedPhysicalQty: 4, expectedRevision: 0}), owner),
    'aborted',
    'RECONCILIATION_STALE_REMOTE_CONFLICT',
  );
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('12 post-count stock movement blocked', async () => {
  const {base, lojaId} = await seed({quantidade: 1, stockRevision: 1, stockUpdatedAt: AFTER_COUNT});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'rpost', {confirmedPhysicalQty: 4, expectedRevision: 1}), owner),
    'failed-precondition',
    'RECONCILIATION_POST_COUNT_MOVEMENT',
  );
  assert.equal((await stockOf(base)).quantidade, 1);
  assert.equal((await base.collection('stock_catalog_operations').doc('rpost').get()).exists, false);
});

test('13 only target variation changes', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 3,
    variacoes: {'18': {rosa: 1, prata: 2}},
  });
  await executeStockCommand(db, reconcile(lojaId, 'rtgt', {confirmedPhysicalQty: 5, size: '18', color: 'rosa'}), owner);
  const s = await stockOf(base);
  assert.equal(s.variacoes['18'].rosa, 5);
  assert.equal(s.variacoes['18'].prata, 2);
});

test('14 other variation cells unchanged', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 4,
    variacoes: {P: {Azul: 1, Vermelho: 3}},
  });
  await executeStockCommand(db, reconcile(lojaId, 'roth', {confirmedPhysicalQty: 0, size: 'P', color: 'Azul'}), owner);
  const s = await stockOf(base);
  assert.equal(s.variacoes.P.Azul, 0);
  assert.equal(s.variacoes.P.Vermelho, 3);
});

test('15 EPT regenerated canonical', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 3,
    variacoes: {'20': {prata: 0, ouro: 3}},
    estoquePorTamanho: {'20': 99},
  });
  await executeStockCommand(db, reconcile(lojaId, 'rept', {confirmedPhysicalQty: 4, size: '20', color: 'prata'}), owner);
  const s = await stockOf(base);
  assert.equal(s.estoquePorTamanho['20'], 7);
  assert.equal(s.variacoes['20'].prata, 4);
  assert.equal(s.variacoes['20'].ouro, 3);
});

test('16 aggregate regenerated canonical', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 99,
    variacoes: {'17': {rosa: 0, prata: 2}},
  });
  await executeStockCommand(db, reconcile(lojaId, 'ragg', {confirmedPhysicalQty: 6, size: '17', color: 'rosa'}), owner);
  assert.equal((await stockOf(base)).quantidade, 8);
});

test('17 incoming EPT ignored', async () => {
  const {lojaId} = await seed();
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'reptin', {confirmedPhysicalQty: 1}, {definition: {estoquePorTamanho: {P: 99}, quantidade: 99}}), owner),
    'invalid-argument',
  );
});

test('18 incoming aggregate ignored', async () => {
  const {lojaId} = await seed();
  const cmd = reconcile(lojaId, 'raggin', {confirmedPhysicalQty: 1});
  cmd.quantidade = 99;
  await denied(executeStockCommand(db, cmd, owner), 'invalid-argument');
});

test('19 server calculates delta', async () => {
  const {lojaId} = await seed({quantidade: 5});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rdelta', {confirmedPhysicalQty: 2}), owner);
  assert.equal(r.previousQty, 5);
  assert.equal(r.confirmedQty, 2);
  assert.equal(r.delta, -3);
});

test('20 zero delta no-op', async () => {
  const {base, lojaId} = await seed({quantidade: 2, stockRevision: 3, stockOperationId: 'prior'});
  const before = await stockOf(base);
  const r = await executeStockCommand(db, reconcile(lojaId, 'rzero', {confirmedPhysicalQty: 2, expectedRevision: 3}), owner);
  assert.equal(r.alreadyReconciled, true);
  assert.equal(r.delta, 0);
  const after = await stockOf(base);
  assert.equal(after.quantidade, 2);
  assert.equal(after.stockRevision, 3);
  assert.equal(after.stockOperationId, 'prior');
  assert.equal(before.stockUpdatedAt.toMillis(), after.stockUpdatedAt.toMillis());
});

test('21 positive reconciliation', async () => {
  const {lojaId} = await seed({quantidade: 1});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rplus', {confirmedPhysicalQty: 4}), owner);
  assert.equal(r.delta, 3);
});

test('22 negative reconciliation', async () => {
  const {lojaId} = await seed({quantidade: 5});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rminus', {confirmedPhysicalQty: 2}), owner);
  assert.equal(r.delta, -3);
});

test('23 zero to positive', async () => {
  const {base, lojaId} = await seed({quantidade: 0});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rzp', {confirmedPhysicalQty: 3}), owner);
  assert.equal(r.delta, 3);
  assert.equal((await stockOf(base)).quantidade, 3);
});

test('24 positive to zero', async () => {
  const {base, lojaId} = await seed({quantidade: 4});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rpz', {confirmedPhysicalQty: 0}), owner);
  assert.equal(r.delta, -4);
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('25 duplicate reconciliationId same payload idempotent', async () => {
  const {base, lojaId} = await seed();
  const cmd = reconcile(lojaId, 'ridem', {confirmedPhysicalQty: 3});
  const first = await executeStockCommand(db, cmd, owner);
  const second = await executeStockCommand(db, cmd, owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal((await stockOf(base)).quantidade, 3);
  assert.equal((await stockOf(base)).stockRevision, 1);
  assert.equal((await base.collection('stock_catalog_operations').get()).size, 1);
});

test('26 duplicate reconciliationId conflicting payload rejected', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'rconf', {confirmedPhysicalQty: 3}), owner);
  await denied(executeStockCommand(db, reconcile(lojaId, 'rconf', {confirmedPhysicalQty: 9}), owner), 'already-exists');
  assert.equal((await stockOf(base)).quantidade, 3);
});

test('27 resulting revision advances once', async () => {
  const {base, lojaId} = await seed({stockRevision: 2, quantidade: 0});
  const r = await executeStockCommand(db, reconcile(lojaId, 'rrev', {confirmedPhysicalQty: 1, expectedRevision: 2}), owner);
  assert.equal(r.resultingRevision, 3);
  assert.equal((await stockOf(base)).stockRevision, 3);
  await executeStockCommand(db, reconcile(lojaId, 'rrev', {confirmedPhysicalQty: 1, expectedRevision: 2}), owner);
  assert.equal((await stockOf(base)).stockRevision, 3);
});

test('28 audit operation written once', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  await executeStockCommand(db, reconcile(lojaId, 'raud', {confirmedPhysicalQty: 4}), owner);
  await executeStockCommand(db, reconcile(lojaId, 'raud', {confirmedPhysicalQty: 4}), owner);
  const ops = await base.collection('stock_catalog_operations').get();
  assert.equal(ops.size, 1);
  const op = ops.docs[0].data();
  assert.equal(op.kind, 'reconcile');
  assert.equal(op.operationType, 'physical_stock_reconciliation');
  assert.equal(op.reconciliationId, 'raud');
  assert.equal(op.productId, 'p');
  assert.equal(op.previousQty, 1);
  assert.equal(op.confirmedQty, 4);
  assert.equal(op.delta, 3);
  assert.equal(op.expectedRevision, 0);
  assert.equal(op.resultingRevision, 1);
  assert.equal(op.countedAt, COUNTED);
  assert.equal(op.actorUid, 'owner');
  assert.ok(op.appliedAt);
  const json = JSON.stringify(op);
  assert.equal(json.includes('Peca Tecnica'), false);
});

test('29 transaction failure writes nothing', async () => {
  const {base, lojaId} = await seed({quantidade: 2, stockRevision: 1});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'rfail', {confirmedPhysicalQty: 9, expectedRevision: 0}), owner),
    'aborted',
    'RECONCILIATION_STALE_REMOTE_CONFLICT',
  );
  assert.equal((await stockOf(base)).quantidade, 2);
  assert.equal((await base.collection('stock_catalog_operations').doc('rfail').get()).exists, false);
});

test('30 concurrent revision conflict writes nothing for loser', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  const results = await Promise.allSettled([
    executeStockCommand(db, reconcile(lojaId, 'rc1', {confirmedPhysicalQty: 4}), owner),
    executeStockCommand(db, reconcile(lojaId, 'rc2', {confirmedPhysicalQty: 7}), owner),
  ]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const rejected = results.filter(r => r.status === 'rejected');
  assert.equal(rejected.length, 1);
  assert.ok(
    rejected[0].reason?.message === 'RECONCILIATION_STALE_REMOTE_CONFLICT' ||
    rejected[0].reason?.message === 'RECONCILIATION_POST_COUNT_MOVEMENT',
    rejected[0].reason?.message || String(rejected[0].reason),
  );
  const s = await stockOf(base);
  assert.ok(s.quantidade === 4 || s.quantidade === 7);
  assert.equal((await base.collection('stock_catalog_operations').get()).size, 1);
});

test('31 no sale document', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'rnsale', {confirmedPhysicalQty: 2}), owner);
  assert.equal((await base.collection('estoque_vendas').get()).empty, true);
});

test('32 no financial document', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'rnfin', {confirmedPhysicalQty: 2}), owner);
  assert.equal((await base.collection('contas_receber').get()).empty, true);
  assert.equal((await base.collection('caixa_movimentos').get()).empty, true);
  assert.equal((await base.collection('comissoes').get()).empty, true);
});

test('33 no queue replay', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'rnq', {confirmedPhysicalQty: 2}), owner);
  assert.equal((await base.collection('product_sync_queue').get()).empty, true);
  assert.equal((await base.collection('fila_produtos').get()).empty, true);
});

test('34 existing sale decrement preserved', async () => {
  const {base, lojaId} = await seed({quantidade: 2});
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('35 existing restock preserved', async () => {
  const {base, lojaId} = await seed({quantidade: 0});
  await executeStockCommand(db, intent(lojaId, 'restock', 'rs1'), owner);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('36 existing replace preserved', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'rep1',
    items: [{productId: 'p', expectedRevision: 0}],
    definition: {quantidade: 8, variacoes: {}},
    editorial: {nome: 'p', publicadoNoCatalogo: true},
  }, owner);
  assert.equal((await stockOf(base)).quantidade, 8);
});

test('37 sale-delete observability preserved', async () => {
  const {base, lojaId} = await seed({quantidade: 4});
  const {lines} = await captureInfo(async () => {
    await denied(
      executeStockCommand(db, intent(lojaId, 'restore', 'r-missing', {}, {sourceOperationId: 'missing-sale'}), owner),
      'failed-precondition',
    );
  });
  const parsed = lines.map(line => { try { return JSON.parse(line); } catch { return null; } })
    .filter(payload => payload && payload.event === 'stock_restore_precondition');
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].reason, 'applied_sale_required');
  assert.equal(parsed[0].lookupKey, 'missing-sale');
  assert.equal('items' in parsed[0], false);
  assert.equal((await stockOf(base)).quantidade, 4);
  const unit = sanitizeRestorePreconditionLog({
    lojaId, operationId: 'r-missing', sourceOperationId: 'missing-sale',
    sourceExists: false, customerName: 'secret',
  });
  assert.equal(unit.reason, 'applied_sale_required');
  assert.equal('customerName' in unit, false);
  assert.equal(typeof emitRestoreAppliedSaleRequiredLog, 'function');
});

test('38 current restore behavior preserved', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  await executeStockCommand(db, intent(lojaId, 'sale', 's-ok'), owner);
  await executeStockCommand(db, intent(lojaId, 'restore', 'r-ok', {}, {sourceOperationId: 's-ok'}), owner);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('39 simple product behavior unaffected', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  await publishStockProduct(db, lojaId, 'p', owner);
  await executeStockCommand(db, intent(lojaId, 'sale', 's-simple'), owner);
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('40 variation/grade current guards preserved', async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', quantidade: 3, variacoes: {P: {Azul: 1, Vermelho: 2}}});
  await executeStockCommand(db, intent(lojaId, 'sale', 's-var', {size: 'P', color: 'azul'}), owner);
  const s = await stockOf(base);
  assert.equal(s.variacoes.P.Azul, 0);
  assert.equal(s.variacoes.P.Vermelho, 2);
});

test('41 unauthenticated denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'runauth', {confirmedPhysicalQty: 1}), null), 'unauthenticated');
});

test('42 NaN and string qty rejected', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'rnan', {confirmedPhysicalQty: Number.NaN}), owner), 'invalid-argument');
  await denied(executeStockCommand(db, reconcile(lojaId, 'rstr', {confirmedPhysicalQty: '3'}), owner), 'invalid-argument');
});
