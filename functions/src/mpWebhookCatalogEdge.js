/**
 * Borda HTTP do mpWebhook (catálogo MP): autenticação da notificação antes de processMpWebhook.
 *
 * Notificações de pagamentos do catálogo são assinadas pela aplicação MP OAuth/catálogo,
 * cujo segredo está em MP_WEBHOOK_CATALOG_SECRET. MP_WEBHOOK_SECRET pertence ao planWebhook
 * e não é aceito aqui (nem como fallback).
 */

import {
  extractMercadoPagoCatalogWebhookDataId,
  validateMercadoPagoWebhookSignature,
} from "./mercadoPagoWebhookSignature.js";

/** Assinatura ausente/inválida — não processar; MP não deve tratar como sucesso de negócio. */
export const MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS = 401;

/**
 * Falha transitória ao processar (ex.: transação Firestore, exceção não prevista).
 * Permite retentativa pelo MP; distinto de 200 após processMpWebhook concluir (true/false).
 */
export const MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS = 500;

export const MP_WEBHOOK_CATALOG_PLATFORM_SECRET_FALLBACK_ALLOWED = false;

/** @typedef {'catalog_secret'|'none'} MpCatalogWebhookSecretSlot */

/**
 * @param {{ catalogSecret?: string }} opts
 * @returns {{ secret: string, secretSlot: MpCatalogWebhookSecretSlot }}
 */
export function pickMpCatalogWebhookSecret({ catalogSecret }) {
  const cat = String(catalogSecret ?? "").trim();
  if (cat.length > 0) {
    return { secret: cat, secretSlot: "catalog_secret" };
  }
  return { secret: "", secretSlot: "none" };
}

/** @param {import('express').Request} req */
export function verifyMpCatalogWebhookNotification(req, webhookSecret) {
  return validateMercadoPagoWebhookSignature({
    req,
    webhookSecret,
    extractDataId: extractMercadoPagoCatalogWebhookDataId,
  });
}

/**
 * Valida x-signature exclusivamente com MP_WEBHOOK_CATALOG_SECRET.
 * Secret ausente → secret_missing (fail closed).
 * @param {import('express').Request} req
 * @param {{ catalogSecret?: string }} opts
 */
export function verifyMpCatalogWebhookNotificationCatalogSecret(req, { catalogSecret }) {
  const { secret, secretSlot } = pickMpCatalogWebhookSecret({ catalogSecret });
  const sig = verifyMpCatalogWebhookNotification(req, secret);
  return { ...sig, secretSlot };
}
