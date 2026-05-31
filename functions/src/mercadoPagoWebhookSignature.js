/**
 * Validação de autenticidade das notificações Webhook do Mercado Pago (header x-signature).
 * @see https://www.mercadopago.com.br/developers/pt/docs/your-integrations/notifications/webhooks
 *
 * Não loga segredo nem assinatura completa.
 */

import crypto from "node:crypto";

const MAX_TS_SKEW_SEC = 600; // tolerância de relógio / atraso

function headerGet(req, name) {
  const h = req?.headers || {};
  const lower = String(name).toLowerCase();
  if (h[lower]) return String(h[lower]).trim();
  const up = Object.keys(h).find((k) => k.toLowerCase() === lower);
  return up ? String(h[up]).trim() : "";
}

function coalesceNotificationId(value) {
  if (value == null) return "";
  const s = String(value).trim();
  return s.length > 0 ? s : "";
}

/**
 * data.id para o manifest HMAC — ordem alinhada ao contrato MP e formatos legados.
 * 1. query["data.id"]  (?data.id=&type=payment)
 * 2. query.data.id     (parser aninhado, ex. ?data[id]=)
 * 3. query.id          (?id=&topic=payment — legado)
 * 4. body.data.id
 * 5. body.id
 */
export function extractMercadoPagoWebhookDataId(req) {
  const q = req?.query || {};

  const fromDataIdKey = coalesceNotificationId(q["data.id"]);
  if (fromDataIdKey) return fromDataIdKey;

  const qData = q.data;
  if (qData && typeof qData === "object" && !Array.isArray(qData)) {
    const fromNestedQuery = coalesceNotificationId(qData.id);
    if (fromNestedQuery) return fromNestedQuery;
  }

  const fromQueryId = coalesceNotificationId(q.id);
  if (fromQueryId) return fromQueryId;

  const b = req?.body || {};
  const fromBodyDataId = coalesceNotificationId(b?.data?.id);
  if (fromBodyDataId) return fromBodyDataId;

  const fromBodyId = coalesceNotificationId(b?.id);
  if (fromBodyId) return fromBodyId;

  return "";
}

/**
 * Formato da notificação (somente para logs estruturados — sem secret/assinatura).
 * @returns {'query_data_id_type'|'query_data_id'|'query_data_object_id'|'query_id_topic'|'query_id'|'body_data_id'|'body_id'|'none'}
 */
export function detectMercadoPagoWebhookNotificationFormat(req) {
  const q = req?.query || {};
  const b = req?.body || {};

  if (q["data.id"] != null && String(q["data.id"]).length > 0) {
    return q.type != null && String(q.type).length > 0 ? "query_data_id_type" : "query_data_id";
  }

  const qData = q.data;
  if (qData && typeof qData === "object" && !Array.isArray(qData) && qData.id != null && String(qData.id).length > 0) {
    return "query_data_object_id";
  }

  if (q.id != null && String(q.id).length > 0) {
    return q.topic != null && String(q.topic).length > 0 ? "query_id_topic" : "query_id";
  }

  if (b?.data?.id != null && String(b.data.id).length > 0) return "body_data_id";
  if (b?.id != null && String(b.id).length > 0) return "body_id";

  return "none";
}

/**
 * Campos seguros para log de diagnóstico de assinatura (mpWebhook catálogo).
 * Nunca inclui webhookSecret, x-signature completo ou tokens.
 */
export function buildMercadoPagoWebhookSignatureLogContext(req) {
  return {
    notificationFormat: detectMercadoPagoWebhookNotificationFormat(req),
    hasXSignature: Boolean(headerGet(req, "x-signature")),
    hasXRequestId: Boolean(headerGet(req, "x-request-id")),
    extractedDataIdLen: extractMercadoPagoWebhookDataId(req).length,
  };
}

function normalizeDataIdForManifest(dataId) {
  const s = String(dataId || "");
  if (!s) return s;
  if (/^[a-f0-9]+$/i.test(s)) return s.toLowerCase();
  return s;
}

function parseXsSignature(xSignature) {
  if (!xSignature || typeof xSignature !== "string") {
    return { ts: null, v1: null };
  }
  let ts = null;
  let v1 = null;
  const parts = xSignature.split(",");
  for (const part of parts) {
    const idx = part.indexOf("=");
    if (idx < 0) continue;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (key === "ts") ts = value;
    else if (key === "v1") v1 = value;
  }
  return { ts, v1 };
}

function buildManifest({ dataId, requestId, ts }) {
  const segments = [];
  const idNorm = normalizeDataIdForManifest(dataId);
  if (idNorm !== "") segments.push(`id:${idNorm}`);
  if (requestId) segments.push(`request-id:${requestId}`);
  if (ts) segments.push(`ts:${ts}`);
  return segments.length ? `${segments.join(";")};` : "";
}

/**
 * @param {object} opts
 * @param {import('express').Request} opts.req
 * @param {string} opts.webhookSecret - assinatura secreta do painel Webhooks (Suas integrações)
 * @returns {{ ok: true, dataId: string } | { ok: false, reason: string, detail?: string }}
 */
export function validateMercadoPagoWebhookSignature({ req, webhookSecret }) {
  const secret = String(webhookSecret || "").trim();
  if (!secret) {
    return { ok: false, reason: "secret_missing", detail: "MP_WEBHOOK_SECRET não configurado" };
  }

  const xSignature = headerGet(req, "x-signature");
  if (!xSignature) {
    return { ok: false, reason: "header_missing" };
  }

  const { ts, v1 } = parseXsSignature(xSignature);
  if (!ts || !v1) {
    return { ok: false, reason: "header_malformed" };
  }

  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum) || tsNum <= 0) {
    return { ok: false, reason: "ts_invalid" };
  }
  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - tsNum) > MAX_TS_SKEW_SEC) {
    return { ok: false, reason: "ts_out_of_range" };
  }

  const xRequestId = headerGet(req, "x-request-id");
  const dataId = extractMercadoPagoWebhookDataId(req);
  const manifest = buildManifest({
    dataId,
    requestId: xRequestId || "",
    ts,
  });
  if (!manifest) {
    return { ok: false, reason: "manifest_empty" };
  }

  const expectedHex = String(v1).trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(expectedHex)) {
    return { ok: false, reason: "v1_not_hex" };
  }

  let computed;
  try {
    computed = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  } catch (e) {
    return { ok: false, reason: "hmac_error", detail: String(e?.message || e) };
  }

  const a = Buffer.from(computed, "hex");
  const b = Buffer.from(expectedHex, "hex");
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, reason: "hmac_mismatch" };
  }

  return { ok: true, dataId };
}
