/**
 * Handler do Webhook Mercado Pago (catálogo) – MasterPalm
 *
 * Sequência (pagamento aprovado):
 *   API MP (token da loja) → correlação pedido/loja → venda canônica (stockCatalogCommand
 *   `sale` + `atomicPdvSale`, identidade SERVER_PAYMENT_AUTH) → estoque → pedido pago +
 *   marcador `_mp_webhook_processed/{paymentId}` (mesma transação) → efeitos pós-commit.
 *
 * Garantias:
 * - Status vem apenas da API MP; corpo do webhook e URL de retorno não são autoridade.
 * - Corte (MP_CATALOG_AUTO_SALE_CUTOVER_UTC): venda automática só se a aprovação MP e a criação do
 *   pedido forem >= corte; corte ausente/inválido ou pedido histórico → nenhuma escrita no pedido.
 * - No máximo 1 venda e 1 baixa por pagamento (operationId determinístico + marcador transacional).
 * - Pedido já confirmado (venda manual, vendaId, intenção de venda do app, paidAt) → 0 venda/estoque/e-mail.
 * - Efeitos pós-commit só com paymentApplied=true; cada efeito tem estado próprio no marcador
 *   e só é marcado como enviado após sucesso (reentregas não duplicam).
 */

import { randomUUID } from "node:crypto";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import {
  registrarPromocaoPosPagamentoMp,
  registrarPromocaoPosPagamentoMpRecovery,
} from "./mpWebhookPromo.js";
import {
  ativarPremioRoletaPosPagamentoMp,
  ativarPremioRoletaPosPagamentoMpRecovery,
} from "./mpWebhookPremioRoleta.js";
import { orderTotalToCents } from "./catalogMpOrderHelpers.js";
import { emitWebhookLog } from "./mpStructuredLogsMp.js";
import { executeStockCommandInTransaction, runStockTransaction } from "./stockCatalogCommands.js";
import { SERVER_PAYMENT_AUTH } from "./stockCatalogAccess.js";
import {
  MP_PAYMENT_SALE_PROTOCOL,
  MP_CATALOG_AUTO_SALE_CUTOVER_ENV,
  MP_POST_EFFECTS_RETRY_WINDOW_MS,
  normalizeMpPaymentId,
  mpPaymentSaleOperationId,
  prePedidoSaleIntentId,
  resolvePaymentMetadataLojaId,
  paymentApprovedAtMs,
  parseAutoSaleCutoverUtc,
  evaluatePaymentCutover,
  evaluateOrderCutover,
  timestampLikeToMs,
  validateCatalogPaymentCorrelation,
  classifyOrderForAutoSale,
  classifySaleIntent,
  buildCanonicalSaleCommandFromOrder,
  isDeterministicStockError,
  stockErrorReason,
  maskEmailsInText,
  blockedReasonText,
} from "./mpCatalogPaymentSale.js";

/** Lazy: evita getFirestore() antes de initializeApp() no deploy/analyze */
function getDb() {
  return getFirestore();
}
const nowTs = FieldValue.serverTimestamp();
const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";
/** Forense suporte: falhas de validação (sem raw MP). Não bloqueia _mp_webhook_processed. */
const WEBHOOK_VALIDATION_REJECTS_COL = "_mp_webhook_validation_rejects";
const ORDER_COLLECTIONS = ["pedidos", "pre_pedidos", "pedidos_pendentes"];
/** Escritas do webhook que entram na transação do comando de estoque: pedido, marcador, intenção. */
const SALE_TX_RESERVED_WRITES = 3;
const POST_EFFECTS_CLAIM_TTL_MS = 5 * 60 * 1000;
const POST_EFFECTS_MAX_ATTEMPTS = 5;

/**
 * Registro mínimo consultável para snapshot (sem PII, sem payload bruto).
 * merge: reentradas atualizam updatedAt; createdAt preservado na primeira gravação.
 */
export async function persistWebhookValidationReject(db, payload) {
  const {
    paymentId,
    lojaId,
    orderId,
    externalReference,
    validationReason,
    paymentStatus,
    paymentMethod,
    amountExpectedCents,
    amountReceivedCents,
    currencyId,
  } = payload;
  const ref = db.collection(WEBHOOK_VALIDATION_REJECTS_COL).doc(String(paymentId));
  const existing = await ref.get();
  const doc = {
    lojaId: String(lojaId),
    orderId: String(orderId),
    paymentId: String(paymentId),
    externalReference: String(externalReference ?? orderId),
    validationReason: String(validationReason),
    paymentStatus: paymentStatus != null ? String(paymentStatus) : null,
    paymentMethod: paymentMethod != null ? String(paymentMethod) : null,
    amountExpectedCents: amountExpectedCents != null ? Number(amountExpectedCents) : null,
    amountReceivedCents: amountReceivedCents != null ? Number(amountReceivedCents) : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (currencyId != null && String(currencyId).trim()) {
    doc.currencyId = String(currencyId).toUpperCase().slice(0, 8);
  }
  if (!existing.exists) doc.createdAt = FieldValue.serverTimestamp();
  await ref.set(doc, { merge: true });
}

/** fetch com timeout */
async function fetchWithTimeout(url, opts = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...opts, signal: controller.signal });
    clearTimeout(id);
    return res;
  } catch (e) {
    clearTimeout(id);
    if (e.name === "AbortError") throw new Error(`Request timeout after ${timeoutMs}ms`);
    throw e;
  }
}

/**
 * Obtém token MP da loja (OAuth mp.access_token ou legado mp_access_token)
 */
async function getLojaMpToken(lojaId) {
  try {
    const db = getDb();
    const doc = await db
      .collection(COLLECTION_LOJAS)
      .doc(String(lojaId))
      .collection("config")
      .doc("payments")
      .get();

    const data = doc.exists ? (doc.data() || {}) : {};
    // OAuth: mp.access_token | mp.token | legado: mp_access_token
    const token =
      (data.mp?.access_token || data.mp?.token || data.mp_access_token || "").trim();
    return token || null;
  } catch (e) {
    console.error("[getLojaMpToken] erro:", e);
    return null;
  }
}

/**
 * Busca payment na API MP com o token fornecido
 */
async function fetchPaymentFromMp(paymentId, token) {
  const r = await fetchWithTimeout(
    `https://api.mercadopago.com/v1/payments/${paymentId}`,
    { headers: { Authorization: `Bearer ${token}` } },
    15000
  );

  if (!r.ok) return null;
  return r.json();
}

/**
 * Resolve lojaId e payment.
 * Ordem: busca estritamente em tokens de lojas (sem credencial de plataforma).
 * Exportado para uso em posPagamento.js (multi-loja).
 */
export async function resolveLojaAndPayment(paymentId) {
  // Iterar lojas para encontrar a que tem o payment
  const lojasSnap = await getDb().collection(COLLECTION_LOJAS).select().get();

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const token = await getLojaMpToken(lojaId);
    if (!token || token.length < 10) continue;

    const payment = await fetchPaymentFromMp(paymentId, token);
    if (payment) {
      return { payment, lojaId };
    }
  }

  return { payment: null, lojaId: null };
}

async function fetchPaymentForStore(lojaId, paymentId) {
  const token = await getLojaMpToken(lojaId);
  if (!token || token.length < 10) return null;
  return fetchPaymentFromMp(paymentId, token);
}

async function sendWhatsAppOrderConfirmationHttp({ lojaId, phone, message }) {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) return { ok: false, error: "project_id_missing" };
  const cfUrl = `https://southamerica-east1-${projectId}.cloudfunctions.net/sendWhatsAppOrderConfirmation`;
  const r = await fetchWithTimeout(
    cfUrl,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ lojaId, phone, message }),
    },
    15000
  );
  return r.ok ? { ok: true } : { ok: false, error: `http_${r.status}` };
}

function defaultDeps(mailOpts, overrides) {
  const smtpUser = String(mailOpts.smtpUser || "").trim();
  const smtpPass = String(mailOpts.smtpPass || "").trim();
  let transporter = null;
  return {
    db: overrides.db ?? getDb(),
    findPayment: resolveLojaAndPayment,
    fetchPaymentForStore,
    smtpUser,
    sendMail: smtpUser && smtpPass
      ? async (msg) => {
        transporter ??= nodemailer.createTransport({
          service: "gmail",
          auth: { user: smtpUser, pass: smtpPass },
        });
        await transporter.sendMail(msg);
      }
      : null,
    sendWhatsApp: sendWhatsAppOrderConfirmationHttp,
    promo: {
      registrar: registrarPromocaoPosPagamentoMp,
      registrarRecovery: registrarPromocaoPosPagamentoMpRecovery,
      premio: ativarPremioRoletaPosPagamentoMp,
      premioRecovery: ativarPremioRoletaPosPagamentoMpRecovery,
    },
    now: () => Date.now(),
    cutoverMs: parseAutoSaleCutoverUtc(process.env[MP_CATALOG_AUTO_SALE_CUTOVER_ENV]),
  };
}

function lojaRef(db, lojaId) {
  return db.collection(COLLECTION_LOJAS).doc(String(lojaId));
}

async function findOrder(db, lojaId, orderId) {
  for (const collection of ORDER_COLLECTIONS) {
    const ref = lojaRef(db, lojaId).collection(collection).doc(String(orderId));
    const snap = await ref.get();
    if (snap.exists) {
      return { ref, collection, order: snap.data() || {}, createTimeMs: timestampLikeToMs(snap.createTime) };
    }
  }
  return null;
}

async function rejectAndLog(db, { paymentId, lojaId, orderId, reason, payment, expectedCents }) {
  emitWebhookLog({
    event: "mpWebhook_validation_failed",
    severity: "warn",
    reason,
    paymentId: String(paymentId),
    ...(orderId != null ? { orderId: String(orderId) } : {}),
    ...(lojaId != null ? { lojaId: String(lojaId) } : {}),
  });
  if (!lojaId || !orderId) return;
  try {
    await persistWebhookValidationReject(db, {
      paymentId,
      lojaId,
      orderId,
      externalReference: payment?.external_reference ?? orderId,
      validationReason: reason,
      paymentStatus: payment?.status,
      paymentMethod: payment?.payment_method_id,
      amountExpectedCents: expectedCents ?? null,
      amountReceivedCents: orderTotalToCents(payment?.transaction_amount),
      currencyId: payment?.currency_id ?? null,
    });
  } catch (e) {
    console.warn("[mpWebhook] persist validation reject:", e && e.message);
  }
}

/**
 * Loja dona do pagamento: o token que encontrou o pagamento e `metadata.loja_id` devem coincidir.
 * Se divergirem, só aceita a loja do metadata quando o token dela também enxerga o pagamento.
 */
async function resolveStoreAndPayment(deps, paymentId) {
  const found = await deps.findPayment(paymentId);
  if (!found?.payment || !found.lojaId) return { ok: false, reason: "payment_not_found" };
  let { payment, lojaId } = found;
  if (String(payment.id ?? "") !== paymentId) return { ok: false, reason: "payment_id_mismatch", lojaId };
  const meta = resolvePaymentMetadataLojaId(payment);
  if (meta.conflict) return { ok: false, reason: "metadata_loja_conflict", lojaId, payment };
  const metaLoja = meta.lojaId;
  if (!metaLoja) return { ok: false, reason: "metadata_loja_missing", lojaId, payment };
  if (metaLoja !== String(lojaId)) {
    const viaMeta = await deps.fetchPaymentForStore(metaLoja, paymentId);
    if (!viaMeta || String(viaMeta.id ?? "") !== paymentId) {
      return { ok: false, reason: "payment_store_mismatch", lojaId, payment };
    }
    payment = viaMeta;
    lojaId = metaLoja;
  }
  return { ok: true, payment, lojaId: String(lojaId) };
}

function markerBase({ paymentId, lojaId, orderId, collection, payment }) {
  return {
    protocol: MP_PAYMENT_SALE_PROTOCOL,
    paymentId: String(paymentId),
    lojaId: String(lojaId),
    orderId: String(orderId),
    orderCollection: collection,
    paymentStatus: "approved",
    paymentMethod: payment?.payment_method_id != null ? String(payment.payment_method_id) : null,
    paymentApprovedAt: payment?.date_approved != null ? String(payment.date_approved) : null,
    processedAt: nowTs,
    updatedAt: nowTs,
  };
}

class SaleNotApplicable extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

/**
 * Transação principal: leituras (marcador, pedido, intenção) → comando canônico (leituras+escritas)
 * → pedido pago + intenção + marcador. Erros determinísticos do comando abortam sem escrita.
 */
async function applyApprovedPaymentTransaction(deps, ctx) {
  const { db } = deps;
  const { paymentId, lojaId, orderId, orderRef, collection, payment, paidCents, markerRef } = ctx;
  const intentRef = collection === "pre_pedidos"
    ? lojaRef(db, lojaId).collection("sale_intents").doc(prePedidoSaleIntentId(orderId))
    : null;
  const operationId = mpPaymentSaleOperationId(paymentId);

  return runStockTransaction(db, async (tx) => {
    const marker = await tx.get(markerRef);
    if (marker.exists) return { outcome: "duplicate", paymentApplied: false, marker: marker.data() };
    const orderSnap = await tx.get(orderRef);
    const intentSnap = intentRef ? await tx.get(intentRef) : null;
    const base = markerBase({ paymentId, lojaId, orderId, collection, payment });

    const order = orderSnap.exists ? orderSnap.data() || {} : null;
    const state = classifyOrderForAutoSale(order, paymentId);
    if (state.state === "missing") throw new SaleNotApplicable(state.reason);
    const cut = evaluateOrderCutover({
      createTimeMs: timestampLikeToMs(orderSnap.createTime), order, cutoverMs: deps.cutoverMs,
    });
    if (!cut.ok) return { outcome: "historical_order", reason: cut.reason, paymentApplied: false };
    if (state.state === "already_business_confirmed") {
      tx.set(markerRef, { ...base, status: "already_business_confirmed", reason: state.reason });
      return { outcome: "already_business_confirmed", reason: state.reason, paymentApplied: false };
    }
    const intent = classifySaleIntent(intentSnap?.exists ? intentSnap.data() : null);
    if (intent.blocking) {
      tx.set(markerRef, { ...base, status: "already_business_confirmed", reason: intent.reason });
      return { outcome: "already_business_confirmed", reason: intent.reason, paymentApplied: false };
    }
    if (state.state === "blocked") throw new SaleNotApplicable(state.reason);

    const built = buildCanonicalSaleCommandFromOrder({ lojaId, orderId, paymentId, payment, order, paidCents });
    if (!built.ok) throw new SaleNotApplicable(built.reason);

    const result = await executeStockCommandInTransaction(
      tx, db, built.command, SERVER_PAYMENT_AUTH, SALE_TX_RESERVED_WRITES,
    );

    const orderPatch = {
      status: "paid",
      paidAt: nowTs,
      paymentId: String(paymentId),
      paymentMethod: payment.payment_method_id != null ? String(payment.payment_method_id) : null,
      mpPaymentStatus: "approved",
      vendaId: operationId,
      saleId: operationId,
      saleOperationId: operationId,
      updatedAt: nowTs,
      dataAtualizacao: nowTs,
    };
    if (collection !== "pedidos") orderPatch.statusPagamento = "aprovado";
    tx.update(orderRef, orderPatch);
    if (intentRef) {
      tx.set(intentRef, {
        protocolVersion: 1,
        saleIntentId: prePedidoSaleIntentId(orderId),
        lojaId: String(lojaId),
        origin: "mp_webhook",
        operationId,
        status: "completed",
        stockEffectHash: `mp_payment:${paymentId}`,
        createdAt: nowTs,
        updatedAt: nowTs,
        completedAt: nowTs,
      });
    }
    tx.set(markerRef, {
      ...base,
      status: "applied",
      effectiveOutcome: result.alreadyApplied ? "applied_sale_replayed" : "applied_canonical_sale",
      saleOperationId: operationId,
      postEffectsAttempts: 0,
    });
    return {
      outcome: "applied",
      paymentApplied: result.alreadyApplied !== true,
      saleOperationId: operationId,
      order,
    };
  });
}

/** Venda automática impossível (determinístico): marcador `sale_blocked`, pedido fica para confirmação manual. */
async function recordSaleBlockedTransaction(deps, ctx, reason) {
  const { db } = deps;
  const { paymentId, lojaId, orderId, orderRef, collection, payment, markerRef } = ctx;
  const intentRef = collection === "pre_pedidos"
    ? lojaRef(db, lojaId).collection("sale_intents").doc(prePedidoSaleIntentId(orderId))
    : null;
  return db.runTransaction(async (tx) => {
    const marker = await tx.get(markerRef);
    if (marker.exists) return { outcome: "duplicate", paymentApplied: false, marker: marker.data() };
    const orderSnap = await tx.get(orderRef);
    const intentSnap = intentRef ? await tx.get(intentRef) : null;
    const base = markerBase({ paymentId, lojaId, orderId, collection, payment });
    const order = orderSnap.exists ? orderSnap.data() || {} : null;
    const state = classifyOrderForAutoSale(order, paymentId);
    if (state.state === "missing") {
      return { outcome: "order_missing", paymentApplied: false };
    }
    const cut = evaluateOrderCutover({
      createTimeMs: timestampLikeToMs(orderSnap.createTime), order, cutoverMs: deps.cutoverMs,
    });
    if (!cut.ok) return { outcome: "historical_order", reason: cut.reason, paymentApplied: false };
    if (state.state === "already_business_confirmed") {
      tx.set(markerRef, { ...base, status: "already_business_confirmed", reason: state.reason });
      return { outcome: "already_business_confirmed", reason: state.reason, paymentApplied: false };
    }
    const intent = classifySaleIntent(intentSnap?.exists ? intentSnap.data() : null);
    if (intent.blocking) {
      tx.set(markerRef, { ...base, status: "already_business_confirmed", reason: intent.reason });
      return { outcome: "already_business_confirmed", reason: intent.reason, paymentApplied: false };
    }
    tx.set(markerRef, { ...base, status: "sale_blocked", reason, postEffectsAttempts: 0 });
    // Campos fora de paymentId/paidAt/statusPagamento: o app continua permitindo confirmação manual.
    tx.update(orderRef, {
      mpAutoSale: {
        status: "blocked",
        reason,
        paymentId: String(paymentId),
        at: nowTs,
      },
    });
    return { outcome: "sale_blocked", reason, paymentApplied: false, order };
  });
}

function postEffectKeys(status) {
  return status === "applied"
    ? ["adminNotification", "whatsapp", "customerPaidEmail", "merchantPaidEmail"]
    : ["adminNotification", "merchantPaidEmail"];
}

function effectDone(marker, key) {
  return marker[`${key}SentAt`] != null || marker[`${key}Skipped`] != null;
}

/** Reserva transacional do lote de efeitos pós-commit (um executor por vez, com TTL). */
async function claimPostEffects(deps, markerRef) {
  const claimId = randomUUID();
  const now = deps.now();
  return deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(markerRef);
    if (!snap.exists) return null;
    const m = snap.data() || {};
    if (m.protocol !== MP_PAYMENT_SALE_PROTOCOL) return null;
    if (m.status !== "applied" && m.status !== "sale_blocked") return null;
    const pending = postEffectKeys(m.status).filter((k) => !effectDone(m, k));
    if (!pending.length) return null;
    const claimedAt = Number(m.postEffectsClaimedAtMs || 0);
    if (claimedAt && now - claimedAt < POST_EFFECTS_CLAIM_TTL_MS) return null;
    const attempts = Number(m.postEffectsAttempts || 0);
    if (attempts >= POST_EFFECTS_MAX_ATTEMPTS) return null;
    tx.set(markerRef, {
      postEffectsClaimId: claimId,
      postEffectsClaimedAtMs: now,
      postEffectsAttempts: attempts + 1,
      updatedAt: nowTs,
    }, { merge: true });
    return { claimId, marker: m, pending };
  });
}

function brl(v) {
  return Number(v || 0).toFixed(2).replace(".", ",");
}

/** Precedência: ownerEmail → adminEmail → owner.email. */
export function resolveMerchantEmail(lojaData) {
  const d = lojaData || {};
  let email = String(d.ownerEmail || d.adminEmail || "").trim();
  if (!email && d.owner && typeof d.owner === "object") email = String(d.owner.email || "").trim();
  return email.includes("@") ? email.toLowerCase() : "";
}

async function runPostEffects(deps, ctx) {
  const { db } = deps;
  const { markerRef, paymentId } = ctx;
  const claim = await claimPostEffects(deps, markerRef);
  if (!claim) return { ran: false };
  const m = claim.marker;
  const lojaId = String(m.lojaId);
  const orderId = String(m.orderId);
  const blocked = m.status === "sale_blocked";

  const lojaSnap = await lojaRef(db, lojaId).get();
  const lojaData = lojaSnap.exists ? lojaSnap.data() || {} : {};
  const lojaNome = String(lojaData.nome || "Loja").trim() || "Loja";
  const orderSnap = await lojaRef(db, lojaId).collection(m.orderCollection || "pre_pedidos").doc(orderId).get();
  const order = orderSnap.exists ? orderSnap.data() || {} : {};
  const cliente = order.cliente && typeof order.cliente === "object" ? order.cliente : {};
  const clienteNome = String(cliente.nome || "Cliente").trim() || "Cliente";
  const clienteEmail = String(cliente.email || "").trim().toLowerCase();
  const total = Number(order.total || 0);

  const results = {};
  const record = (key, outcome) => {
    if (outcome.sent) {
      results[`${key}SentAt`] = nowTs;
      results[`${key}Error`] = null;
    } else if (outcome.skipped) {
      results[`${key}Skipped`] = outcome.skipped;
    } else {
      results[`${key}Error`] = maskEmailsInText(String(outcome.error || "error")).slice(0, 300);
      results[`${key}LastAttemptAt`] = nowTs;
    }
  };

  for (const key of claim.pending) {
    try {
      if (key === "adminNotification") {
        const adminUid = String(lojaData.ownerUid || lojaData.adminUid || "");
        if (!adminUid) { record(key, { skipped: "owner_uid_missing" }); continue; }
        const ref = lojaRef(db, lojaId).collection("notificacoes").doc(`mp_paid_${paymentId}`);
        const doc = blocked
          ? {
            destinatarioUid: adminUid,
            tipo: "pagamentoAprovadoAcaoNecessaria",
            titulo: "⚠️ Pagamento aprovado — confirme o pedido",
            mensagem: `Cliente: ${clienteNome}\nValor: R$ ${brl(total)}\n\nA venda não foi registrada automaticamente: ${blockedReasonText(m.reason)}.`,
          }
          : {
            destinatarioUid: adminUid,
            tipo: "novaVenda",
            titulo: "🎉 NOVO PEDIDO PAGO! Parabéns!",
            mensagem: `Cliente: ${clienteNome}\nValor: R$ ${brl(total)}\n\n✅ PAGAMENTO CONFIRMADO - Venda registrada e estoque atualizado.`,
          };
        try {
          await ref.create({
            ...doc,
            pedidoId: orderId,
            storeId: lojaId,
            valor: total,
            criadaEm: nowTs,
            lida: false,
            dados: { clienteNome, origem: "catalogo_web", pagamentoConfirmado: true },
          });
        } catch (e) {
          if (!(e?.code === 6 || e?.code === "already-exists")) throw e;
        }
        record(key, { sent: true });
      } else if (key === "whatsapp") {
        const telefone = String(cliente.telefone || "").trim().replace(/\D/g, "");
        if (telefone.length < 10) { record(key, { skipped: "customer_phone_missing" }); continue; }
        const itens = order.items || order.itens || [];
        const itensLinhas = itens
          .map((it) => `➡ ${Number(it.qty ?? it.quantidade ?? 1)}x ${String(it.name || it.nome || "")}`)
          .join("\n");
        const formaPagamento = String(order.pagamento || "Mercado Pago");
        const endereco = String(cliente.enderecoFormatado || cliente.endereco || "Não informado");
        const message = `Olá ${clienteNome}, aqui é o atendente virtual da *${lojaNome.toUpperCase()}*.

Vim te avisar que seu pagamento foi aprovado e o pedido foi confirmado. 😊
Fique tranquilo(a) que vou enviar as atualizações do status do seu pedido por aqui.

*Nº do pedido* ${orderId}

*Itens:*
${itensLinhas || "—"}

*Forma de pagamento:* ${formaPagamento}

*Local de entrega:* ${endereco}

*Total do pedido:* R$ ${brl(total)}

Obrigado por comprar conosco! 💜`;
        const r = await deps.sendWhatsApp({ lojaId, phone: cliente.telefone || telefone, message });
        record(key, r?.ok ? { sent: true } : { error: r?.error || "whatsapp_failed" });
      } else if (key === "customerPaidEmail") {
        if (!deps.sendMail) { record(key, { error: "smtp_not_configured" }); continue; }
        if (!clienteEmail.includes("@")) { record(key, { skipped: "customer_email_missing" }); continue; }
        await deps.sendMail({
          from: `"${lojaNome}" <${deps.smtpUser}>`,
          to: clienteEmail,
          subject: `Pagamento confirmado — pedido ${orderId}`,
          text:
            `Olá, ${clienteNome}!\n\n` +
            `Seu pagamento foi aprovado e o pedido foi confirmado.\n\n` +
            `Pedido: ${orderId}\n` +
            `Total: R$ ${brl(total)}\n\n` +
            `Em breve a loja pode entrar em contato com atualizações do envio.\n\n` +
            `Obrigado por comprar conosco!`,
        });
        record(key, { sent: true });
      } else if (key === "merchantPaidEmail") {
        if (!deps.sendMail) { record(key, { error: "smtp_not_configured" }); continue; }
        const merchantEmail = resolveMerchantEmail(lojaData);
        if (!merchantEmail) { record(key, { skipped: "merchant_email_missing" }); continue; }
        const linhas = [
          blocked
            ? "Pagamento aprovado no Mercado Pago — AÇÃO NECESSÁRIA."
            : "Pagamento aprovado no Mercado Pago.",
          "",
          `Pedido / referência: ${orderId}`,
          `Cliente: ${clienteNome}`,
          `E-mail do cliente: ${clienteEmail || "(não informado)"}`,
          `Valor: R$ ${brl(total)}`,
          `ID pagamento MP: ${paymentId}`,
          "",
          blocked
            ? `A venda NÃO foi registrada automaticamente e o estoque NÃO foi baixado: ${blockedReasonText(m.reason)}.\nConfirme o pedido manualmente no painel da loja.`
            : "A venda foi registrada automaticamente e o estoque foi atualizado.\nConsulte os detalhes no painel da loja.",
        ];
        await deps.sendMail({
          from: `"MasterPalm" <${deps.smtpUser}>`,
          to: merchantEmail,
          subject: blocked
            ? `Pagamento aprovado — confirme o pedido ${orderId} — ${lojaNome}`
            : `Pedido pago — ${orderId} — ${lojaNome}`,
          text: linhas.join("\n"),
        });
        record(key, { sent: true });
      }
    } catch (e) {
      record(key, { error: `${e?.code ? `${e.code}: ` : ""}${e?.message || e}` });
    }
  }

  await markerRef.set({ ...results, postEffectsClaimedAtMs: null, updatedAt: nowTs }, { merge: true });
  emitWebhookLog({
    event: "mpWebhook_post_effects_done",
    severity: Object.keys(results).some((k) => k.endsWith("Error") && results[k]) ? "warn" : "info",
    paymentId: String(paymentId),
    lojaId,
    orderId,
    outcome: m.status,
    effects: Object.fromEntries(claim.pending.map((k) => [
      k,
      results[`${k}SentAt`] ? "sent" : results[`${k}Skipped`] ? `skipped:${results[`${k}Skipped`]}` : "failed",
    ])),
  });
  return { ran: true, results };
}

async function runPromo(deps, kind, args) {
  const db = deps.db;
  const fns = kind === "recovery"
    ? [deps.promo.registrarRecovery, deps.promo.premioRecovery]
    : [deps.promo.registrar, deps.promo.premio];
  for (const fn of fns) {
    if (!fn) continue;
    try {
      await fn(db, args);
    } catch (e) {
      console.error("[PROMO-ERROR] pós-venda MP", e && e.message);
    }
  }
}

function withinRetryWindow(deps, payment) {
  const approvedMs = paymentApprovedAtMs(payment);
  return approvedMs != null && deps.now() - approvedMs <= MP_POST_EFFECTS_RETRY_WINDOW_MS;
}

/** Reentrega após marcador: só retoma efeitos pendentes do protocolo atual, dentro da janela. */
async function handleRedelivery(deps, ctx, markerData) {
  const { markerRef, paymentId, payment } = ctx;
  emitWebhookLog({
    event: "mpWebhook_duplicate_ignored",
    severity: "info",
    paymentId: String(paymentId),
    lojaId: markerData?.lojaId != null ? String(markerData.lojaId) : undefined,
    orderId: markerData?.orderId != null ? String(markerData.orderId) : undefined,
    markerStatus: markerData?.status != null ? String(markerData.status) : undefined,
  });
  try {
    await markerRef.set(
      { lastDuplicateWebhookAt: nowTs, lastDuplicateWebhookOutcome: "noop_redelivery_after_processed", updatedAt: nowTs },
      { merge: true },
    );
  } catch (e) {
    console.warn("[mpWebhook] merge duplicate delivery meta:", e && e.message);
  }
  if (markerData?.protocol !== MP_PAYMENT_SALE_PROTOCOL) return;
  if (markerData.status !== "applied" && markerData.status !== "sale_blocked") return;
  if (String(payment?.status ?? "") !== "approved") return;
  if (!withinRetryWindow(deps, payment)) return;
  if (markerData.status === "applied") {
    const orderRef = lojaRef(deps.db, markerData.lojaId)
      .collection(markerData.orderCollection || "pre_pedidos").doc(String(markerData.orderId));
    await runPromo(deps, "recovery", { lojaId: markerData.lojaId, orderId: markerData.orderId, paymentId, orderRef });
  }
  await runPostEffects(deps, ctx);
}

/**
 * Processa o webhook de pagamento MP (catálogo).
 * Retorna true se processou (ou já estava processado / sem efeito por regra), false se rejeitado.
 *
 * @param {string} paymentIdRaw — data.id validado pelo HMAC da borda
 * @param {{ smtpUser?: string; smtpPass?: string }} [mailOpts]
 * @param {object} [overrides] — testes: db, findPayment, fetchPaymentForStore, sendMail, sendWhatsApp, promo, now
 */
export async function processMpWebhook(paymentIdRaw, mailOpts = {}, overrides = {}) {
  const paymentId = normalizeMpPaymentId(paymentIdRaw);
  if (!paymentId) return false;
  const deps = { ...defaultDeps(mailOpts, overrides), ...overrides };
  const { db } = deps;

  const resolved = await resolveStoreAndPayment(deps, paymentId);
  if (!resolved.ok) {
    await rejectAndLog(db, {
      paymentId,
      lojaId: resolved.lojaId,
      orderId: resolved.payment?.external_reference,
      reason: resolved.reason,
      payment: resolved.payment,
    });
    return false;
  }
  const { payment, lojaId } = resolved;
  const status = payment.status != null ? String(payment.status) : "";
  const orderId = String(payment.external_reference ?? "").trim();
  emitWebhookLog({
    event: "mpWebhook_received",
    severity: "info",
    paymentId,
    paymentStatus: status || undefined,
    paymentMethod: payment.payment_method_id != null ? String(payment.payment_method_id) : undefined,
    externalReference: orderId || undefined,
    lojaId,
  });
  if (!orderId || orderId.includes("/")) {
    await rejectAndLog(db, { paymentId, lojaId, orderId: null, reason: "external_reference_missing", payment });
    return false;
  }

  const markerRef = db.collection(WEBHOOK_PROCESSED_COL).doc(paymentId);
  const ctxBase = { paymentId, lojaId, orderId, payment, markerRef };
  const existing = await markerRef.get();
  if (existing.exists) {
    await handleRedelivery(deps, ctxBase, existing.data() || {});
    return true;
  }

  try {
    await lojaRef(db, lojaId).collection("payments").doc(paymentId).set(
      {
        kind: "payment",
        orderId,
        lojaId,
        status,
        amount: payment.transaction_amount,
        raw: payment,
        updatedAt: nowTs,
      },
      { merge: true },
    );
  } catch (auditErr) {
    emitWebhookLog({
      event: "mpWebhook_payments_audit_write_failed",
      severity: "warn",
      paymentId,
      orderId,
      lojaId,
      err: String(auditErr?.message || auditErr),
    });
  }

  if (status !== "approved") return true;

  const paymentCut = evaluatePaymentCutover({ payment, cutoverMs: deps.cutoverMs });
  if (!paymentCut.ok) {
    await rejectAndLog(db, { paymentId, lojaId, orderId, reason: paymentCut.reason, payment });
    return true;
  }

  const found = await findOrder(db, lojaId, orderId);
  if (!found) {
    await rejectAndLog(db, { paymentId, lojaId, orderId, reason: "order_document_not_found", payment });
    return false;
  }
  const orderCut = evaluateOrderCutover({
    createTimeMs: found.createTimeMs, order: found.order, cutoverMs: deps.cutoverMs,
  });
  if (!orderCut.ok) {
    await rejectAndLog(db, { paymentId, lojaId, orderId, reason: orderCut.reason, payment });
    return true;
  }
  const corr = validateCatalogPaymentCorrelation({ payment, lojaId, orderId, order: found.order });
  if (!corr.ok) {
    await rejectAndLog(db, {
      paymentId, lojaId, orderId, reason: corr.code, payment,
      expectedCents: orderTotalToCents(found.order.total),
    });
    return false;
  }

  const ctx = {
    ...ctxBase,
    orderRef: found.ref,
    collection: found.collection,
    paidCents: corr.paidCents,
  };
  let txResult;
  try {
    txResult = await applyApprovedPaymentTransaction(deps, ctx);
  } catch (e) {
    if (e instanceof SaleNotApplicable && e.reason === "order_document_not_found") {
      await rejectAndLog(db, { paymentId, lojaId, orderId, reason: e.reason, payment });
      return false;
    }
    if (!(e instanceof SaleNotApplicable) && !isDeterministicStockError(e)) {
      emitWebhookLog({
        event: "mpWebhook_sale_transaction_error",
        severity: "error",
        paymentId,
        orderId,
        lojaId,
        err: String(e?.message || e).slice(0, 300),
      });
      throw e;
    }
    const reason = e instanceof SaleNotApplicable ? e.reason : stockErrorReason(e);
    txResult = await recordSaleBlockedTransaction(deps, ctx, reason);
  }

  emitWebhookLog({
    event: "mpWebhook_payment_outcome",
    severity: txResult.outcome === "sale_blocked" ? "warn" : "info",
    paymentId,
    orderId,
    lojaId,
    outcome: txResult.outcome,
    paymentApplied: txResult.paymentApplied === true,
    ...(txResult.reason ? { reason: txResult.reason } : {}),
  });

  if (txResult.outcome === "duplicate") {
    await handleRedelivery(deps, ctxBase, txResult.marker || {});
    return true;
  }
  if (txResult.outcome === "order_missing") {
    await rejectAndLog(db, { paymentId, lojaId, orderId, reason: "order_document_not_found", payment });
    return false;
  }
  if (txResult.outcome === "historical_order") {
    await rejectAndLog(db, { paymentId, lojaId, orderId, reason: txResult.reason, payment });
    return true;
  }
  if (txResult.outcome === "applied" && txResult.paymentApplied === true) {
    await runPromo(deps, "first", {
      lojaId, orderId, paymentId, orderData: txResult.order, orderRef: found.ref,
    });
    await runPostEffects(deps, ctx);
  } else if (txResult.outcome === "sale_blocked") {
    await runPostEffects(deps, ctx);
  }
  return true;
}
