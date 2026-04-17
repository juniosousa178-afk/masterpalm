/**
 * Logs JSON estruturados — domínio Mercado Pago (catálogo + webhook).
 * Sem tokens, sem PII desnecessário; correlação via correlationId (prefixo da chave idempotente do catálogo).
 */

import { buildMpCatalogProviderIdempotencyKey } from "./mpCatalogProviderIdempotencyKey.js";

export const MP_PROVIDER = "mercadopago";

/** Primeiros 12 hex da chave idempotente do provedor (mesmo pedido/tipo → mesmo valor). */
export function catalogPaymentCorrelationId(lojaId, orderId, type) {
  try {
    return buildMpCatalogProviderIdempotencyKey(lojaId, orderId, type).slice(0, 12);
  } catch {
    return undefined;
  }
}

function routeBySeverity(severity, line) {
  const s = String(severity || "info").toLowerCase();
  if (s === "error") console.error(line);
  else if (s === "warn" || s === "warning") console.warn(line);
  else console.log(line);
}

export function emitCatalogPaymentLog(fields) {
  const { severity = "info", ...rest } = fields;
  const line = JSON.stringify({
    service: "mpCatalogPayment",
    provider: MP_PROVIDER,
    severity,
    ...rest,
  });
  routeBySeverity(severity, line);
}

export function emitWebhookLog(fields) {
  const { severity = "info", ...rest } = fields;
  const line = JSON.stringify({
    service: "mpWebhook",
    provider: MP_PROVIDER,
    severity,
    ...rest,
  });
  routeBySeverity(severity, line);
}

/** Trunca texto de erro do provedor para log (sem vazar body grande). */
export function truncateProviderErrorText(txt, maxLen = 240) {
  const s = txt == null ? "" : String(txt);
  if (s.length <= maxLen) return s;
  return `${s.slice(0, maxLen)}…`;
}
