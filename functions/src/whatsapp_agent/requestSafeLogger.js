/**
 * Logs seguros para o webhook WhatsApp: sem req.body nem conteúdo de mensagem.
 * Lote 1.
 */

/**
 * @param {string} method - GET | POST
 * @param {object} [query] - req.query (opcional)
 * @param {string} [phoneNumberId] - metadata.phone_number_id (opcional)
 * @param {string} [from] - message.from (opcional, pode mascarar em produção)
 * @param {string} [messageId] - message.id (opcional)
 * @param {string} [intentType] - intent.intent (opcional)
 * @param {string} [event] - ex.: "processed" | "skipped" | "loja_not_found"
 */
export function logWhatsAppWebhook(method, opts = {}) {
  const parts = ["[WhatsApp Webhook]", method];
  if (opts.phoneNumberId != null) parts.push("phone_number_id=" + String(opts.phoneNumberId));
  if (opts.from != null) parts.push("from=" + String(opts.from));
  if (opts.messageId != null) parts.push("message_id=" + String(opts.messageId));
  if (opts.intentType != null) parts.push("intent=" + String(opts.intentType));
  if (opts.event != null) parts.push("event=" + String(opts.event));
  if (opts.reason != null) parts.push("reason=" + String(opts.reason));
  console.log(parts.join(" "));
}
