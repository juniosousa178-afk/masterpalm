/**
 * Validação mínima do payload POST do webhook WhatsApp (Meta).
 * Usado apenas para endurecer o handler: rejeitar formato inválido
 * sem logar corpo da requisição.
 * Lote 1 - sem assinatura criptográfica.
 */

/**
 * @param {object} body - req.body do webhook
 * @returns {{ valid: boolean, reason?: string }}
 */
export function validateWhatsAppPostBody(body) {
  if (body == null || typeof body !== "object") {
    return { valid: false, reason: "body missing or not object" };
  }
  if (body.object !== "whatsapp_business_account") {
    return { valid: false, reason: "object not whatsapp_business_account" };
  }
  if (!Array.isArray(body.entry) || body.entry.length === 0) {
    return { valid: true, reason: "no entries" };
  }
  return { valid: true };
}

/**
 * Valida um bloco value (change.value) para garantir campos mínimos
 * antes de acessar metadata e messages.
 * @param {object} value - change.value
 * @returns {{ valid: boolean, phoneNumberId?: string }}
 */
export function validateWhatsAppChangeValue(value) {
  if (value == null || typeof value !== "object") {
    return { valid: false };
  }
  const phoneNumberId = value.metadata?.phone_number_id;
  if (typeof phoneNumberId !== "string" || !phoneNumberId.trim()) {
    return { valid: false };
  }
  if (!Array.isArray(value.messages)) {
    return { valid: false };
  }
  return { valid: true, phoneNumberId: phoneNumberId.trim() };
}

/**
 * Valida uma mensagem de texto para processamento (evitar acesso inseguro).
 * @param {object} message - item de value.messages
 * @returns {{ valid: boolean, from?: string, messageText?: string, messageId?: string }}
 */
export function validateTextMessage(message) {
  if (message == null || typeof message !== "object") {
    return { valid: false };
  }
  if (message.type !== "text") {
    return { valid: false };
  }
  const body = message.text?.body;
  if (typeof body !== "string") {
    return { valid: false };
  }
  const from = message.from;
  if (from == null || (typeof from !== "string" && typeof from !== "number")) {
    return { valid: false };
  }
  return {
    valid: true,
    from: String(from),
    messageText: body,
    messageId: typeof message.id === "string" ? message.id : undefined,
  };
}
