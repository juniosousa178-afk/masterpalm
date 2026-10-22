/**
 * mpWebhook catálogo → venda canônica → estoque → e-mail.
 * Firestore em memória transacional + API Mercado Pago simulada. Sem emulador, sem rede, sem produção.
 *
 * node --test test/mpWebhookCanonicalSale.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Timestamp} from 'firebase-admin/firestore';
import {processMpWebhook} from '../src/mpWebhookHandler.js';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {SERVER_PAYMENT_AUTH} from '../src/stockCatalogAccess.js';
import {
  MP_CATALOG_AUTO_SALE_CUTOVER_ENV,
  mpPaymentSaleOperationId,
  parseAutoSaleCutoverUtc,
} from '../src/mpCatalogPaymentSale.js';
import {createMpWebhookTestDb} from './_mpWebhookTestDb.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const LOJA = 'loja_mp_a';
const OTHER = 'loja_mp_b';
const ORDER = 'ord_catalogo_1';
const PID = '1330000001';
const OP = mpPaymentSaleOperationId(PID);
const CUTOVER = Date.parse('2026-10-23T09:00:00.000Z');
const ORDER_CREATED = Date.parse('2026-10-23T10:00:00.000Z');
const NOW = Date.parse('2026-10-23T12:00:00.000Z');
const APPROVED_AT = '2026-10-23T08:58:00.000-03:00';

const PRODUCTS = {
  'p-simple': {nome: 'Brinco', quantidade: 5, stockKind: 'simple', stockRevision: 3, variacoes: {}},
  'p-size': {nome: 'Anel', stockKind: 'variation', stockRevision: 1, quantidade: 3,
    variacoes: {'15': {'sem-cor': 2}, '22': {'sem-cor': 1}}, estoquePorTamanho: {'15': 2, '22': 1}, tamanhos: ['15', '22']},
  'p-color': {nome: 'Pulseira', stockKind: 'variation', stockRevision: 1, quantidade: 3,
    variacoes: {'sem-tamanho': {Azul: 2, Rosa: 1}}},
  'p-grade': {nome: 'Blusa', stockKind: 'variation', stockRevision: 1, quantidade: 6,
    variacoes: {P: {Azul: 2, Vermelho: 3}, M: {Azul: 1}}},
  'p-extra': {nome: 'Colar', stockKind: 'variation', stockRevision: 1, quantidade: 3,
    variacoes: {P: {Azul: {A: 2, B: 1}}}},
};

function item(productId, extra = {}) {
  return {productId, id: productId, nome: PRODUCTS[productId]?.nome ?? productId, quantidade: 1, precoUnitario: 90,
    tamanho: '', cor: '', ...extra};
}

function mpPayment({id = PID, status = 'approved', method = 'pix', type = 'bank_transfer', amount = 100,
  ext = ORDER, loja = LOJA, approvedAt = APPROVED_AT, metadata} = {}) {
  return {
    id: Number(id), status, status_detail: status === 'approved' ? 'accredited' : 'pending_waiting_transfer',
    payment_method_id: method, payment_type_id: type, transaction_amount: amount, currency_id: 'BRL',
    external_reference: ext, metadata: metadata ?? {loja_id: loja},
    date_approved: status === 'approved' ? approvedAt : null,
  };
}

function harness({
  control = 'NO_CONTROL',
  products = ['p-simple'],
  order = {},
  orderCollection = 'pre_pedidos',
  loja = {},
  payments = {[PID]: {lojaId: LOJA, payment: mpPayment()}},
  storeVisibility = null,
  smtpFails = false,
  noOrder = false,
  orderCreateTimeMs = ORDER_CREATED,
} = {}) {
  const db = createMpWebhookTestDb();
  for (const lojaId of [LOJA, OTHER]) {
    const base = db.collection('lojas').doc(lojaId);
    db.seed(base, {ownerUid: `owner-${lojaId}`, nome: `Loja ${lojaId}`, owner: {email: 'Dona@Example.test'},
      ...(lojaId === LOJA ? loja : {})});
    if (control === 'ACTIVE') {
      db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    } else if (control === 'INVALID') {
      db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'maintenance'});
    }
    for (const id of Object.keys(PRODUCTS)) {
      db.seed(base.collection('estoque_produtos').doc(id), structuredClone(PRODUCTS[id]));
      if (control === 'ACTIVE') {
        db.seed(base.collection('draft_produtos').doc(id), {nome: PRODUCTS[id].nome, publicadoNoCatalogo: true});
        db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
      }
    }
  }
  const orderRef = db.collection('lojas').doc(LOJA).collection(orderCollection).doc(ORDER);
  if (!noOrder) {
    db.seed(orderRef, {
      lojaId: LOJA, tipo: 'catalogo_web', status: 'pendente', statusPagamento: 'pendente', origemCheckout: 'mercadopago',
      total: 100, subtotal: 90, frete: {nome: 'Entrega', valor: 10, gratis: false}, pagamento: 'PIX',
      cliente: {nome: 'Cliente Teste', email: 'cliente@example.test', telefone: '(11) 99999-0000'},
      itens: products.map(p => (typeof p === 'string' ? item(p) : p)),
      dataCriacao: Timestamp.fromMillis(orderCreateTimeMs),
      ...order,
    }, {createTimeMs: orderCreateTimeMs});
  }
  const mails = [];
  const whatsapps = [];
  const promo = [];
  let smtpBroken = smtpFails;
  const deps = {
    db,
    findPayment: async pid => payments[pid] ? structuredClone(payments[pid]) : null,
    fetchPaymentForStore: async (lojaId, pid) => {
      const entry = payments[pid];
      if (!entry) return null;
      const visible = storeVisibility ? storeVisibility[lojaId] : entry.lojaId === lojaId;
      return visible ? structuredClone(entry.payment) : null;
    },
    smtpUser: 'noreply@example.test',
    sendMail: async msg => {
      if (smtpBroken) throw Object.assign(new Error(`Invalid login for ${'noreply@example.test'}`), {code: 'EAUTH'});
      mails.push(msg);
    },
    sendWhatsApp: async msg => { whatsapps.push(msg); return {ok: true}; },
    promo: {
      registrar: async (_db, a) => promo.push(['registrar', a.paymentId]),
      registrarRecovery: async (_db, a) => promo.push(['registrarRecovery', a.paymentId]),
      premio: async (_db, a) => promo.push(['premio', a.paymentId]),
      premioRecovery: async (_db, a) => promo.push(['premioRecovery', a.paymentId]),
    },
    now: () => NOW,
    cutoverMs: CUTOVER,
  };
  const base = db.collection('lojas').doc(LOJA);
  const h = {
    db, deps, mails, whatsapps, promo, orderRef, base,
    run: (pid = PID, extraDeps = {}) => processMpWebhook(pid, {}, {...deps, ...extraDeps}),
    setSmtpBroken: v => { smtpBroken = v; },
    stock: id => db.getData(base.collection('estoque_produtos').doc(id)),
    order: () => db.getData(orderRef),
    marker: (pid = PID) => db.getData(db.collection('_mp_webhook_processed').doc(pid)),
    sales: (lojaId = LOJA) => db.paths(`lojas/${lojaId}/estoque_vendas/`),
    ops: (lojaId = LOJA) => db.paths(`lojas/${lojaId}/stock_catalog_operations/`),
    notifications: () => db.paths(`lojas/${LOJA}/notificacoes/`),
    merchantMails: () => mails.filter(m => m.from.startsWith('"MasterPalm"')),
    customerMails: () => mails.filter(m => !m.from.startsWith('"MasterPalm"')),
    intent: () => db.getData(base.collection('sale_intents').doc(`pre_pedido:${ORDER}`)),
    reject: (pid = PID) => db.getData(db.collection('_mp_webhook_validation_rejects').doc(pid)),
  };
  return h;
}

function assertNoEffects(h, {lojaId = LOJA} = {}) {
  assert.deepEqual(h.sales(lojaId), []);
  assert.deepEqual(h.ops(lojaId), []);
  assert.equal(h.mails.length, 0);
  assert.equal(h.whatsapps.length, 0);
  assert.deepEqual(h.notifications(), []);
  assert.equal(h.promo.length, 0);
  for (const [id, data] of Object.entries(PRODUCTS)) {
    assert.deepEqual(h.db.getData(h.db.collection('lojas').doc(lojaId).collection('estoque_produtos').doc(id)), data);
  }
}

/** Escritas em produtos/estoque_produtos só podem ocorrer no commit que cria a operação canônica. */
function assertOnlyCanonicalStockWrites(h) {
  let legacy = 0;
  for (const c of h.db.commits) {
    const touchesStock = c.ops.some(o => /\/(produtos|estoque_produtos)\//.test(o.path));
    if (!touchesStock) continue;
    const canonical = c.ops.some(o => o.type === 'create' && /\/stock_catalog_operations\/mp_payment_sale_/.test(o.path));
    if (!canonical) legacy++;
  }
  assert.equal(legacy, 0, 'LEGACY_DIRECT_STOCK_WRITE_COUNT');
}

// ---------------------------------------------------------------- aprovados

test('PIX aprovado: 1 venda canônica, 1 baixa, pedido pago, marcador, e-mails, sem escrita legada', async () => {
  const h = harness();
  assert.equal(await h.run(), true);

  assert.deepEqual(h.sales(), [`lojas/${LOJA}/estoque_vendas/${OP}`]);
  const sale = h.db.getData(h.base.collection('estoque_vendas').doc(OP));
  assert.equal(sale.origemVenda, 'pdv_atomic');
  assert.equal(sale.stockOperationId, OP);
  assert.equal(sale.actorUid, SERVER_PAYMENT_AUTH.uid);
  assert.equal(sale.total, 100);
  assert.equal(sale.pagamentoPix, 100);
  assert.equal(sale.pagamentoCartao, 0);
  assert.equal(sale.frete, 10);
  assert.equal(sale.formasPagamento, 'Mercado Pago (PIX)');
  assert.equal(sale.itens.length, 1);

  const op = h.db.getData(h.base.collection('stock_catalog_operations').doc(OP));
  assert.equal(op.kind, 'sale');
  assert.equal(op.atomicPdvSale, true);
  assert.equal(op.actorUid, SERVER_PAYMENT_AUTH.uid);
  assert.equal(op.status, 'applied');
  assert.deepEqual(op.catalogCountDeltas, {'p-simple': 1});

  const stock = h.stock('p-simple');
  assert.equal(stock.quantidade, 4);
  assert.equal(stock.stockRevision, 4, 'STOCK_REVISION_PROTOCOL_PRESERVED');
  assert.equal(stock.stockOperationId, OP, 'STOCK_OPERATION_AUDIT_PRESENT');

  const order = h.order();
  assert.equal(order.status, 'paid');
  assert.equal(order.statusPagamento, 'aprovado');
  assert.equal(order.paymentId, PID);
  assert.equal(order.vendaId, OP);
  assert.equal(order.saleId, OP);
  assert.ok(order.paidAt);

  const intent = h.intent();
  assert.equal(intent.status, 'completed');
  assert.equal(intent.operationId, OP);
  assert.equal(intent.origin, 'mp_webhook');

  const marker = h.marker();
  assert.equal(marker.status, 'applied');
  assert.equal(marker.protocol, 'canonical_sale_v1');
  assert.equal(marker.saleOperationId, OP);
  assert.ok(marker.merchantPaidEmailSentAt);
  assert.ok(marker.customerPaidEmailSentAt);
  assert.ok(marker.whatsappSentAt);
  assert.ok(marker.adminNotificationSentAt);
  assert.equal(marker.postEffectsClaimedAtMs, null);

  assert.equal(h.merchantMails().length, 1);
  assert.equal(h.merchantMails()[0].to, 'dona@example.test');
  assert.match(h.merchantMails()[0].subject, /^Pedido pago — /);
  assert.equal(h.customerMails().length, 1);
  assert.equal(h.whatsapps.length, 1);
  assert.deepEqual(h.notifications(), [`lojas/${LOJA}/notificacoes/mp_paid_${PID}`]);
  assert.deepEqual(h.promo, [['registrar', PID], ['premio', PID]]);
  assertOnlyCanonicalStockWrites(h);
});

test('cartão aprovado: pagamentoCartao e forma de pagamento corretos', async () => {
  const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({method: 'master', type: 'credit_card'})}}});
  await h.run();
  const sale = h.db.getData(h.base.collection('estoque_vendas').doc(OP));
  assert.equal(sale.pagamentoCartao, 100);
  assert.equal(sale.pagamentoPix, 0);
  assert.equal(sale.formasPagamento, 'Mercado Pago (Cartão)');
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.merchantMails().length, 1);
});

test('loja ACTIVE: venda canônica projeta catálogo e conta vendasCatalogoTotal', async () => {
  const h = harness({control: 'ACTIVE'});
  await h.run();
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.stock('p-simple').vendasCatalogoTotal, 1);
  const live = h.db.getData(h.base.collection('produtos').doc('p-simple'));
  assert.equal(live.quantidade, 4);
  assert.equal(h.sales().length, 1);
  assertOnlyCanonicalStockWrites(h);
});

// ---------------------------------------------------------------- não aprovados / autoridade

for (const status of ['pending', 'in_process', 'rejected', 'cancelled', 'refunded']) {
  test(`status ${status}: 0 venda, 0 estoque, 0 e-mail, 0 marcador`, async () => {
    const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({status})}}});
    assert.equal(await h.run(), true);
    assertNoEffects(h);
    assert.equal(h.marker(), undefined);
    assert.equal(h.order().status, 'pendente');
    assert.equal(h.order().paidAt, undefined);
  });
}

test('pendente e depois aprovado: só a notificação aprovada aplica (1 venda)', async () => {
  const payments = {[PID]: {lojaId: LOJA, payment: mpPayment({status: 'pending'})}};
  const h = harness({payments});
  await h.run();
  assertNoEffects(h);
  payments[PID] = {lojaId: LOJA, payment: mpPayment()};
  await h.run();
  assert.equal(h.sales().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);
});

test('autoridade: só a API MP decide — handler recebe apenas o id; API pending → 0 efeitos', async () => {
  const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({status: 'pending'})}}});
  assert.equal(processMpWebhook.length >= 1, true);
  await h.run();
  assertNoEffects(h);
  const handlerSrc = readFileSync(join(HERE, '../src/mpWebhookHandler.js'), 'utf8');
  assert.doesNotMatch(handlerSrc, /req\.body|req\.query/);
});

test('URL de retorno (?status=approved) não é autoridade: tela de resultado não escreve no Firestore', () => {
  const dart = readFileSync(join(HERE, '../../lib/screens/pagamento_resultado_screen.dart'), 'utf8');
  assert.doesNotMatch(dart, /FirebaseFirestore|\.collection\(|\.set\(|\.update\(|httpsCallable|mpWebhook/);
});

// ---------------------------------------------------------------- corte (cutover) — bloqueador de release

/** Histórico: 0 venda/estoque/e-mail, nenhum marcador, pedido byte-a-byte inalterado. */
async function assertHistoricalUntouched(h, reason) {
  const before = h.order();
  assert.equal(await h.run(), true);
  assertNoEffects(h);
  assert.equal(h.marker(), undefined);
  assert.equal(h.intent(), undefined);
  assert.deepEqual(h.order(), before);
  if (reason) assert.equal(h.reject().validationReason, reason);
}

test('pedido criado antes do corte (2026-08-15) + webhook/aprovação após o deploy: AUTO_SALE=0', async () => {
  const old = Date.parse('2026-08-15T14:00:00.000Z');
  const h = harness({orderCreateTimeMs: old});
  await assertHistoricalUntouched(h, 'order_created_before_cutover');
  for (let i = 0; i < 3; i++) await h.run();
  assertNoEffects(h);
  assert.equal(h.marker(), undefined);
});

test('pedido e aprovação após o corte: elegível (POST_CUTOVER_ORDER_POST_CUTOVER_APPROVAL_ELIGIBLE)', async () => {
  const h = harness();
  await h.run();
  assert.equal(h.sales().length, 1);
  assert.equal(h.order().status, 'paid');
});

test('aprovação MP antes do corte (pedido novo): 0 efeitos', async () => {
  const before = new Date(CUTOVER - 60_000).toISOString();
  const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({approvedAt: before})}}});
  await assertHistoricalUntouched(h, 'payment_approved_before_cutover');
});

for (const [name, approvedAt, reason] of [
  ['date_approved ausente', null, 'payment_approval_time_invalid'],
  ['date_approved sem fuso (ambíguo)', '2026-10-23T11:58:00.000', 'payment_approval_time_invalid'],
  ['date_approved inválido', 'ontem', 'payment_approval_time_invalid'],
]) {
  test(`aprovação: ${name} → fail closed`, async () => {
    const payment = {...mpPayment(), date_approved: approvedAt};
    const h = harness({payments: {[PID]: {lojaId: LOJA, payment}}});
    await assertHistoricalUntouched(h, reason);
  });
}

for (const [name, order, createTimeMs, reason] of [
  ['dataCriacao antes do corte com createTime novo', {dataCriacao: Timestamp.fromMillis(CUTOVER - 1)}, ORDER_CREATED, 'order_created_before_cutover'],
  ['createdAt antes do corte', {createdAt: Timestamp.fromMillis(CUTOVER - 1)}, ORDER_CREATED, 'order_created_before_cutover'],
  ['createTime antes do corte com dataCriacao nova', {}, CUTOVER - 1, 'order_created_before_cutover'],
  ['dataCriacao como string (inválido)', {dataCriacao: '2026-10-23T10:00:00Z'}, ORDER_CREATED, 'order_creation_time_invalid'],
  ['sem dataCriacao/createdAt', {dataCriacao: null}, ORDER_CREATED, 'order_creation_time_missing'],
]) {
  test(`criação do pedido: ${name} → fail closed`, async () => {
    const h = harness({order, orderCreateTimeMs: createTimeMs});
    await assertHistoricalUntouched(h, reason);
  });
}

test('corte não configurado/inválido: nenhuma venda automática', async () => {
  for (const cutoverMs of [null, undefined, NaN]) {
    const h = harness();
    await h.run(PID, {cutoverMs});
    assertNoEffects(h);
    assert.equal(h.marker(), undefined);
    assert.equal(h.order().status, 'pendente');
  }
});

test('corte lido do ambiente (MP_CATALOG_AUTO_SALE_CUTOVER_UTC); webhook recebido não é autoridade', async () => {
  const prev = process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV];
  try {
    const noCut = harness();
    const {cutoverMs: _a, ...depsNoCut} = noCut.deps;
    delete process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV];
    await processMpWebhook(PID, {}, depsNoCut);
    assertNoEffects(noCut);

    const h = harness();
    const {cutoverMs: _b, ...deps} = h.deps;
    process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV] = new Date(CUTOVER).toISOString();
    await processMpWebhook(PID, {}, {...deps, now: () => CUTOVER + 365 * 86400000});
    assert.equal(h.sales().length, 1);

    const late = harness({orderCreateTimeMs: CUTOVER - 1});
    const {cutoverMs: _c, ...depsLate} = late.deps;
    await processMpWebhook(PID, {}, {...depsLate, now: () => CUTOVER + 3600000});
    assertNoEffects(late);
  } finally {
    if (prev === undefined) delete process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV];
    else process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV] = prev;
  }
});

test('parseAutoSaleCutoverUtc: só ISO-8601 UTC com Z', () => {
  assert.equal(parseAutoSaleCutoverUtc('2026-10-22T16:30:00Z'), Date.parse('2026-10-22T16:30:00Z'));
  assert.equal(parseAutoSaleCutoverUtc('2026-10-22T16:30:00.123Z'), Date.parse('2026-10-22T16:30:00.123Z'));
  for (const bad of ['', null, undefined, '2026-10-22', '2026-10-22T16:30:00', '2026-10-22T16:30:00-03:00', 'agora', '1792700000000']) {
    assert.equal(parseAutoSaleCutoverUtc(bad), null, String(bad));
  }
});

// ---------------------------------------------------------------- já confirmado / bloqueador de release

test('pedido confirmado manualmente (status confirmado, sem paidAt, venda manual existente): 0 efeitos', async () => {
  const h = harness({order: {status: 'confirmado', vendaId: '1712'}});
  h.db.seed(h.base.collection('estoque_vendas').doc('manual-sale-uuid'), {total: 100, origemVenda: 'pdv_atomic'});
  h.db.seed(h.base.collection('sale_intents').doc(`pre_pedido:${ORDER}`), {
    protocolVersion: 1, saleIntentId: `pre_pedido:${ORDER}`, lojaId: LOJA, origin: 'pre_pedido',
    operationId: 'manual-sale-uuid', status: 'completed', stockEffectHash: 'h'});
  const beforeOrder = h.order();
  assert.equal(await h.run(), true);
  assert.deepEqual(h.sales(), [`lojas/${LOJA}/estoque_vendas/manual-sale-uuid`]);
  assert.deepEqual(h.ops(), []);
  assert.equal(h.mails.length, 0);
  assert.equal(h.whatsapps.length, 0);
  assert.deepEqual(h.notifications(), []);
  assert.equal(h.stock('p-simple').quantidade, 5);
  assert.deepEqual(h.order(), beforeOrder);
  const marker = h.marker();
  assert.equal(marker.status, 'already_business_confirmed');
  assert.equal(marker.merchantPaidEmailSentAt, undefined);
  // reentrega: continua 0
  await h.run();
  assert.equal(h.mails.length, 0);
  assert.deepEqual(h.ops(), []);
});

for (const [name, order] of [
  ['vendaId existente', {vendaId: 'v-1'}],
  ['saleId existente', {saleId: 'v-1'}],
  ['paidAt existente', {paidAt: new Date('2026-10-23T10:00:00Z')}],
  ['paymentId de outro pagamento', {paymentId: '999'}],
  ['status em_preparacao', {status: 'em_preparacao'}],
  ['statusPagamento aprovado', {statusPagamento: 'aprovado'}],
]) {
  test(`já confirmado (${name}): 0 venda/estoque/e-mail`, async () => {
    const h = harness({order});
    await h.run();
    assertNoEffects(h);
    assert.equal(h.marker().status, 'already_business_confirmed');
  });
}

test('intenção de venda manual em curso (reserved): 0 efeitos', async () => {
  const h = harness();
  h.db.seed(h.base.collection('sale_intents').doc(`pre_pedido:${ORDER}`), {
    protocolVersion: 1, saleIntentId: `pre_pedido:${ORDER}`, lojaId: LOJA, origin: 'pre_pedido',
    operationId: 'x', status: 'reserved', stockEffectHash: 'h'});
  await h.run();
  assertNoEffects(h);
  assert.equal(h.marker().reason, 'manual_sale_intent_reserved');
});

test('intenção manual revertida não bloqueia; webhook reserva a intenção para o app falhar por conflito', async () => {
  const h = harness();
  h.db.seed(h.base.collection('sale_intents').doc(`pre_pedido:${ORDER}`), {
    protocolVersion: 1, saleIntentId: `pre_pedido:${ORDER}`, lojaId: LOJA, origin: 'pre_pedido',
    operationId: 'x', status: 'reverted', stockEffectHash: 'h'});
  await h.run();
  assert.equal(h.sales().length, 1);
  const intent = h.intent();
  assert.equal(intent.status, 'completed');
  assert.notEqual(intent.origin, 'pre_pedido');
  assert.notEqual(intent.stockEffectHash, 'h');
});

// ---------------------------------------------------------------- replay / concorrência

test('replay sequencial do pagamento processado: +0 venda, +0 estoque, +0 e-mail', async () => {
  const h = harness();
  await h.run();
  const mails = h.mails.length;
  for (let i = 0; i < 3; i++) assert.equal(await h.run(), true);
  assert.equal(h.sales().length, 1);
  assert.equal(h.ops().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.mails.length, mails);
  assert.equal(h.whatsapps.length, 1);
  assert.equal(h.notifications().length, 1);
  assert.deepEqual(h.promo.filter(p => !p[0].endsWith('Recovery')), [['registrar', PID], ['premio', PID]]);
});

test('entregas concorrentes: exatamente 1 venda, 1 baixa, 1 e-mail ao lojista', async () => {
  const h = harness({order: {total: 100}});
  const results = await Promise.all([h.run(), h.run(), h.run(), h.run()]);
  assert.deepEqual(results, [true, true, true, true]);
  assert.equal(h.sales().length, 1);
  assert.equal(h.ops().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.stock('p-simple').stockRevision, 4);
  assert.equal(h.merchantMails().length, 1);
  assert.equal(h.customerMails().length, 1);
  assert.equal(h.whatsapps.length, 1);
  assert.equal(h.notifications().length, 1);
  assertOnlyCanonicalStockWrites(h);
});

// ---------------------------------------------------------------- correlação / tenant

test('loja errada: metadata.loja_id de outra loja cujo token não vê o pagamento → fail closed', async () => {
  const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({loja: OTHER})}}});
  assert.equal(await h.run(), false);
  assertNoEffects(h);
  assertNoEffects(h, {lojaId: OTHER});
  assert.equal(h.marker(), undefined);
});

test('cross-tenant: pagamento da loja B referenciando pedido da loja A → fail closed', async () => {
  const h = harness({
    payments: {[PID]: {lojaId: OTHER, payment: mpPayment({loja: OTHER})}},
  });
  assert.equal(await h.run(), false);
  assertNoEffects(h);
  assertNoEffects(h, {lojaId: OTHER});
  assert.equal(h.order().status, 'pendente');
});

for (const [name, payment, order] of [
  ['external_reference errado', mpPayment({ext: 'outro_pedido'}), {}],
  ['external_reference ausente', mpPayment({ext: ''}), {}],
  ['metadata sem loja', mpPayment({metadata: {}}), {}],
  ['metadata loja_id e lojaId conflitantes', mpPayment({metadata: {loja_id: LOJA, lojaId: OTHER}}), {}],
  ['metadata lojaId legado conflitando com loja_id', mpPayment({metadata: {loja_id: OTHER, lojaId: LOJA}}), {}],
  ['valor divergente', mpPayment({amount: 1}), {}],
  ['valor +0,01', mpPayment({amount: 100.01}), {}],
  ['valor -0,01', mpPayment({amount: 99.99}), {}],
  ['valor com 3 casas decimais', mpPayment({amount: 100.004}), {}],
  ['valor ausente', mpPayment({amount: null}), {}],
  ['moeda divergente', {...mpPayment(), currency_id: 'USD'}, {}],
  ['moeda ausente', {...mpPayment(), currency_id: undefined}, {}],
  ['lojaId do pedido divergente', mpPayment(), {lojaId: OTHER}],
]) {
  test(`correlação: ${name} → fail closed`, async () => {
    const h = harness({payments: {[PID]: {lojaId: LOJA, payment}}, order});
    assert.equal(await h.run(), false);
    assertNoEffects(h);
    assert.equal(h.marker(), undefined);
    assert.equal(h.order().paidAt, undefined);
  });
}

for (const [name, metadata] of [
  ['só lojaId (legado)', {lojaId: LOJA}],
  ['loja_id e lojaId iguais', {loja_id: LOJA, lojaId: LOJA}],
]) {
  test(`metadata compatível: ${name} → venda`, async () => {
    const h = harness({payments: {[PID]: {lojaId: LOJA, payment: mpPayment({metadata})}}});
    assert.equal(await h.run(), true);
    assert.equal(h.sales().length, 1);
  });
}

test('valor exato em centavos com total do pedido em ponto flutuante (99.9 + 0.1): venda', async () => {
  const h = harness({order: {total: 99.9 + 0.1}});
  await h.run();
  assert.equal(h.sales().length, 1);
});

test('venda canônica já correlacionada: marcador perdido → intenção bloqueia; sem intenção → replay da operação, 0 extra', async () => {
  const h = harness();
  await h.run();
  const mails = h.mails.length;
  const markerRef = h.db.collection('_mp_webhook_processed').doc(PID);
  const intentRef = h.base.collection('sale_intents').doc(`pre_pedido:${ORDER}`);
  await h.db.runTransaction(async tx => { tx.delete(markerRef); });
  await h.run();
  assert.equal(h.marker().status, 'already_business_confirmed');
  assert.equal(h.sales().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);

  await h.db.runTransaction(async tx => {
    tx.delete(markerRef);
    tx.delete(intentRef);
    tx.update(h.orderRef, {status: 'pendente', statusPagamento: 'pendente', paidAt: null, paymentId: null,
      vendaId: null, saleId: null, mpPaymentStatus: null});
  });
  await h.run();
  assert.equal(h.sales().length, 1);
  assert.equal(h.ops().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.stock('p-simple').stockRevision, 4);
  assert.equal(h.marker().effectiveOutcome, 'applied_sale_replayed');
  assert.equal(h.mails.length, mails);
});

test('pedido inexistente → fail closed', async () => {
  const h = harness({noOrder: true});
  assert.equal(await h.run(), false);
  assertNoEffects(h);
  assert.equal(h.marker(), undefined);
});

test('pagamento inexistente na API / id inválido → fail closed', async () => {
  const h = harness({payments: {}});
  assert.equal(await h.run(), false);
  assert.equal(await h.run('abc/../x'), false);
  assertNoEffects(h);
});

// ---------------------------------------------------------------- variações

for (const [name, productId, sel, check] of [
  ['tamanho', 'p-size', {tamanho: '15', cor: 'sem-cor'}, s => { assert.equal(s.variacoes['15']['sem-cor'], 1); assert.equal(s.variacoes['22']['sem-cor'], 1); }],
  ['cor', 'p-color', {tamanho: '', cor: 'Azul'}, s => { assert.equal(s.variacoes['sem-tamanho'].Azul, 1); assert.equal(s.variacoes['sem-tamanho'].Rosa, 1); }],
  ['tamanho+cor', 'p-grade', {tamanho: 'P', cor: 'Vermelho'}, s => { assert.equal(s.variacoes.P.Vermelho, 2); assert.equal(s.variacoes.P.Azul, 2); assert.equal(s.variacoes.M.Azul, 1); }],
  ['dimensão extra', 'p-extra', {tamanho: 'P', cor: 'Azul', extraValor: 'B', variacaoExtraResumo: 'Modelo: B'}, s => { assert.equal(s.variacoes.P.Azul.B, 0); assert.equal(s.variacoes.P.Azul.A, 2); }],
]) {
  test(`variação ${name}: baixa exatamente a célula`, async () => {
    const h = harness({products: [item(productId, sel)]});
    await h.run();
    const s = h.stock(productId);
    check(s);
    assert.equal(s.stockOperationId, OP);
    assert.equal(s.stockRevision, PRODUCTS[productId].stockRevision + 1);
    assert.equal(h.sales().length, 1);
    assertOnlyCanonicalStockWrites(h);
  });
}

test('estoque insuficiente numa linha: nenhuma venda parcial, alerta ao lojista, pedido segue confirmável', async () => {
  const h = harness({products: [item('p-simple'), item('p-size', {tamanho: '22', cor: '', quantidade: 2})]});
  assert.equal(await h.run(), true);
  assert.deepEqual(h.sales(), []);
  assert.deepEqual(h.ops(), []);
  assert.equal(h.stock('p-simple').quantidade, 5);
  assert.equal(h.stock('p-size').variacoes['22']['sem-cor'], 1);
  const order = h.order();
  assert.equal(order.status, 'pendente');
  assert.equal(order.statusPagamento, 'pendente');
  assert.equal(order.paymentId, undefined);
  assert.equal(order.paidAt, undefined);
  assert.equal(order.mpAutoSale.status, 'blocked');
  const marker = h.marker();
  assert.equal(marker.status, 'sale_blocked');
  assert.match(marker.reason, /insufficient_stock/i);
  assert.equal(h.merchantMails().length, 1);
  assert.match(h.merchantMails()[0].subject, /confirme o pedido/);
  assert.equal(h.customerMails().length, 0);
  assert.equal(h.whatsapps.length, 0);
  await h.run();
  assert.equal(h.merchantMails().length, 1);
  assert.deepEqual(h.sales(), []);
});

test('combo configurável: venda automática bloqueada (confirmação manual)', async () => {
  const h = harness({products: [item('p-simple', {itensComboComSelecao: [{productId: 'p-size', quantidade: 1}]})]});
  await h.run();
  assert.deepEqual(h.sales(), []);
  assert.equal(h.stock('p-simple').quantidade, 5);
  assert.equal(h.marker().reason, 'configurable_combo_requires_manual_confirmation');
});

test('pedido cancelado com pagamento aprovado: sem venda, alerta ao lojista', async () => {
  const h = harness({order: {status: 'cancelado'}});
  await h.run();
  assert.deepEqual(h.sales(), []);
  assert.equal(h.marker().status, 'sale_blocked');
  assert.equal(h.marker().reason, 'order_cancelled');
  assert.equal(h.merchantMails().length, 1);
  assert.equal(h.customerMails().length, 0);
});

test('controle de estoque inválido (manutenção): sem venda, bloqueado', async () => {
  const h = harness({control: 'INVALID'});
  await h.run();
  assert.deepEqual(h.sales(), []);
  assert.equal(h.stock('p-simple').quantidade, 5);
  assert.equal(h.marker().status, 'sale_blocked');
});

// ---------------------------------------------------------------- e-mail

test('falha SMTP: venda=1, estoque=1, pago=true, e-mail=0 com erro registrado; retomada envia 1 vez', async () => {
  const h = harness({smtpFails: true});
  assert.equal(await h.run(), true);
  assert.equal(h.sales().length, 1);
  assert.equal(h.stock('p-simple').quantidade, 4);
  assert.equal(h.order().status, 'paid');
  assert.equal(h.mails.length, 0);
  let marker = h.marker();
  assert.equal(marker.merchantPaidEmailSentAt, undefined);
  assert.match(marker.merchantPaidEmailError, /EAUTH/);
  assert.doesNotMatch(marker.merchantPaidEmailError, /@/);
  assert.ok(marker.whatsappSentAt);

  h.setSmtpBroken(false);
  await h.run();
  assert.equal(h.merchantMails().length, 1);
  assert.equal(h.customerMails().length, 1);
  assert.equal(h.whatsapps.length, 1);
  marker = h.marker();
  assert.ok(marker.merchantPaidEmailSentAt);
  assert.equal(marker.merchantPaidEmailError, null);
  await h.run();
  assert.equal(h.merchantMails().length, 1);
  assert.equal(h.sales().length, 1);
});

test('reentrega fora da janela de retomada não envia e-mail atrasado', async () => {
  const h = harness({smtpFails: true});
  await h.run();
  h.setSmtpBroken(false);
  await h.run(PID, {now: () => NOW + 4 * 24 * 60 * 60 * 1000});
  assert.equal(h.mails.length, 0);
});

test('pagamento estornado depois: reentrega não retoma e-mail de "pedido pago"', async () => {
  const payments = {[PID]: {lojaId: LOJA, payment: mpPayment()}};
  const h = harness({payments, smtpFails: true});
  await h.run();
  h.setSmtpBroken(false);
  payments[PID] = {lojaId: LOJA, payment: {...mpPayment(), status: 'refunded'}};
  await h.run();
  assert.equal(h.mails.length, 0);
});

for (const [name, loja, expected] of [
  ['ownerEmail primeiro', {ownerEmail: 'Owner@Example.test', adminEmail: 'admin@example.test'}, 'owner@example.test'],
  ['adminEmail depois', {adminEmail: 'admin@example.test'}, 'admin@example.test'],
  ['owner.email por último', {}, 'dona@example.test'],
]) {
  test(`precedência do e-mail do lojista: ${name}`, async () => {
    const h = harness({loja});
    await h.run();
    assert.equal(h.merchantMails()[0].to, expected);
  });
}

test('lojista sem e-mail: não bloqueia venda; registrado como skipped', async () => {
  const h = harness({loja: {owner: {}}});
  await h.run();
  assert.equal(h.sales().length, 1);
  assert.equal(h.merchantMails().length, 0);
  assert.equal(h.marker().merchantPaidEmailSkipped, 'merchant_email_missing');
});

test('SMTP não configurado: venda aplicada, e-mail pendente com erro (sem marcar enviado)', async () => {
  const h = harness();
  await h.run(PID, {sendMail: null});
  assert.equal(h.sales().length, 1);
  assert.equal(h.marker().merchantPaidEmailSentAt, undefined);
  assert.equal(h.marker().merchantPaidEmailError, 'smtp_not_configured');
});

// ---------------------------------------------------------------- autorização SERVER_PAYMENT_AUTH

function saleCmd(lojaId, operationId, extra = {}) {
  return {protocolVersion: 1, lojaId, kind: 'sale', operationId, items: [{productId: 'p-simple', quantity: 1}], ...extra};
}

test('cliente não consegue afirmar SERVER_PAYMENT_AUTH (uid igual, objeto diferente)', async () => {
  for (const control of ['NO_CONTROL', 'ACTIVE']) {
    const h = harness({control});
    if (control === 'ACTIVE') {
      h.db.seed(h.base.collection('stock_catalog_access').doc(SERVER_PAYMENT_AUTH.uid), {enabled: true, permissions: {sale: true}});
    }
    await assert.rejects(
      executeStockCommand(h.db, saleCmd(LOJA, 'spoof'), {uid: SERVER_PAYMENT_AUTH.uid}),
      e => e.code === 'permission-denied',
    );
    await assert.rejects(
      executeStockCommand(h.db, saleCmd(LOJA, 'spoof2'), {...SERVER_PAYMENT_AUTH}),
      e => e.code === 'permission-denied',
    );
    assert.equal(h.stock('p-simple').quantidade, 5);
  }
});

test('SERVER_PAYMENT_AUTH limitado a sale: restock/adjust/restore/editorial negados', async () => {
  const h = harness();
  for (const raw of [
    {...saleCmd(LOJA, 'r1'), kind: 'restock'},
    {...saleCmd(LOJA, 'a1'), kind: 'adjust', items: [{productId: 'p-simple', quantity: 9, expectedRevision: 3}]},
    {...saleCmd(LOJA, 'e1'), kind: 'editorial', editorial: {descricao: 'x'}},
  ]) {
    await assert.rejects(executeStockCommand(h.db, raw, SERVER_PAYMENT_AUTH),
      e => e.code === 'permission-denied' || e.code === 'failed-precondition');
  }
  assert.equal(h.stock('p-simple').quantidade, 5);
  assert.deepEqual(h.ops(), []);
});

test('SERVER_PAYMENT_AUTH falha fechado em loja inexistente e controle inválido', async () => {
  const h = harness({control: 'INVALID'});
  await assert.rejects(executeStockCommand(h.db, saleCmd(LOJA, 's1'), SERVER_PAYMENT_AUTH), e => e.code === 'failed-precondition');
  const h2 = harness();
  await assert.rejects(executeStockCommand(h2.db, saleCmd('loja_inexistente', 's1'), SERVER_PAYMENT_AUTH), e => e.code === 'permission-denied');
});

test('dono NO_CONTROL continua vendendo (comportamento existente inalterado)', async () => {
  const h = harness();
  const r = await executeStockCommand(h.db, saleCmd(LOJA, 'owner-sale'), {uid: `owner-${LOJA}`});
  assert.equal(r.alreadyApplied, false);
  assert.equal(h.stock('p-simple').quantidade, 4);
  await assert.rejects(executeStockCommand(h.db, saleCmd(LOJA, 'intruder-sale'), {uid: 'intruder'}), e => e.code === 'permission-denied');
});

// ---------------------------------------------------------------- guarda estática

test('handler não contém escrita direta legada em produtos/estoque_produtos nem espelho mp_', () => {
  const src = readFileSync(join(HERE, '../src/mpWebhookHandler.js'), 'utf8');
  assert.doesNotMatch(src, /collection\(\s*["']produtos["']\s*\)/);
  assert.doesNotMatch(src, /collection\(\s*["']estoque_produtos["']\s*\)/);
  assert.doesNotMatch(src, /collection\(\s*["']estoque_vendas["']\s*\)/);
  assert.doesNotMatch(src, /mp_\$\{orderId\}_\$\{paymentId\}/);
  assert.match(src, /executeStockCommandInTransaction/);
  assert.match(src, /SERVER_PAYMENT_AUTH/);
});
