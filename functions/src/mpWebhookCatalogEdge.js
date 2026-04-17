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

/** @param {import('express').Request} req */
export function verifyMpCatalogWebhookNotification(req, webhookSecret) {
  return validateMercadoPagoWebhookSignature({ req, webhookSecret });
}
