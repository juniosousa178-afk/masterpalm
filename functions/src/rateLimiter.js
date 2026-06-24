/**
 * Rate Limiter e Idempotência para Cloud Functions MasterPalm
 *
 * Objetivo: Impedir abuso, evitar loops acidentais, controlar custos.
 * NÃO bloqueia uso legítimo.
 *
 * Uso:
 *   import { checkRateLimit, checkIdempotency } from './src/rateLimiter.js';
 */

import { HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

/** Lazy: evita getFirestore() antes de initializeApp() no deploy/analyze */
function getDb() {
  return getFirestore();
}

// ============================================================================
// LIMITES POR ENDPOINT (por minuto, por identificador)
// Valores generosos para uso legítimo; bloqueiam apenas abuso evidente
// ============================================================================

export const RATE_LIMITS = {
  // Frete: usuário pode consultar várias opções ao digitar CEP
  calcularCorreios: { maxPerMin: 30, windowMs: 60_000 },
  calcularMelhorEnvio: { maxPerMin: 30, windowMs: 60_000 },
  calcularFrenet: { maxPerMin: 30, windowMs: 60_000 },
  calcularSuperFrete: { maxPerMin: 30, windowMs: 60_000 },
  superFreteTestConnection: { maxPerMin: 20, windowMs: 60_000 },
  superFreteSaveConfig: { maxPerMin: 15, windowMs: 60_000 },
  superFreteGetConfigStatus: { maxPerMin: 40, windowMs: 60_000 },
  superFreteQuote: { maxPerMin: 40, windowMs: 60_000 },
  superFreteCreateCheckout: { maxPerMin: 20, windowMs: 60_000 },
  testarMelhorEnvioToken: { maxPerMin: 20, windowMs: 60_000 },

  // Pagamento: criar preferência é raro por sessão
  createPreference: { maxPerMin: 10, windowMs: 60_000 },
  planCreatePreference: { maxPerMin: 5, windowMs: 60_000 },

  // Cupom/número sorte: 1 por pedido finalizado
  gerarCupomNumeroSorte: { maxPerMin: 20, windowMs: 60_000 },

  // OAuth: fluxo humano, poucas tentativas
  mpOAuthInit: { maxPerMin: 15, windowMs: 60_000 },
  mpOAuthCallback: { maxPerMin: 15, windowMs: 60_000 },

  // Provisionamento: operação administrativa
  provisionSubdomain: { maxPerMin: 5, windowMs: 60_000 },

  // Webhooks Meta: podem receber bursts legítimos
  webhookWhatsApp: { maxPerMin: 120, windowMs: 60_000 },
  webhookInstagram: { maxPerMin: 120, windowMs: 60_000 },
  webhookMessenger: { maxPerMin: 120, windowMs: 60_000 },

  // Callable genérico (planos, etc)
  ensureUserPlan: { maxPerMin: 30, windowMs: 60_000 },
  activateUserTrial90d: { maxPerMin: 5, windowMs: 60_000 },
  cancelPlanRenewalAtPeriodEnd: { maxPerMin: 10, windowMs: 60_000 },
  reactivatePlanRenewal: { maxPerMin: 10, windowMs: 60_000 },
  createPlanSubscription: { maxPerMin: 5, windowMs: 60_000 },
  cancelPlanSubscription: { maxPerMin: 10, windowMs: 60_000 },
  reactivatePlanSubscription: { maxPerMin: 10, windowMs: 60_000 },
  syncPlanSubscription: { maxPerMin: 20, windowMs: 60_000 },
  /** Suporte root: leitura de snapshot de outra conta (sem escrita) */
  getPlanBillingSnapshotForSupport: { maxPerMin: 40, windowMs: 60_000 },
  /** Suporte root: forense leve catálogo MP (somente leitura) */
  getMpCatalogPaymentSupportSnapshot: { maxPerMin: 25, windowMs: 60_000 },

  /** Mestre planos: somente leitura (masterpalm26@gmail.com) */
  masterGetPlanAccessSummary: { maxPerMin: 15, windowMs: 60_000 },
  masterListUsersPlanAccess: { maxPerMin: 30, windowMs: 60_000 },
  masterGetUserPlanDetails: { maxPerMin: 40, windowMs: 60_000 },
  masterGrantCourtesyAccess: { maxPerMin: 20, windowMs: 60_000 },
  masterUpdateCourtesyAccess: { maxPerMin: 20, windowMs: 60_000 },
  masterRevokeCourtesyAccess: { maxPerMin: 20, windowMs: 60_000 },
  masterListPlanAuditActions: { maxPerMin: 30, windowMs: 60_000 },
  getMyPlanEffectiveAccess: { maxPerMin: 60, windowMs: 60_000 },

  // Cliente catálogo: perfil, carrinho, favoritos (uso legítimo frequente)
  getClienteCatalog: { maxPerMin: 60, windowMs: 60_000 },
  solicitarRedefinicaoSenhaCatalogo: { maxPerMin: 5, windowMs: 60_000 },
  girarRoletaCatalogo: { maxPerMin: 12, windowMs: 60_000 },

  // Domínio próprio catálogo (CNAME + catalog_domains)
  catalogDomainSubmitRequest: { maxPerMin: 12, windowMs: 60_000 },
  catalogDomainVerifyDns: { maxPerMin: 24, windowMs: 60_000 },

  /** Catálogo MP: por par loja+pedido (evita replay/spam na mesma ordem) */
  mpCatalogPayment: { maxPerMin: 8, windowMs: 60_000 },

  // IA loja: SEM rate limit (limite fica apenas nas APIs OpenAI/Gemini)
  // Endpoints removidos para evitar bloqueio indevido; usuários que pagam OpenAI não devem ser limitados pelo app.
};

const RATE_LIMIT_COL = "_rate_limits";
const IDEMPOTENCY_COL = "_idempotency";

// ============================================================================
// EXTRAIR IDENTIFICADOR (IP ou User ID)
// ============================================================================

/**
 * Obtém identificador para rate limit.
 * Prioridade: X-Forwarded-For (proxy) > X-Real-IP > conexão direta
 */
export function getClientIdentifier(req) {
  const forwarded = req?.headers?.["x-forwarded-for"];
  if (forwarded) {
    const first = String(forwarded).split(",")[0].trim();
    if (first) return first;
  }
  const realIp = req?.headers?.["x-real-ip"];
  if (realIp) return String(realIp).trim();
  // Callable: req.rawRequest existe
  const raw = req?.rawRequest;
  if (raw?.socket?.remoteAddress) return raw.socket.remoteAddress;
  return "unknown";
}

/**
 * Para Callable: mesmo que onRequest, mas com outra estrutura
 */
export function getCallableIdentifier(request) {
  const auth = request?.auth;
  if (auth?.uid) return `uid:${auth.uid}`;
  const raw = request?.rawRequest;
  if (raw?.headers?.["x-forwarded-for"]) {
    const first = String(raw.headers["x-forwarded-for"]).split(",")[0].trim();
    return first || "unknown";
  }
  if (raw?.socket?.remoteAddress) return raw.socket.remoteAddress;
  return "unknown";
}

// ============================================================================
// RATE LIMITING (Firestore)
// ============================================================================

/**
 * Verifica rate limit. Se excedido, lança HttpsError.
 *
 * @param {string} endpoint - Nome do endpoint (ex: "createPreference")
 * @param {string} identifier - IP ou uid
 * @returns {Promise<void>}
 */
export async function checkRateLimit(endpoint, identifier) {
  const config = RATE_LIMITS[endpoint];
  if (!config) return;

  const key = `${endpoint}:${identifier}`.replace(/[^a-zA-Z0-9_:.-]/g, "_");
  const ref = getDb().collection(RATE_LIMIT_COL).doc(key);

  const now = Date.now();
  const windowStart = now - config.windowMs;

  const doc = await ref.get();
  const data = doc.exists ? doc.data() : { count: 0, firstAt: now };

  // Reset se janela expirou
  if (data.firstAt < windowStart) {
    data.count = 0;
    data.firstAt = now;
  }

  data.count += 1;

  if (data.count > config.maxPerMin) {
    console.warn(`[rateLimit] Bloqueado: ${key} count=${data.count} max=${config.maxPerMin}`);
    throw new HttpsError(
      "resource-exhausted",
      `Muitas requisições. Tente novamente em alguns minutos.`,
      { retryAfter: 60 }
    );
  }

  await ref.set(
    {
      count: data.count,
      firstAt: data.firstAt,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// ============================================================================
// IDEMPOTÊNCIA (evita duplicação em retries)
// ============================================================================

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000; // 24h

/** TTL curto para reutilizar resposta MP sem nova cobrança (QR/link ainda válidos na prática). */
const IDEMPOTENCY_TTL_MP_CATALOG_MS = 10 * 60 * 1000; // 10 min

export function getIdempotencyTtlMs(endpoint) {
  if (endpoint === "mpCatalogPayment") return IDEMPOTENCY_TTL_MP_CATALOG_MS;
  return IDEMPOTENCY_TTL_MS;
}

/**
 * Verifica idempotência. Se a chave já foi processada, retorna o resultado salvo.
 *
 * @param {string} endpoint - Nome do endpoint
 * @param {string} idempotencyKey - Chave única (ex: orderId, pedidoId+clienteId)
 * @returns {Promise<{hit: boolean, result?: object}>}
 */
export async function checkIdempotency(endpoint, idempotencyKey) {
  if (!idempotencyKey || idempotencyKey.length > 128) {
    return { hit: false };
  }

  const safeKey = String(idempotencyKey).replace(/[^a-zA-Z0-9_-]/g, "_");
  const docId = `${endpoint}:${safeKey}`.slice(0, 150);

  const ref = getDb().collection(IDEMPOTENCY_COL).doc(docId);
  const doc = await ref.get();

  const ttlMs = getIdempotencyTtlMs(endpoint);

  if (doc.exists) {
    const data = doc.data() || {};
    const createdAt = data.createdAt?.toMillis?.() || 0;
    if (Date.now() - createdAt < ttlMs) {
      return { hit: true, result: data.result };
    }
    // TTL expirado: pode reprocessar
  }

  return { hit: false };
}

/**
 * Salva resultado para idempotência.
 *
 * @param {string} endpoint
 * @param {string} idempotencyKey
 * @param {object} result - Resposta a retornar em retries
 */
export async function saveIdempotency(endpoint, idempotencyKey, result) {
  if (!idempotencyKey || idempotencyKey.length > 128) return;

  const safeKey = String(idempotencyKey).replace(/[^a-zA-Z0-9_-]/g, "_");
  const docId = `${endpoint}:${safeKey}`.slice(0, 150);

  await getDb()
    .collection(IDEMPOTENCY_COL)
    .doc(docId)
    .set(
      {
        result,
        createdAt: FieldValue.serverTimestamp(),
        endpoint,
      },
      { merge: true }
    );
}
