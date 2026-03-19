/**
 * Monta contexto factual mínimo por mensagem (Lote 1).
 * Não chama searchProducts para evitar dupla leitura e não alterar composeResponse.
 * Apenas empacota lojaId, intent e query para auditoria/telemetria futura.
 */

/**
 * @param {string} lojaId
 * @param {object} intent - resultado de classifyIntent
 * @param {string} messageText
 * @returns {{ lojaId: string, intent: object, messageText: string, query?: string }}
 */
export function buildMinimalFactualContext(lojaId, intent, messageText) {
  const context = {
    lojaId,
    intent,
    messageText,
  };
  if (intent && typeof intent.query === "string" && intent.query.trim()) {
    context.query = intent.query.trim();
  }
  return context;
}
