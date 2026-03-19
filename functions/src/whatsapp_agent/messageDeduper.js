/**
 * Deduplicação in-memory por message.id para evitar envio duplicado em replay.
 * Sem estado persistido (Lote 1). TTL 60s; evict ao atingir limite de tamanho.
 */

const TTL_MS = 60_000;
const MAX_ENTRIES = 5000;

const seen = new Map();

function evictExpired() {
  const now = Date.now();
  for (const [key, ts] of seen.entries()) {
    if (now - ts > TTL_MS) seen.delete(key);
  }
}

/**
 * @param {string} messageId - message.id do payload Meta (opcional)
 * @returns {boolean} true se já processado (deve pular), false se novo (deve processar)
 */
export function isAlreadyProcessed(messageId) {
  if (typeof messageId !== "string" || !messageId.trim()) {
    return false;
  }
  const key = messageId.trim();
  const now = Date.now();
  if (seen.has(key)) {
    return true;
  }
  if (seen.size >= MAX_ENTRIES) {
    evictExpired();
  }
  seen.set(key, now);
  return false;
}
