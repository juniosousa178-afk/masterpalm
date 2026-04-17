/**
 * Forense operacional leve — catálogo MP (somente leitura, root).
 * Fonte: Firestore já persistido (pedido, _idempotency, _mp_webhook_processed, payments/{paymentId}).
 * Não consulta Cloud Logging nem API do Mercado Pago.
 */

import { HttpsError } from "firebase-functions/v2/https";
import { isRootAccountEmail } from "./rootAccounts.js";
import { resolveCatalogOrderForMp } from "./catalogMpOrderHelpers.js";
import { readOrderLojaIndex, resolveLojaIdByOrderId } from "./orderLojaIndex.js";
import { catalogPaymentCorrelationId } from "./mpStructuredLogsMp.js";
import { maskEmailForAudit } from "./planSupportRead.js";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";
/** Falhas de validação do webhook (consultável pelo snapshot; sem raw MP). */
export const WEBHOOK_VALIDATION_REJECTS_COL = "_mp_webhook_validation_rejects";
const IDEMPOTENCY_COL = "_idempotency";
const ENDPOINT = "mpCatalogPayment";

/** Doc id igual ao usado em rateLimiter / mpCatalogPaymentLock. */
export function buildMpCatalogIdempotencyDocId(lojaId, orderId, type) {
  const catalogIdemKey = `${lojaId}:${orderId}:${type}`.slice(0, 128);
  const safeKey = String(catalogIdemKey).replace(/[^a-zA-Z0-9_-]/g, "_");
  return `${ENDPOINT}:${safeKey}`.slice(0, 150);
}

function trim(v) {
  return v == null ? "" : String(v).trim();
}

function tsMillis(v) {
  if (v == null) return null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

/** Remove payload bruto do MP (segurança). */
export function sanitizePaymentsAuditDoc(data) {
  if (!data || typeof data !== "object") return null;
  const { raw, ...rest } = data;
  return rest;
}

/** Mantém apenas campos esperados do registro de falha de validação (defesa em profundidade). */
export function sanitizeWebhookValidationRejectDoc(data) {
  if (!data || typeof data !== "object") return null;
  const allow = [
    "lojaId",
    "orderId",
    "paymentId",
    "externalReference",
    "validationReason",
    "paymentStatus",
    "paymentMethod",
    "amountExpectedCents",
    "amountReceivedCents",
    "currencyId",
    "createdAt",
    "updatedAt",
  ];
  const o = {};
  for (const k of allow) {
    if (Object.prototype.hasOwnProperty.call(data, k)) o[k] = data[k];
  }
  return Object.keys(o).length ? o : null;
}

function summarizeIdempotency(snap, type) {
  if (!snap?.exists) return null;
  const d = snap.data() || {};
  const r = d.result;
  const id = r && r.id != null ? String(r.id) : null;
  return {
    type,
    hasResult: !!r,
    mpCreating: d.mpCreating === true,
    providerResourceId: id,
    createdAtMs: tsMillis(d.createdAt),
  };
}

/**
 * Monta timeline ordenada a partir de sinais persistidos (ms).
 * @param {Array<{ event: string, atMs: number | null }>} entries
 */
export function buildSupportTimeline(entries) {
  return entries
    .filter((e) => e.atMs != null && Number.isFinite(e.atMs))
    .sort((a, b) => a.atMs - b.atMs)
    .map((e) => ({ event: e.event, atMs: e.atMs }));
}

export function deriveSupportIndicators({
  idemPixSnap,
  idemPrefSnap,
  webhookProcSnap,
  validationRejectSnap,
  order,
  paymentsAuditSanitized,
}) {
  const dp = summarizeIdempotency(idemPixSnap, "pix");
  const df = summarizeIdempotency(idemPrefSnap, "preference");
  const hasProviderSuccess = !!(dp?.hasResult || df?.hasResult);
  const hasPersistSuccess = hasProviderSuccess;
  const hasPersistError = !!(dp?.mpCreating && !dp?.hasResult) || !!(df?.mpCreating && !df?.hasResult);
  const hasWebhookProcessed = webhookProcSnap?.exists === true;
  const procData = webhookProcSnap?.exists ? webhookProcSnap.data() || {} : {};
  const hasWebhookProcSuccess =
    webhookProcSnap?.exists === true &&
    (procData.status === "done" || procData.status === "already_paid");
  const rej = validationRejectSnap?.exists ? validationRejectSnap.data() || {} : {};
  const hasValidationRejectRecord = validationRejectSnap?.exists === true;
  const hasValidationFailure = hasValidationRejectRecord && !hasWebhookProcSuccess;
  const validationFailureReason = hasValidationFailure
    ? String(rej.validationReason || "").trim() || null
    : null;
  const validationRejectSuperseded = hasValidationRejectRecord && hasWebhookProcSuccess;
  const hasWebhookApproved =
    paymentsAuditSanitized?.status === "approved" ||
    procData.status === "done" ||
    (String(paymentsAuditSanitized?.status || "").toLowerCase() === "approved");
  const hasOrderPaid = !!order?.paidAt;
  const dupMs = tsMillis(procData.lastDuplicateWebhookAt);
  const hasWebhookRedeliveryIgnored = dupMs != null;
  const eo = procData.effectiveOutcome != null ? String(procData.effectiveOutcome) : "";
  const hasNoopAlreadyPaid =
    procData.status === "already_paid" ||
    eo.startsWith("noop_order_already_paid") ||
    eo === "noop_concurrent_order_already_paid";
  const hasMaterialNewEffect = eo === "applied_order_paid_new_effect" || procData.status === "done";

  return {
    hasProviderSuccess,
    hasPersistSuccess,
    hasPersistError,
    hasWebhookProcessed,
    hasWebhookApproved,
    hasOrderPaid,
    hasValidationFailure,
    validationFailureReason,
    validationRejectSuperseded,
    /** Webhook notificação repetida após doc processado (sem novo efeito no doc principal). */
    hasWebhookRedeliveryIgnored,
    /** Pedido já estava (ou ficou) pago: sem marcar pago de novo com efeito novo. */
    hasNoopAlreadyPaid,
    /** Doc _mp_webhook_processed indica baixa/marcação nova (status done ou outcome explícito). */
    hasMaterialNewEffect,
    /** Alias: reenvio de webhook ignorado (metadado lastDuplicateWebhookAt). */
    hasDuplicateIgnored: hasWebhookRedeliveryIgnored,
    /** Resultado efetivo persistido (preferir a semântica nova). */
    webhookProcessedOutcome: procData.effectiveOutcome != null
      ? String(procData.effectiveOutcome)
      : procData.status != null
        ? String(procData.status)
        : null,
  };
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMpCatalogPaymentSupportSnapshot({ db, request }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const callerEmail = String(request.auth.token?.email || "")
    .trim()
    .toLowerCase();
  if (!isRootAccountEmail(callerEmail)) {
    throw new HttpsError("permission-denied", "Apenas contas root/programador.");
  }

  const data = request.data || {};
  let lojaId = trim(data.lojaId);
  const orderIdInput = trim(data.orderId);
  const externalReference = trim(data.externalReference);
  const paymentIdInput = trim(data.paymentId);

  const orderIdFromExternal = externalReference || orderIdInput;

  if (!paymentIdInput && !orderIdFromExternal) {
    throw new HttpsError(
      "invalid-argument",
      "Informe paymentId ou orderId / externalReference.",
    );
  }

  let orderId = orderIdFromExternal;
  let paymentId = paymentIdInput;
  const warnings = [];

  if (paymentIdInput && !lojaId && !orderIdFromExternal) {
    const procSnap = await db.collection(WEBHOOK_PROCESSED_COL).doc(paymentIdInput).get();
    if (!procSnap.exists) {
      return {
        status: "insufficient_data",
        provider: "mercadopago",
        reason:
          "paymentId sem registro em _mp_webhook_processed; informe lojaId+orderId ou aguarde o webhook.",
        paymentId: paymentIdInput,
      };
    }
    const p = procSnap.data() || {};
    lojaId = trim(p.lojaId);
    orderId = trim(p.orderId);
    if (!lojaId || !orderId) {
      return {
        status: "insufficient_data",
        provider: "mercadopago",
        reason: "_mp_webhook_processed sem lojaId/orderId",
        paymentId: paymentIdInput,
      };
    }
  } else {
    if (!lojaId && orderId) {
      lojaId = (await readOrderLojaIndex(db, orderId)) || (await resolveLojaIdByOrderId(db, orderId));
      if (!lojaId) {
        return {
          status: "not_found",
          provider: "mercadopago",
          reason: "orderId sem lojaId resolvível (índice/varredura)",
          orderId,
        };
      }
    }
    if (!orderId) {
      return {
        status: "not_found",
        provider: "mercadopago",
        reason: "orderId ausente",
      };
    }
  }

  if (!lojaId || !orderId) {
    return { status: "not_found", provider: "mercadopago", reason: "lojaId ou orderId ausente" };
  }

  const resolved = await resolveCatalogOrderForMp(db, lojaId, orderId);
  if (!resolved) {
    return {
      status: "not_found",
      provider: "mercadopago",
      lojaId,
      orderId,
      reason: "pedido não encontrado em pedidos/pre_pedidos/pedidos_pendentes",
    };
  }

  const order = resolved.order || {};
  const orderPaymentId = order.paymentId != null ? String(order.paymentId) : null;
  if (paymentId && orderPaymentId && paymentId !== orderPaymentId) {
    warnings.push("paymentId_request_differs_from_order_paymentId");
  }
  const effectivePaymentId = paymentId || orderPaymentId;

  const idemPixSnap = await db
    .collection(IDEMPOTENCY_COL)
    .doc(buildMpCatalogIdempotencyDocId(lojaId, orderId, "pix"))
    .get();
  const idemPrefSnap = await db
    .collection(IDEMPOTENCY_COL)
    .doc(buildMpCatalogIdempotencyDocId(lojaId, orderId, "preference"))
    .get();

  let webhookProcSnap = { exists: false };
  if (effectivePaymentId) {
    webhookProcSnap = await db.collection(WEBHOOK_PROCESSED_COL).doc(String(effectivePaymentId)).get();
  }

  let paymentsAuditSnap = null;
  let validationRejectSnap = { exists: false };
  if (effectivePaymentId) {
    const paySnap = await db
      .collection(COLLECTION_LOJAS)
      .doc(lojaId)
      .collection("payments")
      .doc(String(effectivePaymentId))
      .get();
    if (paySnap.exists) {
      paymentsAuditSnap = sanitizePaymentsAuditDoc(paySnap.data() || {});
    }
    validationRejectSnap = await db
      .collection(WEBHOOK_VALIDATION_REJECTS_COL)
      .doc(String(effectivePaymentId))
      .get();
  }

  const inferredType = idemPixSnap.exists && summarizeIdempotency(idemPixSnap, "pix")?.hasResult
    ? "pix"
    : idemPrefSnap.exists && summarizeIdempotency(idemPrefSnap, "preference")?.hasResult
      ? "preference"
      : idemPixSnap.exists || idemPrefSnap.exists
        ? "unknown"
        : null;

  const indicators = deriveSupportIndicators({
    idemPixSnap,
    idemPrefSnap,
    webhookProcSnap,
    validationRejectSnap,
    order,
    paymentsAuditSanitized: paymentsAuditSnap,
  });

  const timelineEntries = [];
  const oc = tsMillis(order.createdAt);
  if (oc != null) timelineEntries.push({ event: "order_document_created", atMs: oc });

  const dp = summarizeIdempotency(idemPixSnap, "pix");
  const df = summarizeIdempotency(idemPrefSnap, "preference");
  if (dp?.createdAtMs != null && dp.hasResult) {
    timelineEntries.push({ event: "catalog_idempotency_pix_result", atMs: dp.createdAtMs });
  }
  if (df?.createdAtMs != null && df.hasResult) {
    timelineEntries.push({ event: "catalog_idempotency_preference_result", atMs: df.createdAtMs });
  }

  if (webhookProcSnap.exists) {
    const pr = tsMillis(webhookProcSnap.data()?.processedAt);
    if (pr != null) {
      timelineEntries.push({ event: "webhook_processed_record", atMs: pr });
    }
    const dupAt = tsMillis(webhookProcSnap.data()?.lastDuplicateWebhookAt);
    if (dupAt != null) {
      timelineEntries.push({ event: "webhook_redelivery_ignored", atMs: dupAt });
    }
  }

  if (validationRejectSnap.exists) {
    const vr = validationRejectSnap.data() || {};
    const vrAt = tsMillis(vr.createdAt) ?? tsMillis(vr.updatedAt);
    if (vrAt != null) {
      timelineEntries.push({ event: "webhook_validation_rejected", atMs: vrAt });
    }
  }

  const paidAt = tsMillis(order.paidAt);
  if (paidAt != null) {
    timelineEntries.push({ event: "order_marked_paid_local", atMs: paidAt });
  }

  const timeline = buildSupportTimeline(timelineEntries);

  const summary = {
    lojaId: String(lojaId),
    orderId: String(orderId),
    externalReference: String(orderId),
    paymentId: effectivePaymentId || null,
    provider: "mercadopago",
    tipo: inferredType,
    orderCollection: resolved.collection,
    statusLocal: order.status != null ? String(order.status) : null,
    statusPagamento: order.statusPagamento != null ? String(order.statusPagamento) : null,
    paymentStatusMpDoc: paymentsAuditSnap?.status != null ? String(paymentsAuditSnap.status) : null,
    totalExpected: order.total != null ? Number(order.total) : null,
    createdAtMs: oc,
    paidAtMs: paidAt,
    updatedAtMs: tsMillis(order.updatedAt),
    correlationIdPix: catalogPaymentCorrelationId(lojaId, orderId, "pix"),
    correlationIdPreference: catalogPaymentCorrelationId(lojaId, orderId, "preference"),
    idempotencyDigestNote: "primeiros 12 hex da chave idempotente do catálogo (por tipo)",
  };

  console.log(
    JSON.stringify({
      evt: "mp_catalog_support_snapshot_read",
      callerEmail: maskEmailForAudit(callerEmail),
      lojaId: String(lojaId),
      orderIdSuffix: String(orderId).slice(-8),
      status: "ok",
    }),
  );

  return {
    status: "ok",
    provider: "mercadopago",
    summary,
    indicators,
    timeline,
    idempotency: {
      pix: summarizeIdempotency(idemPixSnap, "pix"),
      preference: summarizeIdempotency(idemPrefSnap, "preference"),
    },
    webhookProcessed: webhookProcSnap.exists
      ? {
          exists: true,
          status: webhookProcSnap.data()?.status ?? null,
          effectiveOutcome: webhookProcSnap.data()?.effectiveOutcome ?? null,
          processedAtMs: tsMillis(webhookProcSnap.data()?.processedAt),
          duplicateWebhookAtMs: tsMillis(webhookProcSnap.data()?.lastDuplicateWebhookAt),
          duplicateWebhookOutcome: webhookProcSnap.data()?.lastDuplicateWebhookOutcome ?? null,
        }
      : { exists: false },
    validationRejection: validationRejectSnap.exists
      ? {
          recordExists: true,
          active: indicators.hasValidationFailure === true,
          reason: String((validationRejectSnap.data() || {}).validationReason || "").trim() || null,
          supersededBySuccessfulWebhook: indicators.validationRejectSuperseded === true,
          recordedAtMs:
            tsMillis((validationRejectSnap.data() || {}).createdAt) ??
            tsMillis((validationRejectSnap.data() || {}).updatedAt),
          sanitized: sanitizeWebhookValidationRejectDoc(validationRejectSnap.data() || {}),
        }
      : { recordExists: false },
    paymentsAudit: paymentsAuditSnap,
    warnings: warnings.length ? warnings : undefined,
  };
}
