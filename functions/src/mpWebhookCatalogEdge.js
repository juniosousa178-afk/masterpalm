/**
 * Borda HTTP do mpWebhook (catálogo MP): autenticação da notificação antes de processMpWebhook.
 * Reutiliza validateMercadoPagoWebhookSignature (mesmo contrato do planWebhook).
 */

import { validateMercadoPagoWebhookSignature } from "./mercadoPagoWebhookSignature.js";

/** Assinatura ausente/inválida — não processar; MP não deve tratar como sucesso de negócio. */
export const MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS = 401;

/**
 * Falha transitória ao processar (ex.: transação Firestore, exceção não prevista).
 * Permite retentativa pelo MP; distinto de 200 após processMpWebhook concluir (true/false).
 */
export const MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS = 500;

/** @typedef {'catalog_secret'|'platform_secret'|'none'} MpCatalogWebhookSecretSlot */

/**
 * Escolhe qual secret usar na borda do catálogo (sem fallback em mismatch).
 * @param {{ catalogSecret?: string, platformSecret?: string }} opts
 * @returns {{ secret: string, secretSlot: MpCatalogWebhookSecretSlot }}
 */
export function pickMpCatalogWebhookSecret({ catalogSecret, platformSecret }) {
  const cat = String(catalogSecret ?? "").trim();
  if (cat.length > 0) {
    return { secret: cat, secretSlot: "catalog_secret" };
  }
  const plat = String(platformSecret ?? "").trim();
  if (plat.length > 0) {
    return { secret: plat, secretSlot: "platform_secret" };
  }
  return { secret: "", secretSlot: "none" };
}

/** @param {import('express').Request} req */
export function verifyMpCatalogWebhookNotification(req, webhookSecret) {
  return validateMercadoPagoWebhookSignature({ req, webhookSecret });
}

/**
 * Valida x-signature usando MP_WEBHOOK_CATALOG_SECRET se configurado; senão MP_WEBHOOK_SECRET.
 * @param {import('express').Request} req
 * @param {{ catalogSecret?: string, platformSecret?: string }} opts
 */
export function verifyMpCatalogWebhookNotificationWithSlots(req, { catalogSecret, platformSecret }) {
  const { secret, secretSlot } = pickMpCatalogWebhookSecret({ catalogSecret, platformSecret });
  const sig = validateMercadoPagoWebhookSignature({ req, webhookSecret: secret });
  return { ...sig, secretSlot };
}
