/**
 * Chave idempotente determinística para APIs do Mercado Pago no fluxo mpCatalogPayment.
 *
 * - Mesmo lojaId + orderId + type → mesma chave em qualquer retry (sem Date/random).
 * - SHA-256 em hex = 64 caracteres (compatível com limite típico do header X-Idempotency-Key).
 * - Complementa external_reference (canônico do pedido); não o substitui.
 *
 * Pré-imagem versionada (mpcat|v1|...) permite evolução futura sem colidir com chaves antigas.
 */

import crypto from "node:crypto";

const PREIMAGE_PREFIX = "mpcat|v1|";

/**
 * @param {string} lojaId
 * @param {string} orderId
 * @param {string} type — ex.: 'pix' | 'preference'
 * @returns {string} 64 caracteres [a-f0-9]
 */
export function buildMpCatalogProviderIdempotencyKey(lojaId, orderId, type) {
  const lid = String(lojaId ?? "").trim();
  const oid = String(orderId ?? "").trim();
  const typ = String(type ?? "").toLowerCase().trim();
  const preimage = `${PREIMAGE_PREFIX}${lid}|${oid}|${typ}`;
  return crypto.createHash("sha256").update(preimage, "utf8").digest("hex");
}
