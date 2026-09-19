import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Firestore, FieldValue, Timestamp} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  STOCK_RECONCILIATION_GRANT,
  authorizeDedicatedReconciliation,
  SERVER_PAYMENT_AUTH,
} from '../src/stockCatalogAccess.js';
import {emitRestoreAppliedSaleRequiredLog, sanitizeRestorePreconditionLog} from '../src/stockCatalogObservability.js';

const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
const db = new Firestore({projectId: 'demo-recon-grant'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const COUNTED = '2026-09-18T12:00:00.000Z';
const BEFORE_COUNT = Timestamp.fromDate(new Date('2026-09-18T11:00:00.000Z'));
const AFTER_COUNT = Timestamp.fromDate(new Date('2026-09-18T13:00:00.000Z'));
const operator = {uid: 'recon-op'};
const owner = {uid: 'owner'};
const customer = {uid: 'customer'};

function commandsSrc() {
  return readFileSync(new URL('../src/stockCatalogCommands.js', import.meta.url), 'utf8');
}
function accessSrc() {
  return readFileSync(new URL('../src/stockCatalogAccess.js', import.meta.url), 'utf8');
}
function rulesSrc() {
  return readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
}

async function seed(opts = {}) {
  const lojaId = opts.lojaId ?? `rg_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {
    ownerUid: opts.ownerUid ?? 'owner',
    name: 'Grant Fixture',
    ...(opts.admins ? {admins: opts.admins} : {}),
  });
  const stock = {
    quantidade: opts.quantidade ?? 0,
    stockKind: opts.stockKind ?? 'simple',
    stockRevision: opts.stockRevision ?? 0,
    stockUpdatedAt: opts.stockUpdatedAt ?? BEFORE_COUNT,
    ...(opts.variacoes ? {variacoes: opts.variacoes} : {}),
    ...(opts.estoquePorTamanho ? {estoquePorTamanho: opts.estoquePorTamanho} : {}),
    ...(opts.estoquePorCor ? {estoquePorCor: opts.estoquePorCor} : {}),
  };
  batch.set(base.collection('estoque_produtos').doc(opts.productId ?? 'p'), stock);
  batch.set(base.collection('draft_produtos').doc(opts.productId ?? 'p'), {nome: 'Peca Tecnica', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc(opts.productId ?? 'p'), {comboIds: []});
  if (opts.protocol === 'active') {
    batch.set(base.collection('stock_catalog_control').doc('state'), {
      protocolVersion: 1, mode: 'active', migrationComplete: true,
    });
  } else if (opts.protocol === 'inactive') {
    batch.set(base.collection('stock_catalog_control').doc('state'), {
      protocolVersion: 1, mode: 'inactive',
    });
  }
  if (opts.access) {
    batch.set(base.collection('stock_catalog_access').doc(opts.access.uid ?? 'owner'), {
      enabled: opts.access.enabled !== false,
      permissions: opts.access.permissions ?? {sale: true, restock: true, adjust: true, restore: true},
    });
  }
  if (opts.grant !== false) {
    const grantDoc = opts.grant === undefined || opts.grant === true
      ? {reconciliationEnabled: true, reference: 'emulator-dedicated-grant'}
      : opts.grant;
    if (grantDoc) {
      batch.set(base.collection('stock_reconciliation_control').doc('state'), grantDoc);
    }
  }
  if (opts.operator !== false) {
    const opUid = typeof opts.operator === 'string' ? opts.operator : (opts.operatorUid ?? 'recon-op');
    const opDoc = opts.operatorDoc ?? {enabled: true};
    if (opDoc) batch.set(base.collection('stock_reconciliation_operators').doc(opUid), opDoc);
  }
  if (opts.member) {
    batch.set(base.collection('members').doc(opts.member.uid), {role: opts.member.role});
  }
  if (opts.publicCatalog) {
    batch.set(base.collection('produtos_publicos').doc('p'), {nome: 'catalog', quantidade: 0});
  }
  await batch.commit();
  return {base, lojaId};
}

function reconcile(lojaId, operationId, item = {}, extra = {}) {
  const row = {productId: extra.productId ?? 'p', expectedRevision: extra.expectedRevision ?? 0, ...item};
  if (!('confirmedPhysicalQty' in row) && extra.omitQty !== true) row.confirmedPhysicalQty = extra.confirmedPhysicalQty ?? 1;
  if (extra.omitQty) delete row.confirmedPhysicalQty;
  const cmd = {
    protocolVersion: 1,
    lojaId,
    kind: extra.kind ?? 'reconcile',
    operationId,
    reconciliationId: extra.reconciliationId ?? operationId,
    items: [row],
    ...extra.cmd,
  };
  if (extra.omitCountedAt !== true && extra.kind !== 'sale') cmd.countedAt = extra.countedAt ?? COUNTED;
  return cmd;
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {protocolVersion: 1, lojaId, kind, operationId, items: [{productId: 'p', quantity: 1, ...item}], ...extra};
}

function atomicSale(lojaId, operationId, item = {}) {
  return {
    protocolVersion: 1,
    lojaId,
    kind: 'sale',
    operationId,
    atomicPdvSale: true,
    items: [{productId: 'p', quantity: 1, ...item}],
    sale: {
      clienteNome: 'Cliente Teste',
      produtosDescricao: '1 x Peca',
      quantidade: 1,
      preco: 10,
      total: 10,
      formasPagamento: 'Pagamento Dinheiro: R$ 10.00',
      frete: 0,
      desconto: 0,
      descontoValor: 0,
      observacao: '',
      pagamentoDinheiro: 10,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      taxas: 0,
      custoProdutos: 0,
      tamanho: '',
      vendedor: 'App',
      itens: [{
        produtoNome: 'Peca', quantidade: 1, tamanho: '', cor: '',
        precoUnitario: 10, precoTotal: 10, productId: 'p',
      }],
    },
  };
}

async function stockOf(base, id = 'p') {
  return (await base.collection('estoque_produtos').doc(id).get()).data();
}
async function denied(promise, code, message) {
  await assert.rejects(promise, e => e.code === code && (message == null || e.message === message));
}

test('01 dedicated grant missing -> reconcile denied', async () => {
  const {base, lojaId} = await seed({grant: false});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g1'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('02 dedicated grant false -> denied', async () => {
  const {lojaId} = await seed({grant: {reconciliationEnabled: false}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g2'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('03 dedicated grant true -> permitted', async () => {
  const {base, lojaId} = await seed();
  const r = await executeStockCommand(db, reconcile(lojaId, 'g3'), operator);
  assert.equal(r.confirmedQty, 1);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('04 wrong store grant -> denied', async () => {
  const a = await seed();
  const b = await seed({grant: false, operator: false});
  await denied(executeStockCommand(db, reconcile(b.lojaId, 'g4'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  await executeStockCommand(db, reconcile(a.lojaId, 'g4ok'), operator);
});

test('05 grant for store A does not authorize store B', async () => {
  const a = await seed();
  const b = await seed({grant: false});
  await denied(executeStockCommand(db, reconcile(b.lojaId, 'g5'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  assert.equal((await stockOf(a.base)).quantidade, 0);
  assert.equal((await stockOf(b.base)).quantidade, 0);
});

test('06 broad protocol false + dedicated true -> reconcile allowed', async () => {
  const {base, lojaId} = await seed({protocol: null});
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  const r = await executeStockCommand(db, reconcile(lojaId, 'g6'), operator);
  assert.equal(r.delta, 1);
  assert.equal(STOCK_RECONCILIATION_GRANT, 'stockReconciliationGrant');
});

test('07 broad protocol false + dedicated true -> variation sale still restricted', async () => {
  const {lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 2,
    variacoes: {P: {Azul: 1, Vermelho: 1}},
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'g7sale', {size: 'P', color: 'azul'}), operator),
    'permission-denied',
  );
  await executeStockCommand(db, reconcile(lojaId, 'g7rec', {confirmedPhysicalQty: 3, size: 'P', color: 'Azul'}), operator);
});

test('08 broad protocol false + dedicated true -> grade sale still restricted', async () => {
  const {lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 2,
    variacoes: {'18': {rosa: 1}, '20': {rosa: 1}},
    estoquePorTamanho: {'18': 1, '20': 1},
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'g8sale', {size: '18', color: 'rosa'}), operator),
    'permission-denied',
  );
});

test('09 dedicated true does not enable replace', async () => {
  const {base, lojaId} = await seed();
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'g9',
    items: [{productId: 'p', expectedRevision: 0}],
    definition: {quantidade: 9, variacoes: {}},
    editorial: {nome: 'x', publicadoNoCatalogo: true},
  }, operator), 'permission-denied');
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('10 dedicated true does not enable restock', async () => {
  const {base, lojaId} = await seed();
  await denied(
    executeStockCommand(db, intent(lojaId, 'restock', 'g10'), operator),
    'failed-precondition',
    'Stock protocol unavailable or migration incomplete',
  );
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('11 dedicated true does not replay queue', async () => {
  const {base, lojaId} = await seed();
  await base.collection('product_sync_queue').doc('pending').set({status: 'queued'});
  await executeStockCommand(db, reconcile(lojaId, 'g11'), operator);
  assert.equal((await base.collection('product_sync_queue').doc('pending').get()).data().status, 'queued');
  assert.equal((await base.collection('fila_produtos').get()).empty, true);
});

test('12 normal customer cannot self-enable dedicated grant', async () => {
  const {base, lojaId} = await seed({grant: false, operator: false, ownerUid: 'customer'});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g12'), customer), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  await denied(executeStockCommand(db, {
    ...reconcile(lojaId, 'g12b'),
    reconciliationEnabled: true,
  }, customer), 'invalid-argument');
  assert.equal((await base.collection('stock_reconciliation_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_reconciliation_operators').doc('customer').get()).exists, false);
});

test('13 unauthenticated reconcile denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'g13'), null), 'unauthenticated');
  await denied(executeStockCommand(db, reconcile(lojaId, 'g13b'), {}), 'unauthenticated');
});

test('14 unauthorized actor denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'g14'), customer), 'permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
  await denied(executeStockCommand(db, reconcile(lojaId, 'g14b'), owner), 'permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
});

test('15 authorized actor + grant allowed', async () => {
  const {base, lojaId} = await seed();
  const r = await executeStockCommand(db, reconcile(lojaId, 'g15'), operator);
  assert.equal(r.alreadyApplied, false);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('16 malformed qty denied', async () => {
  const {base, lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'g16a', {confirmedPhysicalQty: -1}), operator), 'invalid-argument');
  await denied(executeStockCommand(db, reconcile(lojaId, 'g16b', {confirmedPhysicalQty: 1.5}), operator), 'invalid-argument');
  await denied(executeStockCommand(db, reconcile(lojaId, 'g16c', {confirmedPhysicalQty: '1'}), operator), 'invalid-argument');
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('17 missing countedAt denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, reconcile(lojaId, 'g17', {}, {omitCountedAt: true}), operator), 'invalid-argument');
});

test('18 stale revision denied', async () => {
  const {base, lojaId} = await seed({stockRevision: 4, quantidade: 2});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g18', {confirmedPhysicalQty: 1, expectedRevision: 0}), operator),
    'aborted',
    'RECONCILIATION_STALE_REMOTE_CONFLICT',
  );
  assert.equal((await stockOf(base)).quantidade, 2);
});

test('19 post-count movement denied', async () => {
  const {base, lojaId} = await seed({quantidade: 1, stockRevision: 1, stockUpdatedAt: AFTER_COUNT});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g19', {confirmedPhysicalQty: 4, expectedRevision: 1}), operator),
    'failed-precondition',
    'RECONCILIATION_POST_COUNT_MOVEMENT',
  );
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('20 wrong variation denied', async () => {
  const {base, lojaId} = await seed({stockKind: 'variation', quantidade: 1, variacoes: {'18': {rosa: 1}}});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g20', {confirmedPhysicalQty: 2, size: 'P', color: 'Azul'}), operator),
    'failed-precondition',
    'RECONCILIATION_VARIATION_IDENTITY',
  );
  assert.equal((await stockOf(base)).variacoes['18'].rosa, 1);
});

test('21 wrong product denied', async () => {
  const {base, lojaId} = await seed();
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g21', {productId: 'missing', confirmedPhysicalQty: 1}), operator),
    'failed-precondition',
  );
  assert.equal((await stockOf(base)).quantidade, 0);
});

test('22 wrong store denied', async () => {
  await seed();
  await denied(executeStockCommand(db, reconcile('no-such-store', 'g22'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('23 atomic success', async () => {
  const {base, lojaId} = await seed({quantidade: 0});
  const r = await executeStockCommand(db, reconcile(lojaId, 'g23'), operator);
  assert.equal(r.delta, 1);
  assert.equal((await stockOf(base)).quantidade, 1);
  assert.equal((await base.collection('stock_catalog_operations').doc('g23').get()).exists, true);
});

test('24 failure produces zero stock write', async () => {
  const {base, lojaId} = await seed({quantidade: 5, stockRevision: 2});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g24', {confirmedPhysicalQty: 9, expectedRevision: 0}), operator),
    'aborted',
    'RECONCILIATION_STALE_REMOTE_CONFLICT',
  );
  assert.equal((await stockOf(base)).quantidade, 5);
  assert.equal((await base.collection('stock_catalog_operations').doc('g24').get()).exists, false);
});

test('25 exact cell only', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 3,
    variacoes: {P: {Azul: 1, Vermelho: 2}},
  });
  await executeStockCommand(db, reconcile(lojaId, 'g25', {confirmedPhysicalQty: 9, size: 'P', color: 'Azul'}), operator);
  const s = await stockOf(base);
  assert.equal(s.variacoes.P.Azul, 9);
  assert.equal(s.variacoes.P.Vermelho, 2);
});

test('26 EPT regenerated', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 1,
    variacoes: {'20': {prata: 1}},
    estoquePorTamanho: {'20': 1},
  });
  await executeStockCommand(db, reconcile(lojaId, 'g26', {confirmedPhysicalQty: 4, size: '20', color: 'prata'}), operator);
  const s = await stockOf(base);
  assert.equal(s.estoquePorTamanho['20'], 4);
  assert.equal(s.variacoes['20'].prata, 4);
});

test('27 aggregate regenerated', async () => {
  const {base, lojaId} = await seed({
    stockKind: 'variation',
    quantidade: 2,
    variacoes: {'17': {rosa: 2}},
  });
  await executeStockCommand(db, reconcile(lojaId, 'g27', {confirmedPhysicalQty: 6, size: '17', color: 'rosa'}), operator);
  assert.equal((await stockOf(base)).quantidade, 6);
});

test('28 revision advances once', async () => {
  const {base, lojaId} = await seed({stockRevision: 2, quantidade: 0});
  const r = await executeStockCommand(db, reconcile(lojaId, 'g28', {confirmedPhysicalQty: 1, expectedRevision: 2}), operator);
  assert.equal(r.resultingRevision, 3);
  await executeStockCommand(db, reconcile(lojaId, 'g28', {confirmedPhysicalQty: 1, expectedRevision: 2}), operator);
  assert.equal((await stockOf(base)).stockRevision, 3);
});

test('29 audit once', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  await executeStockCommand(db, reconcile(lojaId, 'g29', {confirmedPhysicalQty: 4}), operator);
  await executeStockCommand(db, reconcile(lojaId, 'g29', {confirmedPhysicalQty: 4}), operator);
  const ops = await base.collection('stock_catalog_operations').get();
  assert.equal(ops.size, 1);
  const op = ops.docs[0].data();
  assert.equal(op.kind, 'reconcile');
  assert.equal(op.actorUid, 'recon-op');
  assert.equal(op.operationType, 'physical_stock_reconciliation');
});

test('30 idempotent duplicate same payload', async () => {
  const {base, lojaId} = await seed();
  const cmd = reconcile(lojaId, 'g30', {confirmedPhysicalQty: 3});
  const first = await executeStockCommand(db, cmd, operator);
  const second = await executeStockCommand(db, cmd, operator);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal((await stockOf(base)).quantidade, 3);
  assert.equal((await base.collection('stock_catalog_operations').get()).size, 1);
});

test('31 conflicting duplicate rejected', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g31', {confirmedPhysicalQty: 3}), operator);
  await denied(executeStockCommand(db, reconcile(lojaId, 'g31', {confirmedPhysicalQty: 9}), operator), 'already-exists');
  assert.equal((await stockOf(base)).quantidade, 3);
});

test('32 no sale write', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g32'), operator);
  assert.equal((await base.collection('estoque_vendas').get()).empty, true);
});

test('33 no finance write', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g33'), operator);
  assert.equal((await base.collection('contas_receber').get()).empty, true);
  assert.equal((await base.collection('caixa_movimentos').get()).empty, true);
  assert.equal((await base.collection('comissoes').get()).empty, true);
});

test('34 sale-delete observability preserved', async () => {
  const {base, lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'owner', permissions: {sale: true, restore: true, adjust: true}},
    quantidade: 4,
  });
  const lines = [];
  const orig = console.info;
  console.info = (...args) => lines.push(args.map(String).join(' '));
  try {
    await denied(
      executeStockCommand(db, intent(lojaId, 'restore', 'g34', {}, {sourceOperationId: 'missing-sale'}), owner),
      'failed-precondition',
    );
  } finally {
    console.info = orig;
  }
  const parsed = lines.map(line => { try { return JSON.parse(line); } catch { return null; } })
    .filter(payload => payload && payload.event === 'stock_restore_precondition');
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].reason, 'applied_sale_required');
  assert.equal('items' in parsed[0], false);
  const unit = sanitizeRestorePreconditionLog({
    lojaId, operationId: 'g34', sourceOperationId: 'missing-sale',
    sourceExists: false, customerName: 'secret',
  });
  assert.equal(unit.reason, 'applied_sale_required');
  assert.equal('customerName' in unit, false);
  assert.equal(typeof emitRestoreAppliedSaleRequiredLog, 'function');
  assert.equal((await stockOf(base)).quantidade, 4);
});

test('35 existing normal sale path unchanged', async () => {
  const {base, lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'owner', permissions: {sale: true, restock: true, adjust: true, restore: true}},
    quantidade: 2,
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'g35'), owner);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('36 existing restock path unchanged', async () => {
  const {base, lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'owner', permissions: {sale: true, restock: true, adjust: true}},
    quantidade: 0,
  });
  await executeStockCommand(db, intent(lojaId, 'restock', 'g36'), owner);
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('37 existing replace path unchanged', async () => {
  const {base, lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'owner', permissions: {sale: true, restock: true, adjust: true, editorial: true, create: true}},
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'g37',
    items: [{productId: 'p', expectedRevision: 0}],
    definition: {quantidade: 8, variacoes: {}},
    editorial: {nome: 'p', publicadoNoCatalogo: true},
  }, owner);
  assert.equal((await stockOf(base)).quantidade, 8);
});

test('38 existing SIMPLE atomic sale unaffected', async () => {
  const {base, lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'owner', permissions: {sale: true}},
    quantidade: 1,
  });
  await executeStockCommand(db, atomicSale(lojaId, 'g38'), owner);
  assert.equal((await stockOf(base)).quantidade, 0);
  assert.equal((await base.collection('estoque_vendas').doc('g38').get()).exists, true);
});

test('39 no global grant fallback', async () => {
  await db.collection('stock_reconciliation_control').doc('state').set({reconciliationEnabled: true});
  await db.collection('lojas').doc('_all').collection('stock_reconciliation_control').doc('state').set({reconciliationEnabled: true});
  const {lojaId} = await seed({grant: false});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g39'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('40 missing configuration fail-closed', async () => {
  const {lojaId} = await seed({grant: false, operator: false});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g40'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('41 false configuration fail-closed', async () => {
  const {lojaId} = await seed({grant: {reconciliationEnabled: false, reference: 'off'}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g41'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('42 cross-store isolation', async () => {
  const a = await seed();
  const b = await seed({operator: false});
  await b.base.collection('stock_reconciliation_operators').doc('other-op').set({enabled: true});
  await denied(executeStockCommand(db, reconcile(b.lojaId, 'g42'), operator), 'permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
  await executeStockCommand(db, reconcile(a.lojaId, 'g42a'), operator);
  assert.equal((await stockOf(b.base)).quantidade, 0);
});

test('43 server timestamp/config handling', async () => {
  const {base, lojaId} = await seed({
    grant: {
      reconciliationEnabled: true,
      reference: 'ts',
      updatedAt: FieldValue.serverTimestamp(),
      actorUid: 'recon-op',
    },
  });
  await executeStockCommand(db, reconcile(lojaId, 'g43'), operator);
  const grant = (await base.collection('stock_reconciliation_control').doc('state').get()).data();
  assert.equal(grant.reconciliationEnabled, true);
  assert.ok(grant.updatedAt);
  assert.equal(typeof grant.updatedAt.toMillis, 'function');
});

test('44 no PII in grant/audit', async () => {
  const {base, lojaId} = await seed({
    grant: {reconciliationEnabled: true, reference: 'ticket-ref', reason: 'authorized-repair-prep'},
  });
  await executeStockCommand(db, reconcile(lojaId, 'g44', {confirmedPhysicalQty: 2}), operator);
  const op = (await base.collection('stock_catalog_operations').doc('g44').get()).data();
  const json = JSON.stringify(op);
  assert.equal(json.includes('Peca Tecnica'), false);
  assert.equal(json.includes('@'), false);
  assert.equal(json.includes('email'), false);
  assert.equal(json.includes('customerName'), false);
  assert.equal(op.actorUid, 'recon-op');
  assert.equal('reason' in op, false);
});

test('45 grant inactive after removal -> reconcile denied', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g45a'), operator);
  await base.collection('stock_reconciliation_control').doc('state').delete();
  await denied(executeStockCommand(db, reconcile(lojaId, 'g45b', {confirmedPhysicalQty: 2, expectedRevision: 1}), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  assert.equal((await stockOf(base)).quantidade, 1);
});

test('46 customer runtime flags unchanged', async () => {
  const {base, lojaId} = await seed({protocol: null});
  await executeStockCommand(db, reconcile(lojaId, 'g46'), operator);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').get()).empty, true);
  const grant = (await base.collection('stock_reconciliation_control').doc('state').get()).data();
  assert.equal(grant.reconciliationEnabled, true);
  assert.equal('stockProtocolActive' in grant, false);
});

test('47 no queue side effect', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g47'), operator);
  assert.equal((await base.collection('product_sync_queue').get()).empty, true);
  assert.equal((await base.collection('fila_produtos').get()).empty, true);
  assert.equal((await base.collection('stock_catalog_outbox').get()).empty, true);
});

test('48 no catalog side effect', async () => {
  const {base, lojaId} = await seed({publicCatalog: true});
  const before = (await base.collection('produtos_publicos').doc('p').get()).data();
  await executeStockCommand(db, reconcile(lojaId, 'g48'), operator);
  const after = (await base.collection('produtos_publicos').doc('p').get()).data();
  assert.deepEqual(after, before);
});

test('49 concurrent reconcile CAS preserved', async () => {
  const {base, lojaId} = await seed({quantidade: 1});
  const results = await Promise.allSettled([
    executeStockCommand(db, reconcile(lojaId, 'g49a', {confirmedPhysicalQty: 4}), operator),
    executeStockCommand(db, reconcile(lojaId, 'g49b', {confirmedPhysicalQty: 7}), operator),
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

test('50 dedicated capability cannot expand operation scope', async () => {
  const {lojaId} = await seed();
  const expected = {
    sale: 'permission-denied',
    restock: 'failed-precondition',
    adjust: 'failed-precondition',
    restore: 'permission-denied',
    editorial: 'permission-denied',
    create: 'permission-denied',
    delete: 'permission-denied',
    undo: 'failed-precondition',
  };
  for (const kind of Object.keys(expected)) {
    const extra = kind === 'restore' ? {sourceOperationId: 'none'} : {};
    const items = ['adjust', 'replace', 'delete', 'undo', 'editorial', 'create'].includes(kind)
      ? [{productId: 'p', expectedRevision: 0, ...(kind === 'adjust' ? {quantity: 1} : {})}]
      : [{productId: 'p', quantity: 1}];
    const cmd = {protocolVersion: 1, lojaId, kind, operationId: `g50-${kind}`, items, ...extra};
    if (kind === 'editorial' || kind === 'create') cmd.editorial = {nome: 'x', publicadoNoCatalogo: true};
    if (kind === 'create') cmd.definition = {quantidade: 1, variacoes: {}};
    await denied(executeStockCommand(db, cmd, operator), expected[kind]);
  }
  assert.match(commandsSrc(), /command\.kind === 'replace' \? 'adjust'/);
  assert.equal(commandsSrc().includes("command.kind === 'replace' || command.kind === 'reconcile'"), false);
});

test('51 string true grant fail-closed', async () => {
  const {lojaId} = await seed({grant: {reconciliationEnabled: 'true'}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g51'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('52 numeric 1 grant fail-closed', async () => {
  const {lojaId} = await seed({grant: {reconciliationEnabled: 1}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g52'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('53 ACTIVE+adjust without dedicated grant denies reconcile', async () => {
  const {lojaId} = await seed({
    protocol: 'active',
    access: {uid: 'recon-op', permissions: {adjust: true, sale: true, replace: true}},
    grant: false,
  });
  await denied(executeStockCommand(db, reconcile(lojaId, 'g53'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('54 reserved server identity denied', async () => {
  const {lojaId} = await seed({operatorUid: SERVER_PAYMENT_AUTH.uid});
  await denied(
    executeStockCommand(db, reconcile(lojaId, 'g54'), {uid: SERVER_PAYMENT_AUTH.uid}),
    'permission-denied',
    'Reserved server identity',
  );
});

test('55 owner/admin membership does not authorize reconcile', async () => {
  const {lojaId} = await seed({
    operator: false,
    ownerUid: 'owner',
    admins: {admin1: true},
    member: {uid: 'owner', role: 'owner'},
  });
  await denied(executeStockCommand(db, reconcile(lojaId, 'g55'), owner), 'permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
});

test('56 operator enabled string fail-closed', async () => {
  const {lojaId} = await seed({operatorDoc: {enabled: 'true'}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g56'), operator), 'permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
});

test('57 grant does not write protocol control', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, reconcile(lojaId, 'g57'), operator);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
});

test('58 rules source has no client write path for dedicated grant', async () => {
  const rules = rulesSrc();
  assert.equal(rules.includes('stock_reconciliation_control'), false);
  assert.equal(rules.includes('stock_reconciliation_operators'), false);
  assert.match(rules, /match \/\{document=\*\*\}/);
  assert.match(accessSrc(), /authorizeDedicatedReconciliation/);
  assert.equal(typeof authorizeDedicatedReconciliation, 'function');
});

test('59 client-controlled trust field rejected', async () => {
  const {lojaId} = await seed({grant: false});
  await denied(executeStockCommand(db, {
    ...reconcile(lojaId, 'g59'),
    stockReconciliationGrant: true,
  }, operator), 'invalid-argument');
});

test('60 missing reconciliationEnabled fail-closed', async () => {
  const {lojaId} = await seed({grant: {enabled: true, reference: 'wrong-field'}});
  await denied(executeStockCommand(db, reconcile(lojaId, 'g60'), operator), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});
