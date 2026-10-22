// Race: approved Mercado Pago webhook × merchant manual confirmation of the same pre_pedido,
// through real Firestore emulator transactions. Every assertion reads stored documents.
// Runs only against the local emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 (project demo-mp-race).
//
// Manual side = port of the app 1.0.147 flow (PrePedidoConfirmacaoEligibilityService →
// SaleIntentService.reserveOrJoin → stockCatalogCommand `sale` as the store owner → intent
// transitions → PrePedidoService.confirmarPrePedido). The stock command module is loaded from
// MP_RACE_MANUAL_STOCK_MODULE (the deployed stockCatalogCommand package) when set.
import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {Firestore, FieldValue} from 'firebase-admin/firestore';
import {processMpWebhook} from '../src/mpWebhookHandler.js';

const enabled = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8189';
const skip = enabled ? false : 'Firestore emulator (127.0.0.1:8189) not running';
const db = enabled ? new Firestore({projectId: 'demo-mp-race'}) : null;
after(() => db?.terminate());

const manualModulePath = process.env.MP_RACE_MANUAL_STOCK_MODULE || '';
const manualStock = enabled
  ? await import(manualModulePath ? pathToFileURL(manualModulePath).href : '../src/stockCatalogCommands.js')
  : null;
const ITERATIONS = Number(process.env.MP_RACE_ITERATIONS || 25);
const runId = Date.now().toString(36);
let seq = 0;

/** Deterministic PRNG so a failing schedule can be replayed. */
function prng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const sleep = ms => (ms > 0 ? new Promise(r => setTimeout(r, ms)) : Promise.resolve());

// ------------------------------------------------------------------ app port (1.0.147)

class SaleIntentConflict extends Error {}

function isGatewayPaid(p) {
  const st = String(p.status ?? 'pendente').toLowerCase().trim();
  const sp = String(p.statusPagamento ?? '').toLowerCase().trim();
  const mp = String(p.mpPaymentStatus ?? '').toLowerCase().trim();
  return st === 'paid' || st === 'pago' || sp === 'aprovado' || sp === 'approved' || mp === 'approved'
    || p.paidAt != null || String(p.paymentId ?? '').trim() !== '';
}

function evaluateEligibility(p) {
  if (!p) return 'documentNotFound';
  const st = String(p.status ?? 'pendente').toLowerCase().trim();
  if (st === 'confirmado' || String(p.vendaId ?? '').trim()) return 'alreadyConfirmed';
  const sp = String(p.statusPagamento ?? '').toLowerCase().trim();
  const pid = String(p.paymentId ?? '').trim();
  if (p.paidAt != null && !pid && /mercado|gateway/i.test(String(p.pagamento ?? ''))) return 'inconsistentPaymentState';
  if ((sp === 'aprovado' || sp === 'approved') && p.paidAt == null && !pid) return 'inconsistentPaymentState';
  if (isGatewayPaid(p)) return 'alreadyPaidByMercadoPago';
  return 'eligible';
}

async function reserveOrJoin({lojaId, saleIntentId, origin, stockEffectHash}) {
  const ref = db.collection('lojas').doc(lojaId).collection('sale_intents').doc(saleIntentId);
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      const operationId = randomUUID();
      tx.set(ref, {
        protocolVersion: 1, saleIntentId, lojaId, origin, operationId, status: 'reserved', stockEffectHash,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      return {operationId, status: 'reserved'};
    }
    const d = snap.data() || {};
    if (d.protocolVersion !== 1 || d.lojaId !== lojaId || d.saleIntentId !== saleIntentId
      || !d.operationId || !d.stockEffectHash || !d.origin || !d.status) {
      throw new SaleIntentConflict('schema');
    }
    if (d.stockEffectHash !== stockEffectHash) throw new SaleIntentConflict('stockEffectHash');
    if (d.origin !== origin) throw new SaleIntentConflict('origin');
    if (d.status === 'critical') throw new SaleIntentConflict('critical');
    if (d.status === 'reverted') {
      tx.update(ref, {status: 'reserved', updatedAt: FieldValue.serverTimestamp()});
      return {operationId: d.operationId, status: 'reserved'};
    }
    return {operationId: d.operationId, status: d.status};
  });
}

const TRANSITIONS = {reserved: ['stock_applied', 'reverted'], stock_applied: ['sale_persisted', 'reverted'], sale_persisted: ['completed']};
async function transition(lojaId, saleIntentId, operationId, target) {
  const ref = db.collection('lojas').doc(lojaId).collection('sale_intents').doc(saleIntentId);
  await db.runTransaction(async tx => {
    const d = (await tx.get(ref)).data();
    if (d.operationId !== operationId) throw new SaleIntentConflict('operationId');
    if (!(TRANSITIONS[d.status] || []).includes(target)) throw new SaleIntentConflict(`${d.status}->${target}`);
    tx.update(ref, {status: target, updatedAt: FieldValue.serverTimestamp(),
      ...(target === 'completed' ? {completedAt: FieldValue.serverTimestamp()} : {})});
  });
}

/** pre_pedidos_screen "Confirmar pedido" → registrarVendaMulti(saleIntentId pre_pedido:{id}) → confirmarPrePedido. */
async function manualConfirm(lojaId, orderId, owner, rnd, {scale = 12, afterEligibility} = {}) {
  await sleep(rnd() * scale);
  const orderRef = db.collection('lojas').doc(lojaId).collection('pre_pedidos').doc(orderId);
  const snap = await orderRef.get();
  const elig = evaluateEligibility(snap.exists ? {...snap.data(), id: snap.id} : null);
  if (elig !== 'eligible') return {sold: false, reason: elig};
  await afterEligibility?.();
  await sleep(rnd() * scale);
  const saleIntentId = `pre_pedido:${orderId}`;
  let reservation;
  try {
    reservation = await reserveOrJoin({lojaId, saleIntentId, origin: 'pre_pedido', stockEffectHash: 'p-simple|1'});
  } catch (e) {
    if (e instanceof SaleIntentConflict) return {sold: false, reason: `intent_conflict_${e.message}`};
    throw e;
  }
  if (reservation.status !== 'reserved') return {sold: false, reason: `intent_${reservation.status}`};
  await sleep(rnd() * scale);
  const opId = reservation.operationId;
  await manualStock.executeStockCommand(db, {
    protocolVersion: 1, lojaId, operationId: opId, kind: 'sale', items: [{productId: 'p-simple', quantity: 1}],
  }, {uid: owner});
  await transition(lojaId, saleIntentId, opId, 'stock_applied');
  await db.collection('lojas').doc(lojaId).collection('vendas').doc(opId).set({origem: 'pre_pedido', total: 100});
  await transition(lojaId, saleIntentId, opId, 'sale_persisted');
  await orderRef.update({status: 'confirmado', vendaId: opId, dataAtualizacao: FieldValue.serverTimestamp()});
  await transition(lojaId, saleIntentId, opId, 'completed');
  return {sold: true, opId};
}

// ------------------------------------------------------------------ fixtures

async function seedStore(control) {
  const lojaId = `race_${runId}_${++seq}`;
  const orderId = `ord_${seq}`;
  const paymentId = String(1_800_000_000 + seq * 7 + Math.floor(Math.random() * 5));
  const owner = `owner_${seq}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid: owner, lojaId, nome: 'Loja corrida', owner: {email: 'dona@example.test'}});
  if (control === 'ACTIVE') {
    batch.set(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    batch.set(base.collection('stock_catalog_access').doc(owner), {enabled: true, permissions: {sale: true}});
    batch.set(base.collection('draft_produtos').doc('p-simple'), {nome: 'Brinco', publicadoNoCatalogo: true});
    batch.set(base.collection('stock_catalog_dependencies').doc('p-simple'), {comboIds: []});
  }
  batch.set(base.collection('estoque_produtos').doc('p-simple'),
    {nome: 'Brinco', quantidade: 5, stockKind: 'simple', stockRevision: 3, variacoes: {}});
  batch.set(base.collection('pre_pedidos').doc(orderId), {
    lojaId, tipo: 'catalogo_web', status: 'pendente', statusPagamento: 'pendente', pagamento: 'PIX',
    total: 100, subtotal: 90, frete: {valor: 10}, cliente: {nome: 'Cliente', email: 'cliente@example.test'},
    itens: [{productId: 'p-simple', id: 'p-simple', nome: 'Brinco', quantidade: 1, precoUnitario: 90, tamanho: '', cor: ''}],
    dataCriacao: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {lojaId, orderId, paymentId, owner, base};
}

function webhookDeps(fx, cutoverMs) {
  const payment = {
    id: Number(fx.paymentId), status: 'approved', status_detail: 'accredited', payment_method_id: 'pix',
    payment_type_id: 'bank_transfer', transaction_amount: 100, currency_id: 'BRL', external_reference: fx.orderId,
    metadata: {loja_id: fx.lojaId}, date_approved: new Date().toISOString(),
  };
  const mails = [];
  return {
    mails,
    deps: {
      db,
      findPayment: async () => ({lojaId: fx.lojaId, payment: structuredClone(payment)}),
      fetchPaymentForStore: async lojaId => (lojaId === fx.lojaId ? structuredClone(payment) : null),
      smtpUser: 'noreply@example.test',
      sendMail: async m => { mails.push(m); },
      sendWhatsApp: async () => ({ok: true}),
      promo: {},
      now: () => Date.now(),
      cutoverMs,
    },
  };
}

async function countState(fx) {
  const [webhookSales, manualSales, ops, stock, order, marker] = await Promise.all([
    fx.base.collection('estoque_vendas').get(),
    fx.base.collection('vendas').get(),
    fx.base.collection('stock_catalog_operations').get(),
    fx.base.collection('estoque_produtos').doc('p-simple').get(),
    fx.base.collection('pre_pedidos').doc(fx.orderId).get(),
    db.collection('_mp_webhook_processed').doc(fx.paymentId).get(),
  ]);
  const saleOps = ops.docs.filter(d => d.data().kind === 'sale');
  return {
    sales: webhookSales.size + manualSales.size,
    webhookSales: webhookSales.size,
    manualSales: manualSales.size,
    stockDebits: saleOps.length,
    quantity: stock.data().quantidade,
    stockRevision: stock.data().stockRevision,
    order: order.data(),
    marker: marker.exists ? marker.data() : null,
  };
}

const MANUAL_DELAY_SCALES_MS = [0, 15, 40, 80, 150];

async function raceOnce(control, seed) {
  const rnd = prng(seed);
  const fx = await seedStore(control);
  const cutoverMs = Date.now() - 60_000;
  const {deps, mails} = webhookDeps(fx, cutoverMs);
  const scale = MANUAL_DELAY_SCALES_MS[seed % MANUAL_DELAY_SCALES_MS.length];
  const webhook = (async () => { await sleep(rnd() * 10); return processMpWebhook(fx.paymentId, {}, deps); })();
  const manual = manualConfirm(fx.lojaId, fx.orderId, fx.owner, rnd, {scale});
  const [w, m] = await Promise.allSettled([webhook, manual]);
  assert.equal(w.status, 'fulfilled', `webhook rejected: ${w.reason?.stack || w.reason}`);
  assert.equal(m.status, 'fulfilled', `manual rejected: ${m.reason?.stack || m.reason}`);
  const s = await countState(fx);
  const ctx = `control=${control} seed=${seed} manual=${JSON.stringify(m.value)} marker=${s.marker?.status}/${s.marker?.reason}`;
  assert.equal(s.sales, 1, `SALE_COUNT ${ctx}`);
  assert.equal(s.stockDebits, 1, `STOCK_DEBIT_COUNT ${ctx}`);
  assert.equal(s.quantity, 4, `quantity ${ctx}`);
  assert.equal(s.stockRevision, 4, `stockRevision ${ctx}`);
  if (m.value.sold) {
    assert.equal(s.webhookSales, 0, ctx);
    assert.equal(s.order.status, 'confirmado', ctx);
    assert.equal(s.order.vendaId, m.value.opId, ctx);
    assert.equal(s.order.paidAt, undefined, ctx);
    assert.equal(s.marker?.status, 'already_business_confirmed', ctx);
    assert.equal(mails.length, 0, `PAID_EMAIL ${ctx}`);
  } else {
    assert.equal(s.manualSales, 0, ctx);
    assert.equal(s.order.status, 'paid', ctx);
    assert.equal(s.order.vendaId, `mp_payment_sale_${fx.paymentId}`, ctx);
    assert.equal(s.marker?.status, 'applied', ctx);
  }
  return m.value.sold ? 'manual' : 'webhook';
}

for (const control of ['NO_CONTROL', 'ACTIVE']) {
  test(`corrida webhook × confirmação manual (${control}): ${ITERATIONS} agendamentos, sempre 1 venda e 1 baixa`, {skip}, async () => {
    const winners = {manual: 0, webhook: 0};
    for (let i = 0; i < ITERATIONS; i++) winners[await raceOnce(control, 1000 + i)]++;
    console.log(`[race] control=${control} module=${manualModulePath || 'candidate'} winners=${JSON.stringify(winners)}`);
    assert.ok(winners.manual > 0 && winners.webhook > 0, `scheduling variation not exercised: ${JSON.stringify(winners)}`);
  });
}

test('ordem fixa: manual completo antes do webhook → webhook 0 venda/0 baixa/0 e-mail', {skip}, async () => {
  const fx = await seedStore('NO_CONTROL');
  const r = await manualConfirm(fx.lojaId, fx.orderId, fx.owner, () => 0);
  assert.equal(r.sold, true);
  const {deps, mails} = webhookDeps(fx, Date.now() - 60_000);
  assert.equal(await processMpWebhook(fx.paymentId, {}, deps), true);
  const s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity, mails.length], [1, 1, 4, 0]);
  assert.equal(s.marker.status, 'already_business_confirmed');
});

test('ordem fixa: webhook antes do manual → app bloqueado (elegibilidade) e intenção em conflito', {skip}, async () => {
  const fx = await seedStore('NO_CONTROL');
  const {deps} = webhookDeps(fx, Date.now() - 60_000);
  await processMpWebhook(fx.paymentId, {}, deps);
  const r = await manualConfirm(fx.lojaId, fx.orderId, fx.owner, () => 0);
  assert.deepEqual(r, {sold: false, reason: 'alreadyConfirmed'});
  await assert.rejects(
    reserveOrJoin({lojaId: fx.lojaId, saleIntentId: `pre_pedido:${fx.orderId}`, origin: 'pre_pedido', stockEffectHash: 'p-simple|1'}),
    e => e instanceof SaleIntentConflict,
  );
  const s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity], [1, 1, 4]);
});

test('elegibilidade desatualizada: app lê o pedido antes do webhook e reserva depois → conflito, 0 baixa manual', {skip}, async () => {
  for (const control of ['NO_CONTROL', 'ACTIVE']) {
    const fx = await seedStore(control);
    const {deps} = webhookDeps(fx, Date.now() - 60_000);
    const r = await manualConfirm(fx.lojaId, fx.orderId, fx.owner, () => 0, {
      afterEligibility: () => processMpWebhook(fx.paymentId, {}, deps),
    });
    assert.deepEqual(r, {sold: false, reason: 'intent_conflict_stockEffectHash'});
    const s = await countState(fx);
    assert.deepEqual([s.sales, s.webhookSales, s.manualSales, s.stockDebits, s.quantity], [1, 1, 0, 1, 4]);
    assert.equal(s.order.status, 'paid');
  }
});

test('manual reservou e travou (reserved) → webhook não vende; manual retoma → 1 venda', {skip}, async () => {
  const fx = await seedStore('NO_CONTROL');
  const reservation = await reserveOrJoin({lojaId: fx.lojaId, saleIntentId: `pre_pedido:${fx.orderId}`,
    origin: 'pre_pedido', stockEffectHash: 'p-simple|1'});
  const {deps, mails} = webhookDeps(fx, Date.now() - 60_000);
  await processMpWebhook(fx.paymentId, {}, deps);
  let s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity, mails.length], [0, 0, 5, 0]);
  assert.equal(s.marker.reason, 'manual_sale_intent_reserved');
  const r = await manualConfirm(fx.lojaId, fx.orderId, fx.owner, () => 0);
  assert.equal(r.sold, true);
  assert.equal(r.opId, reservation.operationId);
  s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity], [1, 1, 4]);
});

test('4 webhooks concorrentes no emulador: 1 venda, 1 baixa, 1 e-mail ao lojista', {skip}, async () => {
  const fx = await seedStore('ACTIVE');
  const {deps, mails} = webhookDeps(fx, Date.now() - 60_000);
  await Promise.all([0, 1, 2, 3].map(() => processMpWebhook(fx.paymentId, {}, deps)));
  const s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity, s.stockRevision], [1, 1, 4, 4]);
  assert.equal(mails.filter(m => String(m.from).startsWith('"MasterPalm"')).length, 1);
});

test('pedido histórico (criado antes do corte) no emulador: createTime do Firestore bloqueia', {skip}, async () => {
  const fx = await seedStore('NO_CONTROL');
  const before = (await fx.base.collection('pre_pedidos').doc(fx.orderId).get()).data();
  const {deps, mails} = webhookDeps(fx, Date.now() + 60_000);
  await processMpWebhook(fx.paymentId, {}, {...deps, findPayment: async () => ({lojaId: fx.lojaId, payment: {
    ...(await deps.fetchPaymentForStore(fx.lojaId)), date_approved: new Date(Date.now() + 120_000).toISOString()}})});
  const s = await countState(fx);
  assert.deepEqual([s.sales, s.stockDebits, s.quantity, mails.length], [0, 0, 5, 0]);
  assert.equal(s.marker, null);
  assert.deepEqual(s.order, before);
});
