/* Cloud Functions v2 — Multilojas + Mercado Pago (Pedidos & Planos) + Subdomínios
   - Fretes (Correios, Melhor Envio, Frenet) + Skeleton PagSeguro / Ton / InfinitePay (ESM)
   - Node 20
   - Secrets via Secret Manager (defineSecret): MP_ACCESS_TOKEN, WEB_BASE_URL
   - Emulador/local pode usar .env (dotenv)
*/

import { onRequest, onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import crypto from "node:crypto";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as admin from "firebase-admin";

import { GoogleAuth } from "google-auth-library";
import * as dotenv from "dotenv";
import nodemailer from "nodemailer";
// xml2js: lazy load em calcularCorreios para reduzir cold start

// ✅ ESM import com extensão
import {
  ensureUserPlan,
  rootGrantPlan,
  activateUserTrial90d,
  cancelPlanRenewalAtPeriodEnd,
  reactivatePlanRenewal,
} from "./ensureUserPlan.js";
import { scheduledReconcileExpiredPaidPlans } from "./scheduledExpiredPaidDowngrade.js";
import {
  checkRateLimit,
  checkIdempotency,
  saveIdempotency,
  getClientIdentifier,
  getCallableIdentifier,
} from "./src/rateLimiter.js";
import { processMpWebhook } from "./src/mpWebhookHandler.js";
import {
  verifyMpCatalogWebhookNotification,
  MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS,
  MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS,
} from "./src/mpWebhookCatalogEdge.js";
import {
  resolveCatalogOrderForMp,
  isOrderPayableForMp,
  orderTotalToCents,
} from "./src/catalogMpOrderHelpers.js";
import {
  normalizeEmail,
  buildMpBuyerPayerForCatalog,
  resolveCatalogPixPayerForMp,
} from "./src/mpCatalogPayerBrasil.js";
import { stripPaymentsSecretsForPublic } from "./src/paymentsPublicStrip.js";
import { resolveStrictLojaMpAccessToken } from "./src/mpLojaTokenPolicy.js";
import {
  tryBeginMpCatalogPaymentOrReuse,
  commitMpCatalogPaymentSuccess,
  releaseMpCatalogPaymentLock,
} from "./src/mpCatalogPaymentLock.js";
import { buildMpCatalogProviderIdempotencyKey } from "./src/mpCatalogProviderIdempotencyKey.js";
import {
  emitCatalogPaymentLog,
  catalogPaymentCorrelationId,
  truncateProviderErrorText,
} from "./src/mpStructuredLogsMp.js";
import { runMpCatalogPaymentSupportSnapshot } from "./src/mpCatalogPaymentSupportRead.js";
import {
  generatePlanOrderId,
  PLAN_ORDERS_COL,
  tryProcessPlanOrderWebhook,
} from "./src/planOrdersWebhook.js";
import {
  validateMercadoPagoWebhookSignature,
  extractMercadoPagoWebhookDataId,
} from "./src/mercadoPagoWebhookSignature.js";
import {
  handlePreapprovalWebhookNotification,
  isRecurringPlanBillingEnabled,
  parseExternalReferenceMpRecurring,
  runCancelPlanSubscription,
  runCreatePlanSubscription,
  runReactivatePlanSubscription,
  runSyncPlanSubscription,
} from "./src/mpPlanRecurring.js";
import { runGetPlanBillingSnapshotForSupport } from "./src/planSupportRead.js";
import { writeOrderLojaIndex } from "./src/orderLojaIndex.js";
import {
  sugerirDescricaoProduto as aiSugerirDescricao,
  chatDicasLoja as aiChatDicas,
  sugerirTituloProduto as aiSugerirTitulo,
  sugerirVariacoesDescricao as aiSugerirVariacoesDescricao,
  sugerirLegendaInstagram as aiSugerirLegendaInstagram,
  sugerirMensagemWhatsApp as aiSugerirMensagemWhatsApp,
  sugerirCategoriaSubcategoria as aiSugerirCategoriaSubcategoria,
  sugerirPromocaoEstoqueParado as aiSugerirPromocaoEstoqueParado,
  analiseVendasNatural as aiAnaliseVendasNatural,
  chatAtendimentoCatalogo as aiChatAtendimentoCatalogo,
  sugerirPrecoCombo as aiSugerirPrecoCombo,
} from "./src/aiLoja.js";
import { runCatalogDomainSubmit, runCatalogDomainVerify } from "./src/catalogDomainWorkflow.js";
import { createOnPrePedidoClienteEmail } from "./src/pedidoClienteStatusEmail.js";

// ✅ Webhooks Canais Meta (WhatsApp, Instagram, Messenger)
export { webhookWhatsApp, webhookInstagram, webhookMessenger } from "./canaisMetaWebhooks.js";

// ✅ Thumbnails automáticos (Storage: produtos)
export { generateProductThumbnail } from "./src/generateProductThumbnail.js";

dotenv.config();

// ---------- Secrets (Secret Manager) ----------
const S_MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");
const S_MP_WEBHOOK_SECRET = defineSecret("MP_WEBHOOK_SECRET");
const S_WEB_BASE_URL = defineSecret("WEB_BASE_URL");
const S_MP_APP_ID = defineSecret("MP_APP_ID");
const S_MP_CLIENT_SECRET = defineSecret("MP_CLIENT_SECRET");
const S_SMTP_EMAIL = defineSecret("SMTP_EMAIL");
const S_SMTP_PASSWORD = defineSecret("SMTP_PASSWORD");
const S_OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const S_GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// ---------- Opções globais ----------
setGlobalOptions({
  region: "southamerica-east1",
  maxInstances: 10,
  secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL],
});

// Firebase Admin
initializeApp();
const db = getFirestore();
const nowTs = FieldValue.serverTimestamp();

// ============================== ENV / CONFIG ================================
const MP_PUBLIC_KEY = process.env.MP_PUBLIC_KEY || null; // opcional (front)
const WEBHOOK_URL = process.env.WEBHOOK_URL || ""; // opcional (fallback)
const ROOT_DOMAIN = process.env.ROOT_DOMAIN || "mastepalm.com.br";
/** Site público / hosting (OAuth, return URLs). Subdomínios de loja continuam em [ROOT_DOMAIN]. */
const PUBLIC_SITE_ORIGIN = process.env.PUBLIC_SITE_ORIGIN || "https://app.mastepalm.com.br";
const HOSTING_SITE_ID = process.env.HOSTING_SITE_ID || "";
const PROJECT_ID = process.env.PROJECT_ID || "";
const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const COLLECTION_CLIENTES = "clientes";
const COLLECTION_CLIENTES_PORTAL = "clientes_portal";
const COLLECTION_PEDIDO_STATUS_PUBLICO = "pedido_status_publico";

function maskTokenForAudit(token) {
  const t = String(token || "").trim();
  if (!t) return "empty";
  if (t.length <= 10) return `${t[0] || "*"}***(${t.length})`;
  return `${t.slice(0, 6)}…${t.slice(-4)}(${t.length})`;
}

async function getPlatformMpAccessTokenStrict({ flow }) {
  const token = String((await S_MP_ACCESS_TOKEN.value()) || "").trim();
  if (!token) {
    console.error(
      JSON.stringify({
        evt: "mp_platform_token_missing",
        flow,
        credentialScope: "platform",
        source: "secret_manager",
      }),
    );
    return { ok: false, token: "" };
  }
  console.log(
    JSON.stringify({
      evt: "mp_platform_token_resolved",
      flow,
      credentialScope: "platform",
      source: "secret_manager",
      tokenMasked: maskTokenForAudit(token),
    }),
  );
  return { ok: true, token };
}

function hasStoreContextInPlanPayload(payload) {
  if (!payload || typeof payload !== "object") return false;
  const keys = [
    "lojaId",
    "storeId",
    "tenantId",
    "mpAccessToken",
    "accessToken",
    "mpToken",
    "payments",
    "payments_public",
  ];
  return keys.some((k) => payload[k] != null && String(payload[k]).trim() !== "");
}

// ============================== HELPERS GERAIS ==============================
function corsWrap(handler) {
  return async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, x-internal-token");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (req.method === "OPTIONS") return res.status(204).send("");
    return handler(req, res);
  };
}

function validSubdomain(s) {
  return /^[a-z0-9-]{3,63}$/.test(s || "");
}

function normalizeOptionalString(value) {
  const resolved = value == null ? "" : String(value).trim();
  return resolved.length > 0 ? resolved : null;
}

/** Código curto para exibir no assunto (8 primeiros caracteres do id). */
function pedidoCodigoCurto(pedidoId) {
  const s = String(pedidoId || "");
  if (s.length >= 8) return s.slice(0, 8).toUpperCase();
  return s.toUpperCase();
}

/** Texto com lista de itens para o e-mail do vendedor. */
function formatPrePedidoItensResumoEmail(itens) {
  if (!Array.isArray(itens) || itens.length === 0) {
    return "  (detalhe completo no app)\n";
  }
  const lines = [];
  for (const it of itens) {
    if (!it || typeof it !== "object") continue;
    const q = Math.max(1, Number(it.quantidade ?? it.qty ?? 1) || 1);
    const nome = String(it.nome ?? it.name ?? "Item").trim() || "Item";
    const pu = Number(it.precoUnitario ?? it.preco ?? 0) || 0;
    let tot = it.total != null && it.total !== "" ? Number(it.total) : Number.NaN;
    if (!Number.isFinite(tot)) tot = pu * q;
    const t = String(it.tamanho ?? it.size ?? "").trim();
    const varN = t ? ` - ${t}` : "";
    const totStr = tot.toFixed(2).replace(".", ",");
    lines.push(`  ${q}x ${nome}${varN} — R$ ${totStr}`);
  }
  return lines.length > 0 ? lines.join("\n") : "  (detalhe completo no app)\n";
}

function createPortalToken() {
  return crypto.randomBytes(24).toString("base64url");
}

function buildPedidoStatusPublico(lojaId, pedidoId, data = {}) {
  const itens = Array.isArray(data.itens) ? data.itens : [];
  const itensResumo = itens
    .map((item) => ({
      nome: normalizeOptionalString(item?.nome) || "",
      quantidade: Number(item?.quantidade) || 1,
    }))
    .filter((item) => item.nome.length > 0);

  const frete = data.frete && typeof data.frete === "object" ? data.frete : {};
  const payload = {
    pedidoId: String(pedidoId || ""),
    lojaId: String(lojaId || ""),
    status: normalizeOptionalString(data.status) || "pendente",
    dataCriacao: data.dataCriacao || nowTs,
    dataAtualizacao: data.dataAtualizacao || nowTs,
    total: Number(data.total) || 0,
    itensResumo,
  };

  const codigoRastreio = normalizeOptionalString(
    data.codigoRastreio || data.codigo_rastreio || data.rastreio,
  );
  const freteNome = normalizeOptionalString(data.freteNome || frete.nome);

  if (codigoRastreio) payload.codigoRastreio = codigoRastreio;
  if (freteNome) payload.freteNome = freteNome;

  return payload;
}

function sanitizeEndereco(endereco) {
  if (!endereco || typeof endereco !== "object") return null;
  const allowedKeys = [
    "cep",
    "rua",
    "numero",
    "bairro",
    "cidade",
    "estado",
    "complemento",
    "logradouro",
    "street",
    "postalCode",
  ];
  const result = {};
  for (const key of allowedKeys) {
    const value = endereco[key];
    if (value == null) continue;
    const resolved = typeof value === "string" ? value.trim() : value;
    if (resolved === "" || resolved == null) continue;
    result[key] = resolved;
  }
  return Object.keys(result).length > 0 ? result : null;
}

async function resolveClientePortalTarget(lojaId, pedidoData = {}) {
  const cliente = pedidoData.cliente && typeof pedidoData.cliente === "object"
    ? pedidoData.cliente
    : {};

  let clienteDoc = null;
  const clienteId = normalizeOptionalString(cliente.id);
  const clienteEmail = normalizeEmail(cliente.email);
  const portalTokenFromPedido = normalizeOptionalString(cliente.portalToken);

  if (clienteId) {
    const snap = await db
      .collection(COLLECTION_LOJAS)
      .doc(lojaId)
      .collection(COLLECTION_CLIENTES)
      .doc(clienteId)
      .get();
    if (snap.exists) {
      clienteDoc = { id: snap.id, ref: snap.ref, data: snap.data() || {} };
    }
  }

  if (!clienteDoc && clienteEmail) {
    const snapshot = await db
      .collection(COLLECTION_LOJAS)
      .doc(lojaId)
      .collection(COLLECTION_CLIENTES)
      .where("email", "==", clienteEmail)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      const snap = snapshot.docs[0];
      clienteDoc = { id: snap.id, ref: snap.ref, data: snap.data() || {} };
    }
  }

  // Usar portalToken do pedido (app passou da sessão) quando não encontrou cliente em clientes
  if (!clienteDoc && portalTokenFromPedido && clienteEmail) {
    console.log("[resolveClientePortalTarget] Usando portalToken do pedido (cliente não em clientes, email=" + clienteEmail + ")");
    return {
      clienteId: clienteId || "",
      portalToken: portalTokenFromPedido,
      clienteData: {},
    };
  }

  if (!clienteDoc) return null;

  let portalToken = normalizeOptionalString(clienteDoc.data.portalToken) || portalTokenFromPedido;
  if (!portalToken) {
    portalToken = createPortalToken();
    await clienteDoc.ref.set({ portalToken }, { merge: true });
    clienteDoc.data.portalToken = portalToken;
  }

  return {
    clienteId: clienteDoc.id,
    portalToken,
    clienteData: clienteDoc.data,
  };
}

function buildClientePortalPedido(lojaId, pedidoId, data = {}) {
  return buildPedidoStatusPublico(lojaId, pedidoId, data);
}

async function upsertClientePortalFromPedido(lojaId, pedidoId, pedidoData = {}) {
  const target = await resolveClientePortalTarget(lojaId, pedidoData);
  if (!target) return null;

  const cliente = pedidoData.cliente && typeof pedidoData.cliente === "object"
    ? pedidoData.cliente
    : {};
  const endereco = sanitizeEndereco(cliente.endereco || target.clienteData.endereco);
  const enderecoFormatado = normalizeOptionalString(
    cliente.enderecoFormatado || target.clienteData.enderecoFormatado,
  );

  const portalRef = db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection(COLLECTION_CLIENTES_PORTAL)
    .doc(target.portalToken);

  await portalRef.set(
    {
      lojaId,
      clienteId: target.clienteId,
      dataAtualizacao: nowTs,
      ...(endereco ? { ultimoEndereco: endereco } : {}),
      ...(enderecoFormatado ? { ultimoEnderecoFormatado: enderecoFormatado } : {}),
    },
    { merge: true },
  );

  await portalRef
    .collection("pedidos")
    .doc(pedidoId)
    .set(buildClientePortalPedido(lojaId, pedidoId, pedidoData), { merge: false });

  return {
    portalToken: target.portalToken,
    clienteId: target.clienteId,
  };
}

async function syncClientePortalFromCliente(lojaId, clienteId, clienteData = {}) {
  let portalToken = normalizeOptionalString(clienteData.portalToken);
  const clienteRef = db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection(COLLECTION_CLIENTES)
    .doc(clienteId);

  if (!portalToken) {
    portalToken = createPortalToken();
    await clienteRef.set({ portalToken }, { merge: true });
  }

  const endereco = sanitizeEndereco(clienteData.endereco);
  const enderecoFormatado = normalizeOptionalString(clienteData.enderecoFormatado);

  await db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection(COLLECTION_CLIENTES_PORTAL)
    .doc(portalToken)
    .set(
      {
        lojaId,
        clienteId,
        dataAtualizacao: nowTs,
        ...(endereco ? { ultimoEndereco: endereco } : {}),
        ...(enderecoFormatado ? { ultimoEnderecoFormatado: enderecoFormatado } : {}),
      },
      { merge: true },
    );

  return portalToken;
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

/** fetch com timeout (evita espera infinita em APIs lentas) */
async function fetchWithTimeout(url, opts = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...opts, signal: controller.signal });
    clearTimeout(id);
    return res;
  } catch (e) {
    clearTimeout(id);
    if (e.name === "AbortError") throw new Error(`Request timeout after ${timeoutMs}ms`);
    throw e;
  }
}


function addDays(d, n) {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}
function addMonths(d, n) {
  const x = new Date(d);
  x.setMonth(x.getMonth() + n);
  return x;
}
function addYears(d, n) {
  const x = new Date(d);
  x.setFullYear(x.getFullYear() + n);
  return x;
}

// ============================== CONFIG DE PAGAMENTO POR LOJA ==================
/**
 * Lê a configuração de pagamento da loja (MP):
 * /lojas/{lojaId}/config/payments
 *  - mp_access_token: string (obrigatório pra loja receber)
 *  - mp_public_key: string (opcional, exibição no front)
 *
 * Fluxos **pedido/catálogo** (createPreference, mpCatalogPayment) usam
 * [resolveStrictLojaMpAccessToken] — **sem** fallback para MP_ACCESS_TOKEN global.
 * Planos/billing da plataforma usam token estrito da plataforma (Secret Manager).
 */
async function getLojaPaymentConfig(lojaId) {
  try {
    const doc = await db
      .collection(COLLECTION_LOJAS)
      .doc(String(lojaId))
      .collection("config")
      .doc("payments")
      .get();

    const data = doc.exists ? (doc.data() || {}) : {};
    // OAuth: mp.access_token | mp.token | legado: mp_access_token
    const lojaToken = (data.mp?.access_token || data.mp?.token || data.mp_access_token || "").trim();
    const lojaPubKey = data.mp?.public_key || data.mp_public_key || null;

    return { token: lojaToken || null, publicKey: lojaPubKey || null };
  } catch (e) {
    console.error("[getLojaPaymentConfig] erro:", e);
    return { token: null, publicKey: null };
  }
}

/**
 * Lê a configuração COMPLETA de pagamentos (MP + PagSeguro + Ton + InfinitePay)
 * /lojas/{lojaId}/config/payments
 */
async function getLojaPaymentsRaw(lojaId) {
  try {
    const doc = await db
      .collection(COLLECTION_LOJAS)
      .doc(String(lojaId))
      .collection("config")
      .doc("payments")
      .get();

    return doc.exists ? (doc.data() || {}) : {};
  } catch (e) {
    console.error("[getLojaPaymentsRaw] erro:", e);
    return {};
  }
}

async function canManageStoreConfigServerSide({ lojaId, uid, email }) {
  const emailNorm = String(email || "").trim().toLowerCase();
  if (!uid) return false;
  if (ROOT_EMAILS.has(emailNorm)) return true;

  const lojaRef = db.collection(COLLECTION_LOJAS).doc(String(lojaId));
  const [lojaSnap, userSnap, memberSnap] = await Promise.all([
    lojaRef.get(),
    db.collection("users").doc(String(uid)).get(),
    lojaRef.collection("members").doc(String(uid)).get(),
  ]);

  const lojaData = lojaSnap.exists ? (lojaSnap.data() || {}) : {};
  if (String(lojaData.ownerUid || "") === String(uid)) {
    return true;
  }

  const userData = userSnap.exists ? (userSnap.data() || {}) : {};
  const storeId = String(userData.store_id || userData.storeId || "").trim();
  if (storeId && storeId === String(lojaId)) {
    if (!lojaData.ownerUid || String(lojaData.ownerUid) === String(uid)) {
      return true;
    }
  }

  if (memberSnap.exists) {
    const role = String((memberSnap.data() || {}).role || "").trim().toLowerCase();
    if (role === "owner" || role === "admin") return true;
  }

  return false;
}

// ============================================================================
// MERCADO PAGO – OAuth (Conectar com 1 clique)
// ============================================================================

const MP_AUTH_URL = "https://auth.mercadopago.com/authorization";
const MP_TOKEN_URL = "https://api.mercadopago.com/oauth/token";
const MP_OAUTH_STATE_COL = "_mp_oauth_states";
const MP_OAUTH_STATE_TTL_MS = 15 * 60 * 1000;

/** RFC 7636 PKCE — obrigatório quando a aplicação MP está com PKCE ativado. */
function generateMpPkcePair() {
  const codeVerifier = crypto.randomBytes(32).toString("base64url");
  const codeChallenge = crypto.createHash("sha256").update(codeVerifier).digest("base64url");
  return { codeVerifier, codeChallenge };
}

function mapMpOAuthExchangeError(msgRaw) {
  const msg = String(msgRaw || "").toLowerCase();
  if (msg.includes("state inválido") || msg.includes("state invalido") || msg.includes("state")) {
    return "State inválido ou expirado.";
  }
  if (msg.includes("código") || msg.includes("code")) {
    return "Código de autorização ausente ou inválido.";
  }
  if (msg.includes("token") || msg.includes("mercado pago")) {
    return "Falha de comunicação com o Mercado Pago.";
  }
  return "Falha de comunicação com o servidor.";
}

/**
 * Inicia o fluxo OAuth do Mercado Pago.
 * GET ?lojaId=xxx → redireciona para o Mercado Pago para autorização.
 */
export const mpOAuthInit = onRequest(
  { secrets: [S_MP_APP_ID], cors: true },
  async (req, res) => {
    const lojaId = (req.query.lojaId || "").toString().trim();
    if (!lojaId) {
      res.status(400).send(
        "<html><body><h1>Erro</h1><p>Parâmetro lojaId obrigatório.</p></body></html>"
      );
      return;
    }

    const secretAppIdRaw = await S_MP_APP_ID.value();
    const envAppIdRaw = process.env.MP_APP_ID;
    const appId = secretAppIdRaw || envAppIdRaw;
    const appIdStr = String(appId || "").trim();
    const appIdMasked = appIdStr
      ? (appIdStr.length <= 8
          ? `${appIdStr.slice(0, 1)}***${appIdStr.slice(-1)}`
          : `${appIdStr.slice(0, 4)}***${appIdStr.slice(-4)}`)
      : "empty";
    const appIdSource = secretAppIdRaw ? "S_MP_APP_ID.value()" : (envAppIdRaw ? "process.env.MP_APP_ID" : "fallback");
    if (!appId) {
      console.error("[mpOAuthInit] MP_APP_ID não configurado");
      res.status(500).send(
        "<html><body><h1>Erro de configuração</h1><p>OAuth não configurado. Configure MP_APP_ID.</p></body></html>"
      );
      return;
    }

    // URL no domínio próprio (preferida pelo MP) ou fallback Cloud Functions
    const callbackUrl = `${PUBLIC_SITE_ORIGIN}/mp-oauth-callback`;
    const nonce = crypto.randomBytes(24).toString("base64url");
    const issuedAt = Date.now();
    const expiresAt = issuedAt + MP_OAUTH_STATE_TTL_MS;
    const { codeVerifier, codeChallenge } = generateMpPkcePair();
    await db.collection(MP_OAUTH_STATE_COL).doc(nonce).set({
      lojaId: String(lojaId),
      createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(expiresAt),
      used: false,
      code_verifier: codeVerifier,
    });
    const state = Buffer.from(
      JSON.stringify({ l: String(lojaId), n: nonce, t: issuedAt })
    ).toString("base64url");

    const params = new URLSearchParams({
      client_id: appId,
      response_type: "code",
      platform_id: "mp",
      state,
      redirect_uri: callbackUrl,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
    });

    const authUrl = `${MP_AUTH_URL}?${params.toString()}`;
    const authUrlDiag = authUrl.replace(
      `client_id=${encodeURIComponent(appIdStr)}`,
      `client_id=${encodeURIComponent(appIdMasked)}`
    );
    const authorizeHost = (() => {
      try {
        return new URL(authUrl).host;
      } catch (_) {
        return "invalid_url";
      }
    })();
    console.log(`[MP_OAUTH_DIAG] public_site_origin=${PUBLIC_SITE_ORIGIN}`);
    console.log(`[MP_OAUTH_DIAG] redirect_uri=${callbackUrl}`);
    console.log(`[MP_OAUTH_DIAG] client_id_masked=${appIdMasked}`);
    console.log(`[MP_OAUTH_DIAG] app_id_source=${appIdSource}`);
    console.log(`[MP_OAUTH_DIAG] authorize_host=${authorizeHost}`);
    console.log(`[MP_OAUTH_DIAG] code_challenge_generated=${codeChallenge ? "true" : "false"}`);
    console.log(`[MP_OAUTH_DIAG] authorization_url_masked=${authUrlDiag}`);
    res.redirect(302, authUrl);
  }
);

/**
 * Troca code OAuth por token de forma segura.
 * Espera POST JSON com { code, state }.
 */
export const mpOAuthExchangeCode = onRequest(
  { secrets: [S_MP_APP_ID, S_MP_CLIENT_SECRET], cors: true },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Método não permitido." });
      return;
    }

    const body = req.body && typeof req.body === "object" ? req.body : {};
    const code = (body.code || "").toString().trim();
    const state = (body.state || "").toString().trim();
    if (!code || !state) {
      res.status(400).json({ error: "Parâmetros code/state obrigatórios." });
      return;
    }

    let parsedState;
    try {
      parsedState = JSON.parse(Buffer.from(state, "base64url").toString("utf8"));
    } catch (e) {
      console.error("[mpOAuthExchangeCode] state inválido");
      res.status(400).json({ error: "State inválido." });
      return;
    }

    const lojaId = String(parsedState?.l || "").trim();
    const nonce = String(parsedState?.n || "").trim();
    const stateIssuedAt = Number(parsedState?.t || 0);
    if (!lojaId || !nonce || !Number.isFinite(stateIssuedAt)) {
      res.status(400).json({ error: "State malformado." });
      return;
    }

    const stateRef = db.collection(MP_OAUTH_STATE_COL).doc(nonce);
    const now = Date.now();
    const expiredByPayload = now - stateIssuedAt > MP_OAUTH_STATE_TTL_MS + 30_000;
    if (expiredByPayload) {
      res.status(400).json({ error: "State inválido ou expirado." });
      return;
    }
    // Consumo atômico e de uso único real (anti replay/race).
    await db.runTransaction(async (tx) => {
      const stateSnap = await tx.get(stateRef);
      if (!stateSnap.exists) {
        throw new Error("state_not_found");
      }
      const stateData = stateSnap.data() || {};
      const expMs =
        stateData.expiresAt && typeof stateData.expiresAt.toMillis === "function"
          ? stateData.expiresAt.toMillis()
          : null;
      const stateLoja = String(stateData.lojaId || "").trim();
      const stateUsed = stateData.used === true;
      const expiredByDoc = expMs != null && now > expMs;
      if (stateUsed || expiredByDoc || stateLoja !== lojaId) {
        throw new Error("state_invalid");
      }
      tx.set(
        stateRef,
        {
          used: true,
          usedAt: Timestamp.now(),
          consumedBy: "mpOAuthExchangeCode",
        },
        { merge: true }
      );
    }).catch((e) => {
      const msg = String(e?.message || "");
      if (msg === "state_not_found" || msg === "state_invalid") {
        throw new HttpsError("invalid-argument", "State inválido ou expirado.");
      }
      throw e;
    });

    const stateSnapAfter = await stateRef.get();
    const codeVerifierForToken = String(
      (stateSnapAfter.exists ? stateSnapAfter.data() || {} : {}).code_verifier || ""
    ).trim();

    const appId = (await S_MP_APP_ID.value()) || process.env.MP_APP_ID;
    const clientSecret = (await S_MP_CLIENT_SECRET.value()) || process.env.MP_CLIENT_SECRET;
    if (!appId || !clientSecret) {
      console.error("[mpOAuthExchangeCode] Credenciais OAuth não configuradas");
      res.status(500).json({ error: "OAuth não configurado no servidor." });
      return;
    }

    try {
      const callbackUrl = `${PUBLIC_SITE_ORIGIN}/mp-oauth-callback`;
      const tokenPayload = {
        client_id: appId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
        redirect_uri: callbackUrl,
      };
      if (codeVerifierForToken) {
        tokenPayload.code_verifier = codeVerifierForToken;
      }
      const tokenResp = await fetch(MP_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(tokenPayload),
        signal: AbortSignal.timeout(12000),
      });
      const tokenData = await tokenResp.json();
      if (!tokenResp.ok) {
        const msg = tokenData?.message || tokenData?.error_description || "Falha ao obter token.";
        console.error("[mpOAuthExchangeCode] Falha troca code:", tokenResp.status);
        res.status(400).json({ error: mapMpOAuthExchangeError(msg) });
        return;
      }

      const accessToken = tokenData?.access_token;
      const refreshToken = tokenData?.refresh_token || null;
      const publicKey = tokenData?.public_key || null;
      const userId = tokenData?.user_id != null ? String(tokenData.user_id) : null;
      if (!accessToken) {
        res.status(400).json({ error: "Mercado Pago não retornou access_token." });
        return;
      }

      let email = null;
      try {
        const userResp = await fetch("https://api.mercadopago.com/users/me", {
          headers: { Authorization: `Bearer ${accessToken}` },
          signal: AbortSignal.timeout(8000),
        });
        if (userResp.ok) {
          const userData = await userResp.json();
          email = userData?.email ?? null;
        }
      } catch (e) {
        console.warn("[mpOAuthExchangeCode] users/me indisponível");
      }

      const nowTs = FieldValue.serverTimestamp();
      await db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("config")
        .doc("payments")
        .set(
          {
            mp: {
              access_token: accessToken,
              token: accessToken,
              refresh_token: refreshToken,
              public_key: publicKey,
              user_id: userId,
              email,
              connected: true,
            },
            updatedAt: nowTs,
          },
          { merge: true }
        );

      await db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("config")
        .doc("payments_public")
        .set(
          {
            mp: {
              public_key: publicKey,
              user_id: userId,
              email,
              connected: true,
            },
            updatedAt: nowTs,
          },
          { merge: true }
        );

      console.log("[mpOAuthExchangeCode] MP conectado para loja:", lojaId);
      res.status(200).json({ ok: true, lojaId, connected: true });
    } catch (e) {
      if (e instanceof HttpsError && e.code === "invalid-argument") {
        res.status(400).json({ error: "State inválido ou expirado." });
        return;
      }
      console.error("[mpOAuthExchangeCode] erro interno:", e?.message || e);
      res.status(500).json({ error: "Erro interno ao conectar Mercado Pago." });
    }
  }
);

/**
 * Healthcheck mínimo OAuth MP: valida token salvo da loja via GET /users/me.
 * Não retorna segredos; apenas status seguro para UI.
 */
export const mpOAuthHealthcheck = onCall(
  { timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login para validar a conexão.");
    }

    const lojaId = String(request.data?.lojaId || "").trim();
    if (!lojaId) {
      throw new HttpsError("invalid-argument", "lojaId é obrigatório.");
    }

    const allowed = await canManageStoreConfigServerSide({
      lojaId,
      uid: request.auth.uid,
      email: request.auth.token?.email || "",
    });
    if (!allowed) {
      throw new HttpsError("permission-denied", "Sem permissão para validar esta loja.");
    }

    const payments = await getLojaPaymentsRaw(lojaId);
    const mp = payments?.mp && typeof payments.mp === "object" ? payments.mp : {};
    const accessToken = String(mp.access_token || mp.token || "").trim();
    if (!accessToken) {
      return {
        ok: false,
        connected: false,
        message: "Loja sem token Mercado Pago salvo.",
      };
    }

    try {
      const userResp = await fetch("https://api.mercadopago.com/users/me", {
        method: "GET",
        headers: { Authorization: `Bearer ${accessToken}` },
        signal: AbortSignal.timeout(10000),
      });

      if (!userResp.ok) {
        const bodyText = await userResp.text();
        const msg = userResp.status === 401 || userResp.status === 403
          ? "Token Mercado Pago inválido ou expirado."
          : "Não foi possível validar com o Mercado Pago.";
        console.warn(
          `[mpOAuthHealthcheck] MP users/me status=${userResp.status} loja=${lojaId} uid=${request.auth.uid}`
        );
        return {
          ok: false,
          connected: false,
          message: msg,
          mpStatusCode: userResp.status,
          mpError: String(bodyText || "").slice(0, 120),
        };
      }

      const userData = await userResp.json();
      return {
        ok: true,
        connected: true,
        mp_user_id: userData?.id != null ? String(userData.id) : null,
        nickname: userData?.nickname ? String(userData.nickname) : null,
        email: userData?.email ? String(userData.email) : null,
        message: "Conexão validada com sucesso.",
      };
    } catch (e) {
      console.warn(
        `[mpOAuthHealthcheck] falha comunicação loja=${lojaId} uid=${request.auth.uid} type=${e?.name || typeof e}`
      );
      return {
        ok: false,
        connected: false,
        message: "Falha de comunicação ao validar com o Mercado Pago.",
      };
    }
  }
);

/**
 * Callback OAuth do Mercado Pago.
 * Recebe ?code=xxx&state=xxx, troca por access_token, salva no Firestore e redireciona.
 */
export const mpOAuthCallback = onRequest(
  { secrets: [S_MP_APP_ID, S_MP_CLIENT_SECRET], cors: true },
  async (req, res) => {
    const code = (req.query.code || "").toString().trim();
    const state = (req.query.state || "").toString().trim();
    const errorParam = req.query.error;

    if (errorParam) {
      console.error("[mpOAuthCallback] MP retornou erro:", errorParam, req.query.error_description);
      res.redirect(
        302,
        `${PUBLIC_SITE_ORIGIN}/loja?mp_oauth=error&msg=${encodeURIComponent(String(req.query.error_description || errorParam))}`
      );
      return;
    }

    if (!code || !state) {
      res.status(400).send(
        "<html><body><h1>Erro</h1><p>Código de autorização não recebido.</p></body></html>"
      );
      return;
    }

    let lojaId;
    try {
      const decoded = JSON.parse(Buffer.from(state, "base64url").toString("utf8"));
      lojaId = decoded.lojaId;
    } catch (e) {
      console.error("[mpOAuthCallback] state inválido:", e);
      res.status(400).send(
        "<html><body><h1>Erro</h1><p>Estado inválido.</p></body></html>"
      );
      return;
    }

    const appId = (await S_MP_APP_ID.value()) || process.env.MP_APP_ID;
    const clientSecret = (await S_MP_CLIENT_SECRET.value()) || process.env.MP_CLIENT_SECRET;

    if (!appId || !clientSecret) {
      console.error("[mpOAuthCallback] Credenciais OAuth não configuradas");
      res.status(500).send(
        "<html><body><h1>Erro</h1><p>OAuth não configurado. Configure MP_APP_ID e MP_CLIENT_SECRET.</p></body></html>"
      );
      return;
    }

    // URL no domínio próprio (preferida pelo MP) ou fallback Cloud Functions
    const callbackUrl = `${PUBLIC_SITE_ORIGIN}/mp-oauth-callback`;

    try {
      const tokenResp = await fetch(MP_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: appId,
          client_secret: clientSecret,
          code,
          grant_type: "authorization_code",
          redirect_uri: callbackUrl,
          test_token: "false",
        }),
      });

      const tokenData = await tokenResp.json();

      if (!tokenResp.ok) {
        console.error("[mpOAuthCallback] Erro ao trocar código:", tokenResp.status, tokenData);
        const msg = tokenData.message || tokenData.error_description || "Falha ao obter token";
        res.redirect(
          302,
          `${PUBLIC_SITE_ORIGIN}/loja?mp_oauth=error&msg=${encodeURIComponent(String(msg))}`
        );
        return;
      }

      const accessToken = tokenData.access_token;
      const refreshToken = tokenData.refresh_token;
      const publicKey = tokenData.public_key;
      const userId = tokenData.user_id;

      if (!accessToken) {
        console.error("[mpOAuthCallback] access_token não retornado");
        res.redirect(302, `${PUBLIC_SITE_ORIGIN}/loja?mp_oauth=error&msg=Token+nao+retornado`);
        return;
      }

      // Buscar email do usuário MP
      let email = null;
      try {
        const userResp = await fetch("https://api.mercadopago.com/users/me", {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        if (userResp.ok) {
          const userData = await userResp.json();
          email = userData?.email ?? null;
        }
      } catch (e) {
        console.warn("[mpOAuthCallback] Não foi possível obter email:", e.message);
      }

      const paymentsRef = db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("config")
        .doc("payments");

      await paymentsRef.set(
        {
          mp: {
            access_token: accessToken,
            token: accessToken,
            refresh_token: refreshToken || null,
            public_key: publicKey || accessToken,
            user_id: userId ? String(userId) : null,
            email: email || null,
            connected: true,
          },
          updatedAt: nowTs,
        },
        { merge: true }
      );

      const paymentsPublicRef = db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("config")
        .doc("payments_public");
      await paymentsPublicRef.set(
        {
          mp: {
            public_key: publicKey || null,
            user_id: userId ? String(userId) : null,
            email: email || null,
            connected: true,
          },
          updatedAt: nowTs,
        },
        { merge: true }
      );

      console.log("[mpOAuthCallback] MP conectado para loja:", lojaId);

      res.redirect(
        302,
        `${PUBLIC_SITE_ORIGIN}/loja?mp_oauth=ok&loja=${encodeURIComponent(lojaId)}`
      );
    } catch (e) {
      console.error("[mpOAuthCallback] Erro:", e);
      res.redirect(
        302,
        `${PUBLIC_SITE_ORIGIN}/loja?mp_oauth=error&msg=${encodeURIComponent(e.message || "Erro")}`
      );
    }
  }
);

// ============================================================================
// FRETES – Correios / Melhor Envio / Frenet  (CALLABLE v2)
// ============================================================================

export const calcularCorreios = onCall(
  { timeoutSeconds: 25, memory: "256MiB" },
  async (request) => {
  try {
    const identifier = getCallableIdentifier(request);
    await checkRateLimit("calcularCorreios", identifier);

    const {
      cepOrigem,
      cepDestino,
      peso,
      altura,
      largura,
      comprimento,
      declararValor,
      valorDeclarado,
      codigo,
    } = request.data || {};

    if (!cepOrigem || !cepDestino || !peso) {
      throw new HttpsError(
        "invalid-argument",
        "Parâmetros insuficientes para calcular frete Correios."
      );
    }

    // "sedex"/"pac" => códigos oficiais
    let nCdServico = "04014"; // SEDEX
    if ((codigo || "").toLowerCase() === "pac") nCdServico = "04510"; // PAC

    const params = new URLSearchParams({
      nCdEmpresa: "",
      sDsSenha: "",
      nCdServico,
      sCepOrigem: String(cepOrigem),
      sCepDestino: String(cepDestino),
      nVlPeso: String(peso),
      nCdFormato: "1",
      nVlComprimento: String(comprimento),
      nVlAltura: String(altura),
      nVlLargura: String(largura),
      nVlDiametro: "0",
      sCdMaoPropria: "N",
      nVlValorDeclarado: declararValor ? String(valorDeclarado || 0) : "0",
      sCdAvisoRecebimento: "N",
      StrRetorno: "xml",
    });

    const url = `http://ws.correios.com.br/calculador/CalcPrecoPrazo.aspx?${params.toString()}`;

    const resp = await fetchWithTimeout(url, { method: "GET" }, 18000);
    if (!resp.ok) {
      const txt = await resp.text();
      console.error("[calcularCorreios] HTTP error:", resp.status, txt);
      throw new HttpsError("internal", "Erro ao consultar frete dos Correios.");
    }

    const xml = await resp.text();
    const { parseStringPromise } = await import("xml2js");
    const parsed = await parseStringPromise(xml, { explicitArray: false, ignoreAttrs: true });

    const servicosXml = parsed?.Servicos?.cServico;
    const list = Array.isArray(servicosXml) ? servicosXml : servicosXml ? [servicosXml] : [];

    const servicos = list.map((s) => {
      const codigoServico = s.Codigo;
      let nome = "Correios";
      if (codigoServico === "04014") nome = "SEDEX";
      if (codigoServico === "04510") nome = "PAC";

      const valorStr = (s.Valor || "0").replace(".", "").replace(",", ".");
      const valor = parseFloat(valorStr) || 0;
      const prazoDias = parseInt(s.PrazoEntrega || "0", 10) || 0;

      return { codigo: codigoServico, nome, valor, prazoDias };
    });

    return { servicos };
  } catch (err) {
    console.error("[calcularCorreios] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao consultar frete dos Correios.");
  }
  }
);

export const calcularMelhorEnvio = onCall(
  { timeoutSeconds: 25, memory: "256MiB" },
  async (request) => {
  try {
    const identifier = getCallableIdentifier(request);
    await checkRateLimit("calcularMelhorEnvio", identifier);

    const {
      token,
      origem,
      destino,
      peso,
      altura,
      largura,
      comprimento,
      servico,
      valorProdutos,
    } = request.data || {};

    if (!token || !origem || !destino || !peso) {
      throw new HttpsError(
        "invalid-argument",
        "Parâmetros insuficientes para calcular frete pelo Melhor Envio."
      );
    }

    const url = "https://www.melhorenvio.com.br/api/v2/me/shipment/calculate";

    const vProd = Number(valorProdutos);
    const insuranceValue = Number.isFinite(vProd) && vProd > 0 ? vProd : 10;

    const payload = {
      from: { postal_code: String(origem) },
      to: { postal_code: String(destino) },
      package: {
        weight: Number(peso),
        height: Number(altura),
        width: Number(largura),
        length: Number(comprimento),
      },
      services: servico || "1,2,3,4,17", // PAC, SEDEX, Jadlog .Package, .Com, Mini Envios (17)
      options: {
        insurance_value: insuranceValue,
        receipt: false,
        own_hand: false,
      },
    };

    const resp = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
          "User-Agent": "MasterPalm (contato@mastepalm.com.br)",
        },
        body: JSON.stringify(payload),
      },
      18000
    );

    const txt = await resp.text();
    if (!resp.ok) {
      console.error("[calcularMelhorEnvio] HTTP error:", resp.status, txt);
      throw new HttpsError("internal", "Erro ao consultar frete via Melhor Envio.");
    }

    const trimmed = txt.trim().toLowerCase();
    if (trimmed.startsWith("<!") || trimmed.startsWith("<html")) {
      console.error("[calcularMelhorEnvio] Resposta HTML em vez de JSON");
      throw new HttpsError("internal", "Melhor Envio retornou página web. Verifique o token.");
    }

    const data = JSON.parse(txt);
    const servicos = Array.isArray(data) ? data : [];
    return { servicos };
  } catch (err) {
    console.error("[calcularMelhorEnvio] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao consultar frete via Melhor Envio.");
  }
  }
);

/** Teste do token /me no servidor (navegador não pode chamar Melhor Envio direto — CORS). */
export const testarMelhorEnvioToken = onCall(
  { timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("testarMelhorEnvioToken", identifier);

      const { token } = request.data || {};
      const t = typeof token === "string" ? token.trim() : "";
      if (!t) {
        throw new HttpsError(
          "invalid-argument",
          "Informe o token do Melhor Envio."
        );
      }

      const url = "https://www.melhorenvio.com.br/api/v2/me";
      const resp = await fetchWithTimeout(
        url,
        {
          method: "GET",
          headers: {
            Accept: "application/json",
            Authorization: `Bearer ${t}`,
            "User-Agent": "MasterPalm (contato@mastepalm.com.br)",
          },
        },
        15000
      );

      const txt = await resp.text();
      if (resp.status === 401) {
        throw new HttpsError(
          "permission-denied",
          "Token inválido ou expirado."
        );
      }
      if (!resp.ok) {
        console.error(
          "[testarMelhorEnvioToken] HTTP",
          resp.status,
          txt?.slice?.(0, 300)
        );
        throw new HttpsError(
          "internal",
          `Melhor Envio retornou ${resp.status}. Confira o token.`
        );
      }

      let data;
      try {
        data = JSON.parse(txt);
      } catch (e) {
        console.error("[testarMelhorEnvioToken] JSON inválido");
        throw new HttpsError(
          "internal",
          "Resposta inválida do Melhor Envio."
        );
      }

      const firstname = data.firstname || data.name || "Usuário";
      return { ok: true, firstname: String(firstname) };
    } catch (err) {
      console.error("[testarMelhorEnvioToken] error:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        err?.message || "Erro ao testar token do Melhor Envio."
      );
    }
  }
);

export const calcularFrenet = onCall(
  { timeoutSeconds: 25, memory: "256MiB" },
  async (request) => {
  try {
    const identifier = getCallableIdentifier(request);
    await checkRateLimit("calcularFrenet", identifier);

    const {
      token,
      storeId,
      cepOrigem,
      cepDestino,
      peso,
      altura,
      largura,
      comprimento,
      valorProdutos,
    } = request.data || {};

    if (!token || !cepOrigem || !cepDestino || !peso) {
      throw new HttpsError(
        "invalid-argument",
        "Parâmetros insuficientes para calcular frete via Frenet."
      );
    }

    const url = "https://api.frenet.com.br/shipping/quote";

    const body = {
      SellerCEP: String(cepOrigem),
      RecipientCEP: String(cepDestino),
      ShipmentInvoiceValue: valorProdutos || 0,
      ShippingItemArray: [
        {
          Weight: Number(peso),
          Length: Number(comprimento),
          Height: Number(altura),
          Width: Number(largura),
          Quantity: 1,
        },
      ],
    };

    if (storeId) body.Shipper = { ShipperID: storeId };

    const resp = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", token: token },
        body: JSON.stringify(body),
      },
      18000
    );

    if (!resp.ok) {
      const txt = await resp.text();
      console.error("[calcularFrenet] HTTP error:", resp.status, txt);
      throw new HttpsError("internal", "Erro ao consultar frete via Frenet.");
    }

    return await resp.json();
  } catch (err) {
    console.error("[calcularFrenet] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao consultar frete via Frenet.");
  }
  }
);

// ----------------------------------------------------------------------------
// SuperFrete (API v8) - proxy para web (evita CORS)
// ----------------------------------------------------------------------------
const SUPERFRETE_USER_AGENT = "MasterPalm (contato@mastepalm.com.br)";

export const calcularSuperFrete = onCall(
  { timeoutSeconds: 25, memory: "256MiB" },
  async (request) => {
  try {
    const identifier = getCallableIdentifier(request);
    await checkRateLimit("calcularSuperFrete", identifier);

    const {
      token,
      cepOrigem,
      cepDestino,
      peso,
      altura,
      largura,
      comprimento,
      valorDeclarado,
    } = request.data || {};

    if (!token || !cepOrigem || !cepDestino || peso == null) {
      throw new HttpsError(
        "invalid-argument",
        "Parâmetros insuficientes para calcular frete via SuperFrete."
      );
    }

    const url = "https://api.superfrete.com/api/v8/calculator";

    const alt = Math.max(1, Math.round(Number(altura) || 10));
    const lar = Math.max(10, Math.round(Number(largura) || 20));
    const comp = Math.max(15, Math.round(Number(comprimento) || 30));
    const pesoKg = Math.max(0.3, Number(peso) / 1000);

    const payload = {
      from: { postal_code: String(cepOrigem).replace(/\D/g, "") },
      to: { postal_code: String(cepDestino).replace(/\D/g, "") },
      package: {
        height: alt,
        width: lar,
        length: comp,
        weight: pesoKg,
      },
      options: {
        insurance_value: Number(valorDeclarado) || 10,
        receipt: false,
        own_hand: false,
      },
    };

    const resp = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`,
          "Accept": "application/json",
          "User-Agent": SUPERFRETE_USER_AGENT,
        },
        body: JSON.stringify(payload),
      },
      20000
    );

    if (resp.status !== 200) {
      const txt = await resp.text();
      console.error("[calcularSuperFrete] HTTP error:", resp.status, txt);
      throw new HttpsError("internal", "Erro ao consultar frete via SuperFrete.");
    }

    const body = await resp.text();
    const bodyTrim = body.trim().toLowerCase();
    if (bodyTrim.startsWith("<!") || bodyTrim.startsWith("<html")) {
      console.error("[calcularSuperFrete] Resposta HTML em vez de JSON");
      throw new HttpsError(
        "internal",
        "SuperFrete retornou página web. Verifique o token e o ambiente (sandbox/produção)."
      );
    }

    const data = JSON.parse(body);
    const arr = Array.isArray(data) ? data : [];
    const opcoes = arr.map((s) => ({
      nome: s.name ?? "SuperFrete",
      preco: Number(s.price) || 0,
      prazo: s.delivery_time ?? 0,
      empresa: s.company?.name ?? "SuperFrete",
      servico_id: s.id,
    }));

    opcoes.sort((a, b) => a.preco - b.preco);

    return { sucesso: true, opcoes };
  } catch (err) {
    console.error("[calcularSuperFrete] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao consultar frete via SuperFrete.");
  }
  }
);

// ============================== MERCADO PAGO — PEDIDOS ======================
function mapItemsForMP(items = []) {
  return (items || []).map((it = {}) => ({
    title: it.name,
    quantity: Number(it.qty || 1),
    unit_price: Number(it.price || 0),
    currency_id: "BRL",
    picture_url: it.imageUrl || undefined,
  }));
}

async function findLojaIdByOrderId(orderId) {
  const { resolveLojaIdByOrderId } = await import("./src/orderLojaIndex.js");
  return resolveLojaIdByOrderId(db, orderId);
}

// ---------- HANDLERS PARA OUTROS GATEWAYS (PagSeguro / Ton / InfinitePay) ----------
async function handlePagSeguroPayment({ lojaId, orderId, order, paymentsCfg }) {
  const cfg = (paymentsCfg && paymentsCfg.pagseguro) || {};
  const enabled = !!cfg.enabled;
  const token = (cfg.token || cfg.accessToken || "").trim();

  if (!enabled || !token) {
    return {
      error:
        "PagSeguro não está configurado para esta loja (enabled/token ausente em config/payments.pagseguro).",
    };
  }

  const amount = Number(order.total || order.totalAmount || order.valorTotal || 0) || 0;
  const paymentId = `pagseguro_${orderId}`;

  await db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection("payments")
    .doc(paymentId)
    .set(
      {
        kind: "gateway",
        gateway: "pagseguro",
        orderId,
        lojaId,
        amount,
        status: "pending_backend",
        note: "Skeleton PagSeguro criado. Complete a integração com a API oficial no backend.",
        createdAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true }
    );

  return {
    id: paymentId,
    gateway: "pagseguro",
    status: "pending_backend",
    amount,
    message: "PagSeguro skeleton criado no Firestore. Falta plugar a chamada real da API (checkout/link).",
  };
}

async function handleTonPayment({ lojaId, orderId, order, paymentsCfg }) {
  const cfg = (paymentsCfg && paymentsCfg.ton) || {};
  const enabled = !!cfg.enabled;
  const apiKey = (cfg.apiKey || cfg.token || "").trim();

  if (!enabled || !apiKey) {
    return {
      error: "Ton não está configurado para esta loja (enabled/apiKey ausente em config/payments.ton).",
    };
  }

  const amount = Number(order.total || order.totalAmount || order.valorTotal || 0) || 0;
  const paymentId = `ton_${orderId}`;

  await db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection("payments")
    .doc(paymentId)
    .set(
      {
        kind: "gateway",
        gateway: "ton",
        orderId,
        lojaId,
        amount,
        status: "pending_backend",
        note: "Skeleton Ton criado. Complete a integração com a API/SDK oficial para gerar link ou registrar pagamento.",
        createdAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true }
    );

  return {
    id: paymentId,
    gateway: "ton",
    status: "pending_backend",
    amount,
    message: "Ton skeleton criado no Firestore. Falta plugar a API/SDK oficial.",
  };
}

async function handleInfinitePayPayment({ lojaId, orderId, order, paymentsCfg }) {
  const cfg = (paymentsCfg && paymentsCfg.infinitepay) || {};
  const enabled = !!cfg.enabled;
  const apiKey = (cfg.apiKey || cfg.token || "").trim();

  if (!enabled || !apiKey) {
    return {
      error:
        "InfinitePay não está configurado para esta loja (enabled/apiKey ausente em config/payments.infinitepay).",
    };
  }

  const amount = Number(order.total || order.totalAmount || order.valorTotal || 0) || 0;
  const paymentId = `infinitepay_${orderId}`;

  await db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection("payments")
    .doc(paymentId)
    .set(
      {
        kind: "gateway",
        gateway: "infinitepay",
        orderId,
        lojaId,
        amount,
        status: "pending_backend",
        note: "Skeleton InfinitePay criado. Complete a integração com a API oficial para gerar link/charge.",
        createdAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true }
    );

  return {
    id: paymentId,
    gateway: "infinitepay",
    status: "pending_backend",
    amount,
    message: "InfinitePay skeleton criado no Firestore. Falta plugar a API oficial.",
  };
}

/**
 * Cria a preferência de pagamento para um pedido
 */
export const createPreference = onRequest(
  { cors: true, secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL], timeoutSeconds: 45, memory: "256MiB" },
  corsWrap(async (req, res) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const bodyReq = req.body || {};
      const { lojaId, orderId, returnUrl, notificationUrl, idempotencyKey } = bodyReq;

      // Rate limiting (evita abuso)
      const identifier = getClientIdentifier(req);
      await checkRateLimit("createPreference", identifier);

      // Idempotência (retry não duplica preferência)
      const idemKey = idempotencyKey || (lojaId && orderId ? `${lojaId}:${orderId}` : null);
      if (idemKey) {
        const { hit, result } = await checkIdempotency("createPreference", idemKey);
        if (hit && result) return res.json(result);
      }
      const gateway = String(bodyReq.gateway || "mp").toLowerCase();

      if (!lojaId || !orderId) return res.status(400).send("orderId/lojaId missing");

      const orderRef = db
        .collection(COLLECTION_LOJAS)
        .doc(lojaId)
        .collection("pedidos")
        .doc(orderId);

      const orderSnap = await orderRef.get();
      if (!orderSnap.exists) return res.status(404).send("Order not found");

      const order = orderSnap.data() || {};
      const itemsForMp = mapItemsForMP(order.items || []);
      const paymentsCfg = await getLojaPaymentsRaw(lojaId);

      // --------------------- MERCADO PAGO (DEFAULT) ---------------------
      if (gateway === "mp" || gateway === "mercadopago") {
        if (itemsForMp.length === 0) return res.status(400).send("No items to pay");

        const lojaCfg = await getLojaPaymentConfig(lojaId);
        const mpResolved = resolveStrictLojaMpAccessToken(lojaCfg);
        if (!mpResolved.ok) {
          console.warn(
            JSON.stringify({
              evt: "mp_loja_token_required",
              function: "createPreference",
              domain: "loja_pedido",
              lojaId: String(lojaId),
              orderId: String(orderId),
              reason: mpResolved.reason,
              tokenLen: mpResolved.tokenLen,
            }),
          );
          return res.status(400).json({
            error:
              "Mercado Pago da loja não configurado ou token inválido. Configure o Access Token de produção em Pagamentos.",
            code: "MP_LOJA_TOKEN_REQUIRED",
          });
        }
        const MP_TOKEN = mpResolved.token;

        const WEB_BASE = S_WEB_BASE_URL.value() || process.env.WEB_BASE_URL || PUBLIC_SITE_ORIGIN;

        const back = returnUrl || `${WEB_BASE}/pedido/${orderId}`;
        const notif =
          notificationUrl ||
          WEBHOOK_URL ||
          `https://southamerica-east1-${PROJECT_ID}.cloudfunctions.net/mpWebhook`;

        const payer = buildMpBuyerPayerForCatalog(order, orderId);

        const mpBody = {
          items: itemsForMp,
          payer,
          external_reference: orderId,
          auto_return: "approved",
          back_urls: { success: back, failure: back, pending: back },
          notification_url: notif,
          metadata: { lojaId },
          statement_descriptor: "MASTERPALM",
        };

        const r = await fetchWithTimeout(
          "https://api.mercadopago.com/checkout/preferences",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${MP_TOKEN}`,
            },
            body: JSON.stringify(mpBody),
          },
          25000
        );

        if (!r.ok) {
          const txt = await r.text();
          console.error("MP create preference error:", txt);
          return res.status(r.status).send(txt);
        }

        const data = await r.json();

        await orderRef.set(
          { mpPreferenceId: data.id, status: "pending", updatedAt: nowTs },
          { merge: true }
        );

        await db
          .collection(COLLECTION_LOJAS)
          .doc(lojaId)
          .collection("payments")
          .doc(String(data.id))
          .set({ kind: "preference", orderId, lojaId, createdAt: nowTs }, { merge: true });

        const pubKey = lojaCfg.publicKey || MP_PUBLIC_KEY || null;

        const mpResult = { gateway: "mp", init_point: data.init_point, id: data.id, public_key: pubKey };
        if (idemKey) await saveIdempotency("createPreference", idemKey, mpResult);

        return res.json(mpResult);
      }

      // --------------------- PAGSEGURO ---------------------
      if (gateway === "pagseguro") {
        const result = await handlePagSeguroPayment({ lojaId, orderId, order, paymentsCfg });
        if (result.error) return res.status(400).json(result);
        return res.json(result);
      }

      // --------------------- TON ---------------------
      if (gateway === "ton") {
        const result = await handleTonPayment({ lojaId, orderId, order, paymentsCfg });
        if (result.error) return res.status(400).json(result);
        return res.json(result);
      }

      // --------------------- INFINITEPAY ---------------------
      if (gateway === "infinitepay") {
        const result = await handleInfinitePayPayment({ lojaId, orderId, order, paymentsCfg });
        if (result.error) return res.status(400).json(result);
        return res.json(result);
      }

      return res.status(400).json({ error: `Gateway inválido: ${gateway}` });
    } catch (e) {
      if (e.code === "resource-exhausted") {
        return res.status(429).json({ error: e.message || "Muitas requisições. Tente novamente em alguns minutos.", retryAfter: 60 });
      }
      console.error("createPreference error:", e);
      return res.status(500).send("Erro ao criar preferência");
    }
  })
);

/**
 * Proxy para criar pagamento Mercado Pago a partir do catálogo (PIX ou preferência).
 * Usado na WEB para evitar CORS (o browser não pode chamar api.mercadopago.com diretamente).
 * POST body: { lojaId, type: 'pix'|'preference', ... }
 * v2 - force deploy
 */
export const mpCatalogPayment = onRequest(
  { cors: true, secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL], timeoutSeconds: 30, memory: "256MiB" },
  corsWrap(async (req, res) => {
    let catalogIdemKey = null;
    let lockHeld = false;
    let mpProviderIdempotencyKey = "";
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const body = req.body || {};
      const { lojaId, type } = body;
      if (!lojaId || !type) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "missing_lojaId_or_type",
          lojaId: lojaId != null ? String(lojaId) : undefined,
        });
        return res.status(400).json({ error: "lojaId e type são obrigatórios" });
      }

      const orderIdRaw = body.orderId != null ? String(body.orderId).trim() : "";
      const extRef =
        body.externalReference != null ? String(body.externalReference).trim() : "";
      const orderId = orderIdRaw || extRef;
      if (!orderId) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "missing_orderId_or_externalReference",
          lojaId: String(lojaId),
        });
        return res.status(400).json({
          error: "orderId ou externalReference é obrigatório (pré-pedido/pedido canônico).",
        });
      }

      try {
        await checkRateLimit("mpCatalogPayment", `${lojaId}:${orderId}`);
      } catch (rlErr) {
        if (rlErr instanceof HttpsError && rlErr.code === "resource-exhausted") {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_rate_limited",
            severity: "warn",
            outcome: "rate_limited",
            lojaId: String(lojaId),
            orderId: String(orderId),
            externalReference: String(orderId),
          });
          return res.status(429).json({
            error:
              rlErr.message || "Muitas tentativas para este pedido. Aguarde e tente novamente.",
            code: "MP_CATALOG_RATE_LIMIT",
          });
        }
        throw rlErr;
      }

      const resolvedOrder = await resolveCatalogOrderForMp(db, lojaId, orderId);
      if (!resolvedOrder) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "order_not_found",
          lojaId: String(lojaId),
          orderId: String(orderId),
          externalReference: String(orderId),
        });
        return res.status(404).json({ error: "Pedido não encontrado para esta loja." });
      }
      if (!isOrderPayableForMp(resolvedOrder.order)) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "order_not_payable",
          lojaId: String(lojaId),
          orderId: String(orderId),
          externalReference: String(orderId),
        });
        return res.status(400).json({
          error: "Pedido não disponível para pagamento (inexistente, já pago ou cancelado).",
        });
      }
      const expectedTotal = Number(resolvedOrder.order.total);
      if (!Number.isFinite(expectedTotal) || expectedTotal < 0.01) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "invalid_total",
          lojaId: String(lojaId),
          orderId: String(orderId),
          externalReference: String(orderId),
        });
        return res.status(400).json({ error: "Total do pedido inválido no servidor." });
      }
      const clientValor = body.valor != null ? Number(body.valor) : null;
      if (
        clientValor != null &&
        Number.isFinite(clientValor) &&
        orderTotalToCents(clientValor) !== orderTotalToCents(expectedTotal)
      ) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "warn",
          outcome: "validation_fail",
          reason: "client_total_divergence_ignored",
          lojaId: String(lojaId),
          orderId: String(orderId),
          externalReference: String(orderId),
          amountExpectedCents: orderTotalToCents(expectedTotal),
        });
      }

      const lojaCfg = await getLojaPaymentConfig(lojaId);
      const mpResolved = resolveStrictLojaMpAccessToken(lojaCfg);
      if (!mpResolved.ok) {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_validation_failed",
          severity: "error",
          outcome: "validation_fail",
          reason:
            mpResolved.reason === "missing"
              ? "mp_store_token_missing"
              : "mp_store_token_invalid_format",
          lojaId: String(lojaId),
          orderId: String(orderId),
          externalReference: String(orderId),
          tokenLen: mpResolved.tokenLen,
        });
        return res.status(400).json({
          error:
            "Mercado Pago não configurado para esta loja ou token inválido. Configure o Access Token (PRODUÇÃO) em Pagamentos.",
          code: "MP_LOJA_TOKEN_REQUIRED",
        });
      }
      const MP_TOKEN = mpResolved.token;

      const t = String(type).toLowerCase();
      const correlationId =
        t === "pix" || t === "preference" ? catalogPaymentCorrelationId(lojaId, orderId, t) : undefined;

      if (t === "pix" || t === "preference") {
        catalogIdemKey = `${lojaId}:${orderId}:${t}`.slice(0, 128);
        const { hit, result: idemResult } = await checkIdempotency("mpCatalogPayment", catalogIdemKey);
        if (hit && idemResult) {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_idempotency_hit",
            severity: "info",
            outcome: "reuse",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            externalReference: String(orderId),
            correlationId,
            idempotencyKeyDigest: correlationId,
          });
          return res.json(idemResult);
        }

        if (t === "pix" && !body.descricao) {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_validation_failed",
            severity: "warn",
            outcome: "validation_fail",
            reason: "missing_descricao",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            correlationId,
            externalReference: String(orderId),
          });
          return res.status(400).json({ error: "PIX requer descricao" });
        }
        if (t === "preference" && !body.titulo) {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_validation_failed",
            severity: "warn",
            outcome: "validation_fail",
            reason: "missing_titulo",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            correlationId,
            externalReference: String(orderId),
          });
          return res.status(400).json({ error: "Preferência requer titulo" });
        }

        const gate = await tryBeginMpCatalogPaymentOrReuse(db, catalogIdemKey);
        if (gate.kind === "reuse" && gate.result) {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_idempotency_hit",
            severity: "info",
            outcome: "reuse",
            source: "firestore_lock_doc",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            externalReference: String(orderId),
            correlationId,
            idempotencyKeyDigest: correlationId,
          });
          return res.json(gate.result);
        }
        if (gate.kind === "busy") {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_in_progress",
            severity: "warn",
            outcome: "busy",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            externalReference: String(orderId),
            correlationId,
            idempotencyKeyDigest: correlationId,
          });
          return res.status(409).json({
            error: "Pagamento em processamento. Tente novamente em instantes.",
            code: "MP_CATALOG_PAYMENT_IN_PROGRESS",
          });
        }
        if (gate.kind === "error") {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_validation_failed",
            severity: "error",
            outcome: "validation_fail",
            reason: "lock_acquire_failed",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            externalReference: String(orderId),
            correlationId,
          });
          return res.status(500).json({ error: "Erro ao reservar pagamento. Tente novamente." });
        }
        lockHeld = true;
        mpProviderIdempotencyKey = buildMpCatalogProviderIdempotencyKey(lojaId, orderId, t);
      }

      if (t === "pix") {
        const { descricao, email, cpf } = body;
        const numValor = expectedTotal;
        const pixPayer = resolveCatalogPixPayerForMp({
          body: { email, cpf },
          order: resolvedOrder.order,
          orderId,
        });
        if (!pixPayer.ok) {
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_validation_failed",
            severity: "warn",
            outcome: "validation_fail",
            reason: "cpf_invalid_for_pix",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: t,
            correlationId,
            externalReference: String(orderId),
          });
          if (lockHeld && catalogIdemKey) await releaseMpCatalogPaymentLock(db, catalogIdemKey);
          return res.status(400).json({ error: pixPayer.error, code: pixPayer.code });
        }
        const { emailStr, cpfLimpo } = pixPayer;
        const notifUrl = WEBHOOK_URL || (PROJECT_ID ? `https://southamerica-east1-${PROJECT_ID}.cloudfunctions.net/mpWebhook` : "");
        // P1.5 trava local (Firestore) + chave determinística no MP: sucesso remoto com falha no commit local não deve gerar nova cobrança no retry.
        const mpBody = {
          transaction_amount: numValor,
          description: String(descricao),
          payment_method_id: "pix",
          external_reference: String(orderId),
          metadata: { lojaId: String(lojaId) },
          ...(notifUrl && { notification_url: notifUrl }),
          payer: {
            email: emailStr,
            ...(cpfLimpo.length === 11 && {
              identification: { type: "CPF", number: cpfLimpo },
            }),
          },
        };
        const r = await fetchWithTimeout(
          "https://api.mercadopago.com/v1/payments",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${MP_TOKEN}`,
              ...(mpProviderIdempotencyKey && {
                "X-Idempotency-Key": mpProviderIdempotencyKey,
              }),
            },
            body: JSON.stringify(mpBody),
          },
          20000
        );
        if (!r.ok) {
          const txt = await r.text();
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_provider_error",
            severity: "error",
            outcome: "provider_fail",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: "pix",
            externalReference: String(orderId),
            correlationId,
            idempotencyKeyDigest: correlationId,
            httpStatus: r.status,
            providerErrorSnippet: truncateProviderErrorText(txt),
          });
          let errMsg = "Erro ao gerar PIX. Verifique e-mail e CPF e tente novamente.";
          try {
            const errJson = JSON.parse(txt);
            const msg = errJson?.message || errJson?.error || errJson?.cause?.[0]?.description;
            if (msg) {
              const s = String(msg).toLowerCase();
              if (s.includes("bad_request") || s.includes("invalid")) {
                errMsg = "Dados inválidos para PIX. Verifique e-mail e CPF e tente novamente.";
              } else {
                errMsg = String(msg);
              }
            }
          } catch (_) {}
          if (lockHeld && catalogIdemKey) await releaseMpCatalogPaymentLock(db, catalogIdemKey);
          return res.status(r.status).json({ error: errMsg });
        }
        const data = await r.json();
        const pixPayload = {
          id: data.id,
          status: data.status,
          qr_code: data.point_of_interaction?.transaction_data?.qr_code,
          qr_code_base64: data.point_of_interaction?.transaction_data?.qr_code_base64,
          ticket_url: data.point_of_interaction?.transaction_data?.ticket_url,
        };
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_provider_success",
          severity: "info",
          outcome: "success",
          lojaId: String(lojaId),
          orderId: String(orderId),
          type: "pix",
          externalReference: String(orderId),
          correlationId,
          idempotencyKeyDigest: correlationId,
          providerPaymentId: data.id != null ? String(data.id) : undefined,
          paymentStatus: data.status != null ? String(data.status) : undefined,
        });
        if (lockHeld && catalogIdemKey) {
          try {
            await commitMpCatalogPaymentSuccess(db, catalogIdemKey, pixPayload);
            emitCatalogPaymentLog({
              event: "mpCatalogPayment_persist_success",
              severity: "info",
              outcome: "success",
              lojaId: String(lojaId),
              orderId: String(orderId),
              type: "pix",
              externalReference: String(orderId),
              correlationId,
              providerPaymentId: data.id != null ? String(data.id) : undefined,
            });
          } catch (persistErr) {
            emitCatalogPaymentLog({
              event: "mpCatalogPayment_persist_error",
              severity: "error",
              outcome: "persist_fail",
              lojaId: String(lojaId),
              orderId: String(orderId),
              type: "pix",
              externalReference: String(orderId),
              correlationId,
              providerPaymentId: data.id != null ? String(data.id) : undefined,
              err: String(persistErr?.message || persistErr),
            });
            throw persistErr;
          }
        }
        return res.json(pixPayload);
      }

      if (t === "preference") {
        const { titulo, quantidade = 1, descricao, backUrls } = body;
        const payerPref = buildMpBuyerPayerForCatalog(resolvedOrder.order, orderId);
        const WEB_BASE = (await S_WEB_BASE_URL.value()) || process.env.WEB_BASE_URL || "https://app.mastepalm.com.br";
        const notifUrl = WEBHOOK_URL || (PROJECT_ID ? `https://southamerica-east1-${PROJECT_ID}.cloudfunctions.net/mpWebhook` : "");
        const unitPrice = expectedTotal / (Number(quantidade) || 1);
        const lojaQ = encodeURIComponent(String(lojaId));
        const backFallback = {
          success: `${WEB_BASE}/pagamento/sucesso?loja=${lojaQ}`,
          failure: `${WEB_BASE}/pagamento/falha?loja=${lojaQ}`,
          pending: `${WEB_BASE}/pagamento/pendente?loja=${lojaQ}`,
        };
        const mpBody = {
          items: [
            {
              title: String(titulo),
              description: descricao || titulo,
              quantity: Number(quantidade) || 1,
              currency_id: "BRL",
              unit_price: unitPrice,
            },
          ],
          external_reference: String(orderId),
          metadata: { lojaId: String(lojaId) },
          ...(notifUrl && { notification_url: notifUrl }),
          payer: payerPref,
          back_urls: backUrls || backFallback,
          auto_return: "approved",
          statement_descriptor: "MASTERPALM",
        };
        const r = await fetchWithTimeout(
          "https://api.mercadopago.com/checkout/preferences",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${MP_TOKEN}`,
              ...(mpProviderIdempotencyKey && {
                "X-Idempotency-Key": mpProviderIdempotencyKey,
              }),
            },
            body: JSON.stringify(mpBody),
          },
          20000
        );
        if (!r.ok) {
          const txt = await r.text();
          emitCatalogPaymentLog({
            event: "mpCatalogPayment_provider_error",
            severity: "error",
            outcome: "provider_fail",
            lojaId: String(lojaId),
            orderId: String(orderId),
            type: "preference",
            externalReference: String(orderId),
            correlationId,
            idempotencyKeyDigest: correlationId,
            httpStatus: r.status,
            providerErrorSnippet: truncateProviderErrorText(txt),
          });
          if (lockHeld && catalogIdemKey) await releaseMpCatalogPaymentLock(db, catalogIdemKey);
          return res.status(r.status).send(txt);
        }
        const data = await r.json();
        const prefPayload = {
          id: data.id,
          init_point: data.init_point,
          sandbox_init_point: data.sandbox_init_point,
        };
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_provider_success",
          severity: "info",
          outcome: "success",
          lojaId: String(lojaId),
          orderId: String(orderId),
          type: "preference",
          externalReference: String(orderId),
          correlationId,
          idempotencyKeyDigest: correlationId,
          preferenceId: data.id != null ? String(data.id) : undefined,
        });
        if (lockHeld && catalogIdemKey) {
          try {
            await commitMpCatalogPaymentSuccess(db, catalogIdemKey, prefPayload);
            emitCatalogPaymentLog({
              event: "mpCatalogPayment_persist_success",
              severity: "info",
              outcome: "success",
              lojaId: String(lojaId),
              orderId: String(orderId),
              type: "preference",
              externalReference: String(orderId),
              correlationId,
              preferenceId: data.id != null ? String(data.id) : undefined,
            });
          } catch (persistErr) {
            emitCatalogPaymentLog({
              event: "mpCatalogPayment_persist_error",
              severity: "error",
              outcome: "persist_fail",
              lojaId: String(lojaId),
              orderId: String(orderId),
              type: "preference",
              externalReference: String(orderId),
              correlationId,
              preferenceId: data.id != null ? String(data.id) : undefined,
              err: String(persistErr?.message || persistErr),
            });
            throw persistErr;
          }
        }
        return res.json(prefPayload);
      }

      emitCatalogPaymentLog({
        event: "mpCatalogPayment_validation_failed",
        severity: "warn",
        outcome: "validation_fail",
        reason: "invalid_type",
        lojaId: String(lojaId),
        orderId: String(orderId),
        type: t,
        externalReference: String(orderId),
      });
      return res.status(400).json({ error: "type deve ser 'pix' ou 'preference'" });
    } catch (e) {
      if (lockHeld && catalogIdemKey) {
        await releaseMpCatalogPaymentLock(db, catalogIdemKey).catch(() => {});
      }
      if (e instanceof HttpsError && e.code === "resource-exhausted") {
        emitCatalogPaymentLog({
          event: "mpCatalogPayment_rate_limited",
          severity: "warn",
          outcome: "rate_limited",
          reason: "outer_catch",
        });
        return res.status(429).json({
          error: e.message || "Muitas requisições.",
          code: "MP_CATALOG_RATE_LIMIT",
        });
      }
      emitCatalogPaymentLog({
        event: "mpCatalogPayment_processing_error",
        severity: "error",
        outcome: "error",
        err: String(e?.message || e),
      });
      return res.status(500).json({ error: "Erro ao criar pagamento no Mercado Pago. Tente novamente." });
    }
  })
);

/**
 * WEBHOOK OFICIAL DE PRODUÇÃO — Mercado Pago
 *
 * URL: https://southamerica-east1-{PROJECT_ID}.cloudfunctions.net/mpWebhook
 * Configure esta URL no painel do Mercado Pago (Webhooks / Notificações).
 *
 * Responsabilidades:
 * - Idempotência por paymentId (reenvios não duplicam)
 * - Token correto por lojaId (multi-tenant)
 * - Atualiza pedidos/pre_pedidos, baixa estoque, notifica admin
 *
 * NOTA: mercadopagoWebhook (posPagamento.js) NÃO está em uso; campanhas/números
 * via webhook requerem integração futura se necessário.
 *
 * Borda: valida x-signature (MP_WEBHOOK_SECRET) antes de processMpWebhook — alinhado ao planWebhook.
 * Sem paymentId: 200 ok (ack vazio, sem efeito).
 * Assinatura inválida: 401 (não entra no handler).
 * processMpWebhook conclui (retorno booleano): 200 OK (inclui validação de negócio false e noops internos).
 * Exceção ao processar: 500 (retentativa MP).
 */
export const mpWebhook = onRequest(
  {
    cors: true,
    secrets: [S_MP_ACCESS_TOKEN, S_MP_WEBHOOK_SECRET, S_SMTP_EMAIL, S_SMTP_PASSWORD],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  corsWrap(async (req, res) => {
    try {
      const body = req.body || {};
      const query = req.query || {};
      const paymentId = body?.data?.id || query["data.id"] || body?.id || query?.id;

      if (!paymentId) return res.status(200).send("ok");

      const smtpUser = ((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
      const smtpPass = ((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();

      const WEBHOOK_SECRET =
        (await S_MP_WEBHOOK_SECRET.value()) || process.env.MP_WEBHOOK_SECRET || "";
      const sig = verifyMpCatalogWebhookNotification(req, WEBHOOK_SECRET);
      if (!sig.ok) {
        const reason = sig.reason || "unknown";
        let evt = "mp_webhook_signature_invalid";
        if (reason === "header_missing") evt = "mp_webhook_signature_missing";
        else if (
          reason === "secret_missing" ||
          reason === "hmac_error" ||
          reason === "unknown"
        ) {
          evt = "mp_webhook_signature_error";
        }
        console.warn(
          JSON.stringify({
            service: "mpWebhook",
            provider: "mercadopago",
            severity: "warn",
            event: evt,
            reason,
            ...(sig.detail ? { detail: String(sig.detail).slice(0, 200) } : {}),
          }),
        );
        return res.status(MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS).send("Unauthorized");
      }

      await processMpWebhook(paymentId, { smtpUser, smtpPass });

      return res.status(200).send("OK");
    } catch (e) {
      console.error(
        JSON.stringify({
          service: "mpWebhook",
          provider: "mercadopago",
          severity: "error",
          event: "mp_webhook_processing_error",
          err: String(e?.message || e).slice(0, 500),
        }),
      );
      console.error("mpWebhook error:", e);
      return res.status(MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS).send("Internal Server Error");
    }
  })
);

// ============================== MERCADO PAGO — PLANOS ========================
const PRICE_BASIC_MONTHLY = 19.99;
const PRICE_INTERMEDIATE_MONTHLY = 29.99;
const PRICE_PRO_MONTHLY = 39.99;
const PRICE_PRO_YEARLY = 349.99;
/** @deprecated nomes legados; mantidos para compatibilidade de clientes antigos */
const PRICE_MENSAL = PRICE_PRO_MONTHLY;
const PRICE_ANUAL = PRICE_PRO_YEARLY;

function normalizePlanId(raw) {
  const p = String(raw || "").trim().toLowerCase();
  if (p === "mensal" || p === "pro_monthly") return "pro_monthly";
  if (p === "anual" || p === "pro_yearly") return "pro_yearly";
  if (p === "basic" || p === "basic_monthly") return "basic_monthly";
  if (p === "intermediate" || p === "intermediate_monthly") return "intermediate_monthly";
  if (p === "trial_30d" || p === "free_trial_30d") return "free_trial_30d";
  if (p === "trial_90d" || p === "free_trial_90d") return "free_trial_90d";
  if (p === "free_limited") return "free_limited";
  if (p === "lifetime") return "lifetime";
  return p;
}

function planTitleForMp(canonicalPlanId) {
  const c = normalizePlanId(canonicalPlanId);
  if (c === "basic_monthly") return "MasterPalm — Plano Básico (mensal)";
  if (c === "intermediate_monthly") return "MasterPalm — Plano Intermediário (mensal)";
  if (c === "pro_monthly") return "MasterPalm — Plano Pro (mensal)";
  if (c === "pro_yearly") return "MasterPalm — Plano Pro (anual)";
  return `MasterPalm — ${c}`;
}

function unitPriceForPlan(canonicalPlanId) {
  const c = normalizePlanId(canonicalPlanId);
  if (c === "basic_monthly") return PRICE_BASIC_MONTHLY;
  if (c === "intermediate_monthly") return PRICE_INTERMEDIATE_MONTHLY;
  if (c === "pro_monthly") return PRICE_PRO_MONTHLY;
  if (c === "pro_yearly") return PRICE_PRO_YEARLY;
  return PRICE_PRO_MONTHLY;
}

function toLegacyPlanAlias(planId) {
  const p = normalizePlanId(planId);
  if (p === "pro_yearly") return "anual";
  if (p === "pro_monthly") return "mensal";
  return p;
}

function mapCheckoutStatus(mpStatus) {
  const s = String(mpStatus || "").trim().toLowerCase();
  if (s === "approved") return "approved";
  if (s === "pending" || s === "in_process") return "pending";
  if (s === "cancelled" || s === "canceled") return "cancelled";
  if (s === "refunded" || s === "charged_back") return "refunded";
  return "rejected";
}

async function findCheckoutByPayment({ preferenceId, externalRef, userEmail, expectedPlanId }) {
  const expected = normalizePlanId(expectedPlanId);
  if (preferenceId) {
    const q = await db
      .collection("checkout_planos")
      .where("preferenceId", "==", preferenceId)
      .limit(1)
      .get();
    if (!q.empty) return { doc: q.docs[0], source: "preferenceId", ambiguous: false };
  }
  if (externalRef) {
    const q = await db
      .collection("checkout_planos")
      .where("externalReference", "==", externalRef)
      .limit(1)
      .get();
    if (!q.empty) return { doc: q.docs[0], source: "externalReference", ambiguous: false };
  }
  if (userEmail) {
    const q = await db
      .collection("checkout_planos")
      .where("userEmail", "==", userEmail)
      .orderBy("createdAt", "desc")
      .limit(3)
      .get();
    if (!q.empty) {
      const now = Date.now();
      const recentAndCompatible = q.docs.filter((doc) => {
        const d = doc.data() || {};
        const created = d.createdAt?.toDate ? d.createdAt.toDate().getTime() : 0;
        const isRecent = created > 0 && now - created <= 1000 * 60 * 30; // 30min
        const planCandidate = normalizePlanId(d.normalizedPlanId || d.planoId || "");
        const compatible = !expected || !planCandidate || planCandidate === expected;
        return isRecent && compatible;
      });
      if (recentAndCompatible.length === 1) {
        return { doc: recentAndCompatible[0], source: "userEmail_strict", ambiguous: false };
      }
      if (recentAndCompatible.length > 1) {
        return { doc: null, source: "userEmail_strict", ambiguous: true };
      }
    }
  }
  return { doc: null, source: "none", ambiguous: false };
}

async function activatePlanForUser({
  uid,
  plan,
  paymentId,
  status,
  amount,
  planOrderId,
  billingExtras,
}) {
  const now = new Date();
  let renew = null;
  const canonicalPlanId = normalizePlanId(plan);
  if (canonicalPlanId === "pro_yearly") renew = addYears(now, 1);
  else if (
    canonicalPlanId === "pro_monthly" ||
    canonicalPlanId === "basic_monthly" ||
    canonicalPlanId === "intermediate_monthly"
  ) {
    renew = addMonths(now, 1);
  } else {
    renew = addMonths(now, 1);
  }

  const ref = db.collection("users").doc(uid);

  const payload = {
    // Canônico
    currentPlanId: canonicalPlanId || "pro_monthly",
    status: "active",
    currentPeriodEnd: renew ? admin.firestore.Timestamp.fromDate(renew) : null,
    trialing: false,
    trialUsed: true,
    cancelAtPeriodEnd: false,
    planLastPaymentId: String(paymentId || ""),
    updatedAt: nowTs,
    ...(billingExtras && typeof billingExtras === "object" ? billingExtras : {}),
  };

  await ref.set(payload, { merge: true });

  // Histórico canônico de assinatura
  await ref.collection("subscriptions").doc(String(paymentId || Date.now())).set(
    {
      planId: canonicalPlanId || "pro_monthly",
      status: "active",
      trialing: false,
      currentPeriodEnd: renew ? admin.firestore.Timestamp.fromDate(renew) : null,
      kind: "paid",
      paymentId: String(paymentId || ""),
      planOrderId: planOrderId || null,
      amount: amount ?? null,
      createdAt: nowTs,
      updatedAt: nowTs,
    },
    { merge: true }
  );

  if (planOrderId) {
    await db
      .collection(PLAN_ORDERS_COL)
      .doc(String(planOrderId))
      .set(
        {
          userId: uid,
          activatedPlanId: canonicalPlanId || "pro_monthly",
          expiresAt: renew ? admin.firestore.Timestamp.fromDate(renew) : null,
          updatedAt: nowTs,
        },
        { merge: true }
      );
  }

  return payload;
}

/** Bearer do header (Express pode normalizar chaves em minúsculas). */
function extractBearerTokenFromRequest(req) {
  const headers = req?.headers || {};
  const authRaw =
    headers.authorization ||
    headers.Authorization ||
    headers["authorization"] ||
    (typeof headers.get === "function"
      ? headers.get("authorization") || headers.get("Authorization") || ""
      : "");
  const m = /^Bearer\s+(.+)$/i.exec(String(authRaw).trim());
  return m?.[1]?.trim() || null;
}

/** JWT Firebase: payload aud/iss/sub (sem validar assinatura) — só diagnóstico. */
function planCreatePreferenceIdTokenPayloadDiag(bearerToken) {
  if (!bearerToken) {
    return { aud: null, iss: null, subHint: null, tokenLength: 0 };
  }
  const tokenLength = bearerToken.length;
  let aud = null;
  let iss = null;
  let subHint = null;
  try {
    const parts = bearerToken.split(".");
    if (parts.length >= 2) {
      const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const json = Buffer.from(b64, "base64").toString("utf8");
      const p = JSON.parse(json);
      aud = p.aud != null ? String(p.aud) : null;
      iss = p.iss != null ? String(p.iss).slice(0, 80) : null;
      subHint = p.sub != null ? `${String(p.sub).slice(0, 10)}…` : null;
    }
  } catch (_) {
    /* ignore */
  }
  return { aud, iss, subHint, tokenLength };
}

function planCreatePreferenceAuthDiag(req, bearerToken) {
  const headers = req?.headers || {};
  const headerKeys = Object.keys(headers).filter((k) => /auth/i.test(String(k)));
  const adminProjectId = process.env.GCLOUD_PROJECT || PROJECT_ID || "";
  const payload = planCreatePreferenceIdTokenPayloadDiag(bearerToken);
  const audMismatchHint =
    !!payload.aud &&
    !!adminProjectId &&
    String(payload.aud) !== String(adminProjectId) &&
    !String(payload.iss || "").includes(adminProjectId);
  return {
    evt: "planCreatePreference_auth_diag",
    domain: "planos_app",
    transport: "http",
    authorizationHeaderPresent: !!bearerToken,
    bearerPrefixPresent: !!bearerToken,
    tokenLength: payload.tokenLength,
    aud: payload.aud,
    iss: payload.iss,
    subHint: payload.subHint,
    adminProjectId,
    audDiffersFromGcloudProject: audMismatchHint,
    headerKeysMatchingAuth: headerKeys.slice(0, 12),
  };
}

/** Preferência MP checkout planos — compartilhado por HTTP e Callable. */
async function executePlanPreferenceCheckout({
  tokenUid,
  tokenEmail,
  planInput,
  installationId,
  returnUrl,
  notificationUrl,
  mpToken,
  webBase,
}) {
  if (!mpToken) {
    const err = new Error("MP token not configured");
    err.code = "NO_MP";
    throw err;
  }
  const allowedPlans = new Set([
    "mensal",
    "anual",
    "basic_monthly",
    "intermediate_monthly",
    "pro_monthly",
    "pro_yearly",
  ]);
  const planStr = String(planInput || "").trim().toLowerCase();
  if (!allowedPlans.has(planStr)) {
    const err = new Error("plan inválido");
    err.code = "INVALID_PLAN";
    throw err;
  }

  const planOrderId = generatePlanOrderId();
  const canonical = normalizePlanId(planStr);
  const price = unitPriceForPlan(canonical);

  await db
    .collection(PLAN_ORDERS_COL)
    .doc(planOrderId)
    .set({
      planOrderId,
      userId: tokenUid,
      userEmail: tokenEmail || null,
      canonicalPlanId: canonical,
      legacyPlanAlias: planStr,
      orderStatus: "PENDENTE",
      installationId: installationId ? String(installationId).slice(0, 128) : null,
      createdAt: nowTs,
      updatedAt: nowTs,
    });

  console.log(
    JSON.stringify({
      evt: "plan_order_created",
      planOrderId,
      uid: tokenUid,
      plan: planStr,
      canonical,
    }),
  );

  const back = returnUrl || `${webBase}/assinatura/${planStr}/retorno`;
  const notif =
    notificationUrl ||
    WEBHOOK_URL ||
    `https://southamerica-east1-${PROJECT_ID}.cloudfunctions.net/planWebhook`;

  const mpBody = {
    items: [
      {
        id: `masterpalm_${canonical}`,
        title: planTitleForMp(canonical),
        quantity: 1,
        unit_price: Number(price.toFixed(2)),
        currency_id: "BRL",
        category_id: "services",
        description: "Assinatura do aplicativo MasterPalm",
      },
    ],
    payer: { email: tokenEmail || undefined },
    back_urls: { success: back, pending: back, failure: back },
    auto_return: "approved",
    notification_url: notif,
    external_reference: planOrderId,
    metadata: {
      uid: tokenUid,
      user_id: tokenUid,
      plan: planStr,
      normalized_plan_id: canonical,
      user_email: tokenEmail || "",
      plan_order_id: planOrderId,
    },
    statement_descriptor: "MASTERPALM",
  };

  const r = await fetchWithTimeout(
    "https://api.mercadopago.com/checkout/preferences",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${mpToken}`,
      },
      body: JSON.stringify(mpBody),
    },
    25000,
  );

  if (!r.ok) {
    const txt = await r.text();
    console.error("[planCreatePreference] MP error:", txt);
    await db.collection(PLAN_ORDERS_COL).doc(planOrderId).set(
      {
        orderStatus: "FALHA",
        mpPreferenceError: String(txt).slice(0, 2000),
        updatedAt: nowTs,
      },
      { merge: true },
    );
    const err = new Error("mp_http");
    err.code = "MP_HTTP";
    err.status = r.status;
    err.mpBody = txt;
    throw err;
  }

  const data = await r.json();

  await db.collection(PLAN_ORDERS_COL).doc(planOrderId).set(
    {
      preferenceId: data.id || null,
      updatedAt: nowTs,
    },
    { merge: true },
  );

  return {
    id: data.id,
    init_point: data.init_point || data.sandbox_init_point,
    public_key: MP_PUBLIC_KEY || null,
    planOrderId,
  };
}

/** Valida Firebase ID Token (Bearer) em HTTP onRequest */
async function requireFirebaseUserFromRequest(req) {
  const raw = extractBearerTokenFromRequest(req);
  if (!raw) {
    const err = new Error("NO_AUTH");
    err.code = "NO_AUTH";
    throw err;
  }
  return admin.auth().verifyIdToken(raw);
}

export const planCreatePreference = onRequest(
  { cors: true, secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL], timeoutSeconds: 45, memory: "256MiB" },
  corsWrap(async (req, res) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const bearerForDiag = extractBearerTokenFromRequest(req);
      console.log(JSON.stringify(planCreatePreferenceAuthDiag(req, bearerForDiag)));

      const identifier = getClientIdentifier(req);
      await checkRateLimit("planCreatePreference", identifier);

      let decoded;
      try {
        decoded = await requireFirebaseUserFromRequest(req);
      } catch (authErr) {
        if (authErr?.code === "NO_AUTH") {
          return res.status(401).json({ error: "Autenticação obrigatória (Bearer ID token)." });
        }
        console.warn(
          JSON.stringify({
            evt: "planCreatePreference_verify_fail",
            code: String(authErr?.code || "unknown"),
            message: String(authErr?.message || "").slice(0, 200),
            domain: "planos_app",
            adminProjectId: process.env.GCLOUD_PROJECT || PROJECT_ID || "",
          }),
        );
        return res.status(401).json({ error: "Token inválido ou expirado." });
      }

      const tokenUid = decoded.uid;
      const tokenEmail = normalizeEmail(decoded.email || "");

      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "planCreatePreference",
      });
      if (!platformToken.ok) return res.status(500).send("MP platform token not configured");

      const WEB_BASE =
        (await S_WEB_BASE_URL.value()) || process.env.WEB_BASE_URL || "https://app.mastepalm.com.br";

      const { plan, returnUrl, notificationUrl, installationId } = req.body || {};
      if (hasStoreContextInPlanPayload(req.body || {})) {
        return res.status(400).json({
          error: "Payload inválido para plano: contexto de loja não é permitido.",
          code: "PLAN_STORE_CONTEXT_FORBIDDEN",
        });
      }
      if (!plan) {
        return res.status(400).json({
          error:
            "plan é obrigatório (mensal|anual|basic_monthly|intermediate_monthly|pro_monthly|pro_yearly)",
        });
      }

      try {
        const payload = await executePlanPreferenceCheckout({
          tokenUid,
          tokenEmail,
          planInput: plan,
          installationId,
          returnUrl,
          notificationUrl,
          mpToken: platformToken.token,
          webBase: WEB_BASE,
        });
        return res.json(payload);
      } catch (bizErr) {
        if (bizErr?.code === "INVALID_PLAN") {
          return res.status(400).json({ error: bizErr.message || "plan inválido" });
        }
        if (bizErr?.code === "NO_MP") {
          return res.status(500).send("MP token not configured");
        }
        if (bizErr?.code === "MP_HTTP") {
          return res.status(bizErr.status || 502).send(String(bizErr.mpBody || ""));
        }
        throw bizErr;
      }
    } catch (err) {
      if (err.code === "resource-exhausted") {
        return res.status(429).json({ error: err.message || "Muitas requisições.", retryAfter: 60 });
      }
      console.error("[planCreatePreference] error:", err);
      return res.status(500).json({ error: String(err?.message || err) });
    }
  }),
);

/** Mesmo fluxo de [planCreatePreference] com auth via Callable (recomendado no Web — evita 401 por header). */
export const planCreatePreferenceCall = onCall(
  { secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL], timeoutSeconds: 45, memory: "256MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login novamente.");
    }
    await checkRateLimit("planCreatePreference", getCallableIdentifier(request));
    const uid = request.auth.uid;
    const email = normalizeEmail(request.auth.token?.email || "");
    const { plan, installationId, returnUrl, notificationUrl } = request.data || {};
    console.log(
      JSON.stringify({
        evt: "planCreatePreference_auth_diag",
        domain: "planos_app",
        transport: "callable",
        uidHint: `${String(uid).slice(0, 10)}…`,
        hasPlan: !!plan,
        adminProjectId: process.env.GCLOUD_PROJECT || PROJECT_ID || "",
      }),
    );
    if (!plan) {
      throw new HttpsError(
        "invalid-argument",
        "plan é obrigatório (mensal|anual|basic_monthly|intermediate_monthly|pro_monthly|pro_yearly)",
      );
    }
    const platformToken = await getPlatformMpAccessTokenStrict({
      flow: "planCreatePreferenceCall",
    });
    if (!platformToken.ok) {
      throw new HttpsError("failed-precondition", "MP platform token não configurado");
    }
    const WEB_BASE =
      (await S_WEB_BASE_URL.value()) || process.env.WEB_BASE_URL || "https://app.mastepalm.com.br";
    if (hasStoreContextInPlanPayload(request.data || {})) {
      throw new HttpsError(
        "invalid-argument",
        "Payload inválido para plano: contexto de loja não é permitido.",
      );
    }
    try {
      return await executePlanPreferenceCheckout({
        tokenUid: uid,
        tokenEmail: email,
        planInput: plan,
        installationId,
        returnUrl,
        notificationUrl,
        mpToken: platformToken.token,
        webBase: WEB_BASE,
      });
    } catch (bizErr) {
      if (bizErr?.code === "INVALID_PLAN") {
        throw new HttpsError("invalid-argument", bizErr.message || "plan inválido");
      }
      if (bizErr?.code === "NO_MP") {
        throw new HttpsError("failed-precondition", "MP token não configurado");
      }
      if (bizErr?.code === "MP_HTTP") {
        throw new HttpsError(
          "internal",
          `Mercado Pago: ${String(bizErr.mpBody || "").slice(0, 400)}`,
        );
      }
      console.error("[planCreatePreferenceCall]", bizErr);
      throw new HttpsError("internal", String(bizErr?.message || bizErr));
    }
  },
);

export const planWebhook = onRequest(
  {
    cors: true,
    secrets: [S_MP_ACCESS_TOKEN, S_MP_WEBHOOK_SECRET],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  corsWrap(async (req, res) => {
    try {
      const WEBHOOK_SECRET =
        (await S_MP_WEBHOOK_SECRET.value()) || process.env.MP_WEBHOOK_SECRET || "";
      const sig = validateMercadoPagoWebhookSignature({
        req,
        webhookSecret: WEBHOOK_SECRET,
      });
      if (!sig.ok) {
        const reason = sig.reason || "unknown";
        let evt = "plan_webhook_signature_invalid";
        if (reason === "header_missing") evt = "plan_webhook_signature_missing";
        else if (
          reason === "secret_missing" ||
          reason === "hmac_error" ||
          reason === "unknown"
        ) {
          evt = "plan_webhook_signature_error";
        }
        console.warn(
          JSON.stringify({
            evt,
            reason,
            ...(sig.detail ? { detail: String(sig.detail).slice(0, 200) } : {}),
          }),
        );
        return res.status(401).send("Unauthorized");
      }
      console.log(
        JSON.stringify({
          evt: "plan_webhook_signature_valid",
          dataIdLen: String(sig.dataId || "").length,
        }),
      );

      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "planWebhook",
      });
      if (!platformToken.ok) return res.status(200).send("OK");

      const qTopic = String(req.query?.topic || req.query?.type || "").toLowerCase();
      const bodyType = String(req.body?.type || "").toLowerCase();
      const bodyAction = String(req.body?.action || "").toLowerCase();
      const isSubscriptionAuthorizedPaymentEvent =
        qTopic === "subscription_authorized_payment" ||
        bodyType === "subscription_authorized_payment" ||
        bodyAction === "subscription_authorized_payment";
      const isPreapprovalEvent =
        qTopic === "subscription" ||
        qTopic.includes("preapproval") ||
        bodyType === "subscription" ||
        bodyType.includes("preapproval") ||
        bodyAction.includes("preapproval");
      if (isSubscriptionAuthorizedPaymentEvent) {
        console.log(
          JSON.stringify({
            evt: "PLAN_WEBHOOK_RECEIVED",
            type: bodyType || qTopic || "subscription_authorized_payment",
            action: bodyAction || "subscription_authorized_payment",
            id:
              String(req.body?.data?.id || req.query?.["data.id"] || req.body?.id || req.query?.id || ""),
          }),
        );
      }
      if (isPreapprovalEvent) {
        const preId = extractMercadoPagoWebhookDataId(req);
        if (preId && isRecurringPlanBillingEnabled()) {
          await handlePreapprovalWebhookNotification({
            db,
            token: platformToken.token,
            preapprovalId: preId,
            nowTs,
            normalizePlanId,
          });
          return res.status(200).send("OK");
        }
      }

      const body = req.body || {};
      const query = req.query || {};
      const paymentId = body?.data?.id || query["data.id"] || body?.id || query?.id;
      if (!paymentId) return res.status(200).send("ok");

      const r = await fetchWithTimeout(
        `https://api.mercadopago.com/v1/payments/${paymentId}`,
        { headers: { Authorization: `Bearer ${platformToken.token}` } },
        15000
      );

      if (!r.ok) {
        const txt = await r.text();
        console.error("[planWebhook] get payment error:", txt);
        return res.status(200).send("ok");
      }

      const payment = await r.json();
      if (String(payment?.metadata?.lojaId || "").trim()) {
        console.warn(
          JSON.stringify({
            evt: "plan_webhook_store_event_ignored",
            flow: "planWebhook",
            domain: "planos_app",
            credentialScope: "platform",
            paymentId: String(paymentId),
            lojaId: String(payment.metadata.lojaId),
          }),
        );
        return res.status(200).send("OK");
      }

      const consumed = await tryProcessPlanOrderWebhook({
        db,
        payment,
        paymentId,
        nowTs,
        normalizePlanId,
        mapCheckoutStatus,
        activatePlanForUser,
      });
      if (consumed) return res.status(200).send("OK");

      const status = payment.status;
      const checkoutStatus = mapCheckoutStatus(status);
      const externalRef = payment.external_reference || "";
      const md = payment.metadata || {};
      const preferenceId = payment.order?.id || payment.preference_id || md.preference_id || null;
      const userEmailFromMd = String(md.user_email || md.email || payment.payer?.email || "")
        .trim()
        .toLowerCase();

      let uid = md.uid || md.userId || md.user_id || null;
      let plan = md.normalized_plan_id || md.plan || md.plano_id || null;

      // Fallback 1: lookup em checkout_planos (preference/external/email estrito)
      let checkoutDoc = null;
      let checkoutSource = "none";
      let checkoutAmbiguous = false;
      try {
        const checkoutLookup = await findCheckoutByPayment({
          preferenceId,
          externalRef,
          userEmail: userEmailFromMd,
          expectedPlanId: plan,
        });
        checkoutDoc = checkoutLookup.doc;
        checkoutSource = checkoutLookup.source;
        checkoutAmbiguous = checkoutLookup.ambiguous === true;
        if (checkoutDoc) {
          const c = checkoutDoc.data() || {};
          uid = uid || c.userId || null;
          plan = plan || c.normalizedPlanId || c.planoId || null;
        } else if (checkoutAmbiguous) {
          console.warn(
            "[PlanosWebhook] Ambiguidade no fallback por email; checkout NÃO será associado",
            JSON.stringify({ paymentId, userEmailFromMd, preferenceId, externalRef })
          );
        }
      } catch (e) {
        console.warn("[PlanosWebhook] Falha ao localizar checkout_planos:", e?.message || e);
      }

      // Formato recorrente: mprec|uid|plan (createPlanSubscription)
      const recurringExternalRef = parseExternalReferenceMpRecurring(externalRef);
      if ((!uid || !plan) && recurringExternalRef) {
        uid = uid || recurringExternalRef.uid;
        plan = plan || recurringExternalRef.canonicalPlanId;
      }

      // Formato legado: uid|plan (planCreatePreference)
      if ((!uid || !plan) && externalRef.includes("|") && !externalRef.startsWith("mprec|")) {
        const parts = externalRef.split("|");
        uid = uid || parts[0];
        plan = plan || parts[1];
      }

      // Formato 2: plano_mensal_123 ou plano_anual_123 (CheckoutService Flutter)
      if (externalRef.startsWith("plano_") && !uid) {
        const match = externalRef.match(/^plano_(mensal|anual)_/);
        plan = plan || (match ? match[1] : null);
        const userEmail = userEmailFromMd;
        if (userEmail) {
          try {
            const userRecord = await admin.auth().getUserByEmail(userEmail);
            uid = userRecord.uid;
          } catch (e) {
            console.warn("[planWebhook] getUserByEmail não encontrou:", userEmail, e.message);
          }
        }
      }

      // Fallback 2: resolver uid por e-mail
      if (!uid && userEmailFromMd) {
        try {
          const userRecord = await admin.auth().getUserByEmail(userEmailFromMd);
          uid = userRecord.uid;
        } catch (e) {
          console.warn("[PlanosWebhook] getUserByEmail fallback falhou:", userEmailFromMd, e?.message || e);
        }
      }

      plan = normalizePlanId(plan);

      // Idempotência explícita para approved
      const processedRef = db.collection("processed_plan_payments").doc(String(paymentId));
      if (status === "approved") {
        let skipApproved = false;
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(processedRef);
          const d = snap.exists ? snap.data() || {} : {};
          if (snap.exists && d.status === "approved") {
            skipApproved = true;
            return;
          }
          tx.set(
            processedRef,
            {
              paymentId: String(paymentId),
              status: "processing",
              rawStatus: String(status || ""),
              updatedAt: nowTs,
              createdAt: d.createdAt || nowTs,
            },
            { merge: true }
          );
        });
        if (skipApproved) {
          console.warn("[PlanosWebhook] payment já processado (dedupe):", paymentId);
          return res.status(200).send("OK");
        }
      }

      // Atualiza auditoria de checkout independentemente da ativação canônica
      if (checkoutDoc) {
        const update = {
          status: checkoutStatus,
          rawStatus: String(status || ""),
          paymentId: String(paymentId || ""),
          updatedAt: nowTs,
          paidAt: status === "approved" ? nowTs : null,
          lookupSource: checkoutSource,
          failureReason:
            status === "approved"
              ? null
              : String(payment.status_detail || payment.status || "payment_not_approved"),
        };
        await checkoutDoc.ref.set(update, { merge: true });
      } else {
        console.warn(
          "[PlanosWebhook] checkout_planos não encontrado",
          JSON.stringify({ paymentId, preferenceId, externalRef, userEmailFromMd })
        );
      }

      if (!uid) {
        console.warn("[planWebhook] uid não resolvido, externalRef:", externalRef, "metadata:", md);
        return res.status(200).send("OK");
      }

      if (status === "approved") {
        const preapId = payment.preapproval_id || payment.preapproval?.id;
        const billingExtras =
          preapId && isRecurringPlanBillingEnabled()
            ? {
                provider: "mercado_pago",
                billingVersion: 2,
                billingSource: "mp_subscription_payment",
                billingMode: "recurring",
                planStatus: "active",
                providerSubscriptionId: String(preapId),
                mercadoPagoPreapprovalId: String(preapId),
                subscriptionId: String(preapId),
                planLastSyncedAt: nowTs,
              }
            : undefined;
        if (billingExtras) {
          console.log(
            JSON.stringify({
              evt: "plan_v2_payment_webhook",
              uid: String(uid),
              paymentId: String(paymentId),
              planId: String(plan || ""),
              providerSubscriptionId: String(preapId),
              billingVersion: 2,
              billingSource: "mp_subscription_payment",
            }),
          );
          console.log(
            JSON.stringify({
              evt: "PLAN_RECURRING_PAYMENT_CONFIRMED",
              uid: String(uid),
              paymentId: String(paymentId),
              preapprovalId: String(preapId),
            }),
          );
        }
        await activatePlanForUser({
          uid,
          plan:
            plan ||
            (String(payment.description || "").toLowerCase().includes("anual") ? "anual" : "mensal"),
          paymentId: String(paymentId),
          status: "active",
          amount: payment.transaction_amount,
          billingExtras,
        });
        if (billingExtras?.billingMode === "recurring") {
          console.log(
            JSON.stringify({
              evt: "PLAN_USER_ACTIVATED",
              uid: String(uid),
              planId: String(plan || ""),
              billingMode: "recurring",
            }),
          );
        }
        await processedRef.set(
          {
            paymentId: String(paymentId),
            processedAt: nowTs,
            uid: uid || null,
            checkoutId: checkoutDoc?.id || null,
            status: "approved",
            rawStatus: String(status || ""),
          },
          { merge: true }
        );
      } else {
        await db
          .collection("users")
          .doc(uid)
          .set(
            {
              // Canônico: não ativa plano em falha
              status: checkoutStatus === "pending" ? "pending" : "inactive",
              updatedAt: nowTs,
            },
            { merge: true }
          );
      }

      return res.status(200).send("OK");
    } catch (err) {
      console.error("[planWebhook] error:", err);
      return res.status(200).send("OK");
    }
  })
);

// ---------- Planos: assinatura recorrente MP (preapproval) — USE_RECURRING_PLAN_BILLING no ambiente ----------
export const createPlanSubscription = onCall(
  { secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL], timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit("createPlanSubscription", getCallableIdentifier(request));
      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "createPlanSubscription",
      });
      if (!platformToken.ok) {
        throw new HttpsError("failed-precondition", "MP platform token não configurado");
      }
      if (hasStoreContextInPlanPayload(request.data || {})) {
        throw new HttpsError(
          "invalid-argument",
          "Payload inválido para plano: contexto de loja não é permitido.",
        );
      }
      const webBase =
        (await S_WEB_BASE_URL.value()) || process.env.WEB_BASE_URL || PUBLIC_SITE_ORIGIN;
      const prices = {
        PRICE_BASIC_MONTHLY,
        PRICE_INTERMEDIATE_MONTHLY,
        PRICE_PRO_MONTHLY,
        PRICE_PRO_YEARLY,
      };
      return await runCreatePlanSubscription({
        db,
        request,
        token: platformToken.token,
        webBase,
        prices,
        planTitleForMp,
        normalizePlanId,
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[createPlanSubscription]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  }
);

export const cancelPlanSubscription = onCall(
  { secrets: [S_MP_ACCESS_TOKEN], timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit("cancelPlanSubscription", getCallableIdentifier(request));
      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "cancelPlanSubscription",
      });
      if (!platformToken.ok) {
        throw new HttpsError("failed-precondition", "MP platform token não configurado");
      }
      return await runCancelPlanSubscription({ db, request, token: platformToken.token });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[cancelPlanSubscription]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  }
);

export const reactivatePlanSubscription = onCall(
  { secrets: [S_MP_ACCESS_TOKEN], timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit("reactivatePlanSubscription", getCallableIdentifier(request));
      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "reactivatePlanSubscription",
      });
      if (!platformToken.ok) {
        throw new HttpsError("failed-precondition", "MP platform token não configurado");
      }
      return await runReactivatePlanSubscription({ db, request, token: platformToken.token });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[reactivatePlanSubscription]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  }
);

export const syncPlanSubscription = onCall(
  { secrets: [S_MP_ACCESS_TOKEN], timeoutSeconds: 45, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit("syncPlanSubscription", getCallableIdentifier(request));
      const platformToken = await getPlatformMpAccessTokenStrict({
        flow: "syncPlanSubscription",
      });
      if (!platformToken.ok) {
        throw new HttpsError("failed-precondition", "MP platform token não configurado");
      }
      return await runSyncPlanSubscription({
        db,
        request,
        token: platformToken.token,
        normalizePlanId,
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[syncPlanSubscription]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  }
);

/** Somente root (e-mail em ROOT_ACCOUNT_EMAILS): leitura de billing/plano de outra conta por UID ou e-mail. Sem escrita. */
export const getPlanBillingSnapshotForSupport = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit(
        "getPlanBillingSnapshotForSupport",
        getCallableIdentifier(request),
      );
      return await runGetPlanBillingSnapshotForSupport({
        db,
        admin,
        request,
        normalizePlanId,
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[getPlanBillingSnapshotForSupport]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  }
);

/** Root: forense operacional leve do pagamento catálogo MP (Firestore persistido; sem logs GCP). */
export const getMpCatalogPaymentSupportSnapshot = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    try {
      await checkRateLimit(
        "getMpCatalogPaymentSupportSnapshot",
        getCallableIdentifier(request),
      );
      return await runMpCatalogPaymentSupportSnapshot({ db, request });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[getMpCatalogPaymentSupportSnapshot]", e);
      throw new HttpsError("internal", String(e?.message || e));
    }
  },
);

// ======================= SUBDOMÍNIOS AUTOMÁTICOS (Firebase Hosting) ==================
async function createHostingDomain(domainName) {
  if (!PROJECT_ID || !HOSTING_SITE_ID) {
    throw new Error("PROJECT_ID/HOSTING_SITE_ID não configurados");
  }

  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const client = await auth.getClient();
  const accessToken = await client.getAccessToken();

  const url = `https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT_ID}/sites/${HOSTING_SITE_ID}/domains`;
  const body = { site: HOSTING_SITE_ID, domainName };

  console.log("[hosting] Criando domínio:", body);
  const r = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken.token || accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
    20000
  );

  const j = await r.json();
  console.log("[hosting] API status:", r.status, j);

  const msg = String(j?.error?.message || "");
  if (!r.ok && !msg.includes("already exists")) {
    throw new Error(`Erro criando domínio: ${r.status} ${JSON.stringify(j)}`);
  }
  return j;
}

async function waitDomainActive(domainName, timeoutMs = 120000) {
  if (!HOSTING_SITE_ID) throw new Error("HOSTING_SITE_ID não configurado");

  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const client = await auth.getClient();
  const accessToken = await client.getAccessToken();

  const url = `https://firebasehosting.googleapis.com/v1beta1/sites/${HOSTING_SITE_ID}/domains/${encodeURIComponent(
    domainName
  )}`;

  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const r = await fetchWithTimeout(
      url,
      { headers: { Authorization: `Bearer ${accessToken.token || accessToken}` } },
      10000
    );
    const j = await r.json();
    if (j?.status === "ACTIVE") return j;
    await sleep(4000);
  }
  return null;
}

export const provisionSubdomain = onRequest(
  { cors: true, timeoutSeconds: 60, memory: "256MiB" },
  corsWrap(async (req, res) => {
    try {
      const identifier = getClientIdentifier(req);
      await checkRateLimit("provisionSubdomain", identifier);

      const subdomain =
        (req.method === "POST" ? req.body?.subdomain : req.query?.subdomain) || "";

      if (!validSubdomain(subdomain)) return res.status(400).json({ error: "Subdomínio inválido" });
      if (!HOSTING_SITE_ID || !PROJECT_ID)
        return res.status(500).json({ error: "PROJECT_ID/HOSTING_SITE_ID não configurados" });

      const domainName = `${subdomain}.${ROOT_DOMAIN}`;
      await createHostingDomain(domainName);
      const details = await waitDomainActive(domainName);

      return res.json({
        ok: true,
        domainName,
        siteId: HOSTING_SITE_ID,
        status: details?.status || "PENDING",
        details,
      });
    } catch (e) {
      if (e.code === "resource-exhausted") {
        return res.status(429).json({ error: e.message || "Muitas requisições.", retryAfter: 60 });
      }
      console.error(e);
      return res.status(500).json({ error: String(e) });
    }
  })
);

// ======================================================================
// NOTIFICAÇÃO ADMIN AO CRIAR PRÉ-PEDIDO (catálogo web e APK)
// Cria notificação no servidor para não depender de permissão do cliente (web anônimo)
// Envia email + push FCM para o dono da loja
// ======================================================================
export const onPrePedidoCreated = onDocumentCreated(
  {
    document: `${COLLECTION_LOJAS}/{lojaId}/pre_pedidos/{pedidoId}`,
    secrets: [S_SMTP_EMAIL, S_SMTP_PASSWORD],
  },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const pedidoId = event?.params?.pedidoId;
    const snap = event.data;
    if (!snap?.exists) return;
    const data = snap.data() || {};
    const cliente = data.cliente || {};
    const clienteNome = cliente.nome || "Cliente";
    const valorTotal = Number(data.total) ?? 0;
    const vendedorRef = data.vendedorRef || null;
    const pagamento = (data.pagamento || "").toString();
    const origemCheckout = (data.origemCheckout || "").toString();
    const isWhatsApp = origemCheckout === "whatsapp";
    const pagamentoConfirmado = pagamento === "gateway" || pagamento === "mercadopago" || pagamento === "Mercado Pago";
    let vendedorNome = null;
    if (vendedorRef) {
      try {
        const vendedorDoc = await db.collection(COLLECTION_LOJAS).doc(lojaId).collection("vendedores").doc(vendedorRef).get();
        if (vendedorDoc.exists) vendedorNome = vendedorDoc.data()?.nome ?? "Vendedor";
      } catch (_) {}
    }
    const origem = vendedorRef ? "catalogo_vendedor" : "catalogo_web";
    try {
      const lojaDoc = await db.collection(COLLECTION_LOJAS).doc(lojaId).get();
      if (!lojaDoc.exists) return;
      const lojaData = lojaDoc.data() || {};
      const adminUid = lojaData.ownerUid ?? lojaData.adminUid ?? "";
      let adminEmail = (lojaData.ownerEmail ?? lojaData.adminEmail ?? "").toString().trim();
      if (!adminEmail && lojaData.owner && typeof lojaData.owner === "object") {
        adminEmail = (lojaData.owner.email ?? "").toString().trim();
      }
      if (!adminUid) {
        console.warn("[onPrePedidoCreated] Admin não encontrado para loja", lojaId);
        return;
      }
      const lojaNome = String(lojaData.nome || lojaData.name || "Sua loja").trim() || "Sua loja";
      const codRef = pedidoCodigoCurto(pedidoId);
      const itensTexto = formatPrePedidoItensResumoEmail(data.itens);
      let titulo;
      if (isWhatsApp) {
        titulo = "📱 Pedido finalizado por WhatsApp";
      } else {
        titulo = pagamentoConfirmado
          ? "🎉 Pedido confirmado! Mais uma venda realizada!"
          : "🛍️ Novo pedido pelo catálogo – alguém quer comprar!";
      }
      const valorStr = valorTotal.toFixed(2).replace(".", ",");
      let mensagem = `Cliente: ${clienteNome}\nValor: R$ ${valorStr}`;
      if (vendedorNome) mensagem += `\nVendedor: ${vendedorNome}`;
      if (isWhatsApp) {
        mensagem += "\n\n📲 Cliente enviou pelo WhatsApp – confira e confirme o pedido.";
      } else {
        mensagem += pagamentoConfirmado
          ? "\n\n✅ Pagamento confirmado – aproveite esse momento!"
          : "\n\n⏳ Aguardando confirmação do pagamento – toque para ver detalhes";
      }
      await db.collection(COLLECTION_LOJAS).doc(lojaId).collection("notificacoes").add({
        destinatarioUid: adminUid,
        destinatarioEmail: adminEmail,
        tipo: "novaVenda",
        titulo,
        mensagem,
        pedidoId,
        storeId: lojaId,
        valor: valorTotal,
        lida: false,
        criadaEm: nowTs,
        dados: { clienteNome, origem, vendedorNome, pagamentoConfirmado },
      });
      console.log("[onPrePedidoCreated] Notificação criada para admin:", pedidoId);

      // Push FCM para o admin (notificação na barra de status com app fechado; toque abre tela de pedidos)
      try {
        const userDoc = await db.collection("users").doc(adminUid).get();
        const fcmToken = userDoc.exists ? (userDoc.data()?.fcmToken || "").trim() : "";
        if (fcmToken.length > 0) {
          const messaging = getMessaging();
          const bodyShort = mensagem.split("\n").slice(0, 2).join("\n");
          await messaging.send({
            token: fcmToken,
            notification: { title: titulo, body: bodyShort },
            data: { lojaId, storeId: lojaId, pedidoId: String(pedidoId || "") },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          });
          console.log("[onPrePedidoCreated] Push FCM enviado para admin");
        }
      } catch (fcmErr) {
        console.warn("[onPrePedidoCreated] FCM push (não bloqueia):", fcmErr.message || fcmErr);
      }

      // E-mails (servidor: funciona no catálogo web; SMTP no app não roda no browser)
      const smtpUser = ((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
      const smtpPass = ((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();
      if (smtpUser && smtpPass) {
        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: { user: smtpUser, pass: smtpPass },
        });
        const origemPedido = isWhatsApp
          ? "O cliente concluiu a compra pelo WhatsApp. Acesse a tela de Pré-pedidos no MasterPalm, revise com calma e confirme quando fizer sentido."
          : pagamentoConfirmado
            ? "O pedido entrou com pagamento confirmado no gateway. Aproveite esse resultado e siga com a separação e o envio no seu ritmo."
            : "O pedido chegou pelo catálogo. Abra Pré-pedidos no MasterPalm, confira itens, forma de pagamento e só confirme após checar o recebimento no banco.";
        const corpoVendedor =
          `Parabéns! A loja "${lojaNome}" acabou de receber um novo pedido — e isso merece comemorar! Cada venda é um voto de confiança no seu negócio.\n\n` +
          `${origemPedido}\n\n` +
          `Antes de confirmar o pedido, confira se o valor caiu na sua conta (PIX, cartão ou o meio que vocês combinaram) e se tudo bate com a venda. Só avance com segurança após isso.\n\n` +
          `--- Dados do pedido ---\n` +
          `Código: ${codRef}\n` +
          `ID do pedido: ${pedidoId}\n` +
          `Cliente: ${clienteNome}\n` +
          (vendedorNome ? `Indicação / vendedor: ${vendedorNome}\n` : "") +
          `Valor total: R$ ${valorStr}\n` +
          `Forma de pagamento: ${pagamento || "—"}\n\n` +
          `Itens:\n${itensTexto}\n` +
          `Acesse o app MasterPalm e abra Pré-pedidos para endereço completo e detalhes.\n\n` +
          `Boa venda! — MasterPalm`;
        const assuntoVendedor = isWhatsApp
          ? `🎉 ${lojaNome}: novo pedido via WhatsApp (#${codRef})`
          : pagamentoConfirmado
            ? `🎉 Venda confirmada! ${lojaNome} (#${codRef})`
            : `🎉 Novo pedido no catálogo — ${lojaNome} (#${codRef})`;
        if (adminEmail && adminEmail.trim().length > 0) {
          try {
            await transporter.sendMail({
              from: `"MasterPalm" <${smtpUser}>`,
              to: adminEmail.trim(),
              subject: assuntoVendedor,
              text: corpoVendedor,
            });
            console.log("[onPrePedidoCreated] Email enviado para admin:", adminEmail);
          } catch (mailErr) {
            console.warn("[onPrePedidoCreated] Email admin (não bloqueia):", mailErr.message || mailErr);
          }
        }
        // E-mail "recebido" ao cliente: onPrePedidoClienteEmail (deduplicação + templates)
        const clienteEmail = normalizeEmail(cliente.email || "");
        if (clienteEmail && clienteEmail.includes("@") && !clienteEmail.startsWith("catalogo+")) {
          console.log("[onPrePedidoCreated] E-mail ao cliente será tratado por onPrePedidoClienteEmail");
        } else {
          console.log(
            "[onPrePedidoCreated] Cliente sem e-mail válido — onPrePedidoClienteEmail não enviará ao comprador",
          );
        }
      } else {
        console.log("[onPrePedidoCreated] SMTP não configurado — e-mails de pré-pedido não enviados");
      }
    } catch (e) {
      console.error("[onPrePedidoCreated] Erro:", e);
    }
  }
);

/** E-mails ao cliente por etapa de status (catálogo) + deduplicação em emailsStatusEnviados* */
export const onPrePedidoClienteEmail = createOnPrePedidoClienteEmail(S_SMTP_EMAIL, S_SMTP_PASSWORD);

// ======================================================================
// ESPELHO PÚBLICO SANITIZADO DE STATUS DE PEDIDO
// Mantém apenas os campos mínimos em uma coleção pública separada.
// A exclusão do privado é tratada no app interno para diferenciar cancelar x excluir.
// ======================================================================
export const syncPedidoStatusPublico = onDocumentWritten(
  {
    document: `${COLLECTION_LOJAS}/{lojaId}/pre_pedidos/{pedidoId}`,
  },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const pedidoId = event?.params?.pedidoId;
    const after = event.data?.after;

    if (!lojaId || !pedidoId) return;

    if (!after?.exists) {
      try {
        await db
          .collection(COLLECTION_LOJAS)
          .doc(lojaId)
          .collection(COLLECTION_PEDIDO_STATUS_PUBLICO)
          .doc(pedidoId)
          .delete();
        console.log("[syncPedidoStatusPublico] pre_pedido deletado – pedido_status_publico limpo:", pedidoId);
      } catch (e) {
        console.error("[syncPedidoStatusPublico] Erro ao limpar pedido_status_publico no delete:", e);
      }
      return;
    }

    try {
      const afterData = after.data() || {};
      const payload = buildPedidoStatusPublico(lojaId, pedidoId, afterData);
      await db
        .collection(COLLECTION_LOJAS)
        .doc(lojaId)
        .collection(COLLECTION_PEDIDO_STATUS_PUBLICO)
        .doc(pedidoId)
        .set(payload, { merge: false });
      await upsertClientePortalFromPedido(lojaId, pedidoId, afterData);
      await writeOrderLojaIndex(db, pedidoId, lojaId, "pre_pedidos");
      console.log("[syncPedidoStatusPublico] Espelho público atualizado:", pedidoId);
    } catch (e) {
      console.error("[syncPedidoStatusPublico] Erro:", e);
    }
  },
);

/** Espelha `config/payments` → `config/payments_public` sem segredos (lojas legadas + qualquer write em payments). */
export const syncPaymentsPublicFromPaymentsConfig = onDocumentWritten(
  { document: `${COLLECTION_LOJAS}/{lojaId}/config/payments`, memory: "256MiB" },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    if (!lojaId) return;
    const after = event.data?.after;
    const pubRef = db
      .collection(COLLECTION_LOJAS)
      .doc(String(lojaId))
      .collection("config")
      .doc("payments_public");
    try {
      if (!after?.exists) {
        await pubRef.delete().catch(() => {});
        return;
      }
      const raw = after.data() || {};
      const stripped = stripPaymentsSecretsForPublic(raw);
      await pubRef.set(
        { ...stripped, updatedAt: FieldValue.serverTimestamp() },
        { merge: false },
      );
    } catch (e) {
      console.error("[syncPaymentsPublicFromPaymentsConfig]", String(lojaId), e);
    }
  },
);

export const syncClientePortalProfile = onDocumentWritten(
  {
    document: `${COLLECTION_LOJAS}/{lojaId}/clientes/{clienteId}`,
  },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const clienteId = event?.params?.clienteId;
    const after = event.data?.after;

    if (!lojaId || !clienteId || !after?.exists) return;

    try {
      await syncClientePortalFromCliente(lojaId, clienteId, after.data() || {});
      console.log("[syncClientePortalProfile] Perfil portal sincronizado:", clienteId);
    } catch (e) {
      console.error("[syncClientePortalProfile] Erro:", e);
    }
  },
);

// ======================================================================
// NOTIFICAÇÃO ADMIN AO CRIAR PEDIDO PENDENTE (catálogo PIX/WhatsApp)
// Envia email + push FCM para o dono da loja
// ======================================================================
export const onPedidoPendenteCreated = onDocumentCreated(
  {
    document: `${COLLECTION_LOJAS}/{lojaId}/pedidos_pendentes/{pedidoId}`,
    secrets: [S_SMTP_EMAIL, S_SMTP_PASSWORD],
  },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const pedidoId = event?.params?.pedidoId;
    const snap = event.data;
    if (!snap?.exists) return;
    const data = snap.data() || {};
    const tipo = (data.tipo || "").toString();
    if (tipo !== "catalogo_web" && tipo !== "catalogo_vendedor") return;
    const cliente = data.cliente || {};
    const clienteNome = cliente.nome || "Cliente";
    const valorTotal = Number(data.total) ?? 0;
    const vendedorNome = data.vendedorNome || null;
    const titulo = "🛍️ Novo pedido pelo catálogo – alguém quer comprar!";
    const valorStr = valorTotal.toFixed(2).replace(".", ",");
    let mensagem = `Cliente: ${clienteNome}\nValor: R$ ${valorStr}`;
    if (vendedorNome) mensagem += `\nVendedor: ${vendedorNome}`;
    mensagem += "\n\n⏳ Aguardando confirmação do pagamento – toque para ver detalhes";
    try {
      const lojaDoc = await db.collection(COLLECTION_LOJAS).doc(lojaId).get();
      if (!lojaDoc.exists) return;
      const lojaData = lojaDoc.data() || {};
      const adminUid = lojaData.ownerUid ?? lojaData.adminUid ?? "";
      let adminEmail = (lojaData.ownerEmail ?? lojaData.adminEmail ?? "").toString().trim();
      if (!adminEmail && lojaData.owner && typeof lojaData.owner === "object") {
        adminEmail = (lojaData.owner.email ?? "").toString().trim();
      }
      if (!adminUid) {
        console.warn("[onPedidoPendenteCreated] Admin não encontrado para loja", lojaId);
        return;
      }
      const origem = vendedorNome ? "catalogo_vendedor" : "catalogo_web";

      // Push FCM
      try {
        const userDoc = await db.collection("users").doc(adminUid).get();
        const fcmToken = userDoc.exists ? (userDoc.data()?.fcmToken || "").trim() : "";
        if (fcmToken.length > 0) {
          const messaging = getMessaging();
          const bodyShort = mensagem.split("\n").slice(0, 2).join("\n");
          await messaging.send({
            token: fcmToken,
            notification: { title: titulo, body: bodyShort },
            data: { lojaId, storeId: lojaId, pedidoId: String(pedidoId || "") },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          });
          console.log("[onPedidoPendenteCreated] Push FCM enviado para admin");
        }
      } catch (fcmErr) {
        console.warn("[onPedidoPendenteCreated] FCM push (não bloqueia):", fcmErr.message || fcmErr);
      }

      // Email
      if (adminEmail && adminEmail.trim().length > 0) {
        try {
          const smtpUser = ((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
          const smtpPass = ((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();
          if (smtpUser && smtpPass) {
            const transporter = nodemailer.createTransport({
              service: "gmail",
              auth: { user: smtpUser, pass: smtpPass },
            });
            const corpo = `${mensagem}\n\nAcesse o app para ver os detalhes do pedido.`;
            await transporter.sendMail({
              from: `"MasterPalm" <${smtpUser}>`,
              to: adminEmail.trim(),
              subject: titulo,
              text: corpo,
            });
            console.log("[onPedidoPendenteCreated] Email enviado para admin:", adminEmail);
          }
        } catch (mailErr) {
          console.warn("[onPedidoPendenteCreated] Email (não bloqueia):", mailErr.message || mailErr);
        }
      }
    } catch (e) {
      console.error("[onPedidoPendenteCreated] Erro:", e);
    }
  }
);

export const onLojaCreated = onDocumentCreated(
  { document: `${COLLECTION_LOJAS}/{lojaId}` },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const snap = event.data;

    if (!HOSTING_SITE_ID || !PROJECT_ID) {
      console.error("PROJECT_ID/HOSTING_SITE_ID não configurados");
      return;
    }
    if (!validSubdomain(lojaId)) {
      console.warn("lojaId inválido:", lojaId);
      return;
    }

    const domainName = `${lojaId}.${ROOT_DOMAIN}`;

    try {
      await createHostingDomain(domainName);
      const details = await waitDomainActive(domainName);
      const publicUrl = `https://${domainName}`;

      await snap.ref.set(
        {
          publicUrl,
          hostingSiteId: HOSTING_SITE_ID,
          hostingStatus: details?.status || "PENDING",
          updatedAt: nowTs,
        },
        { merge: true }
      );

      console.log("[hosting] criado:", publicUrl, "status:", details?.status);
    } catch (e) {
      console.error("Falha ao provisionar domínio:", lojaId, e);
      await snap.ref.set({ hostingError: String(e), updatedAt: nowTs }, { merge: true });
    }
  }
);

// ======================================================================
// ÍNDICE LINK CURTO: loja criada/atualizada → catalog_redirect_index
// ======================================================================
export const onLojaWrittenSyncCatalogRedirect = onDocumentWritten(
  { document: `${COLLECTION_LOJAS}/{lojaId}` },
  async (event) => {
    const lojaId = event?.params?.lojaId;
    const after = event.data?.after;
    if (!after?.exists) return;
    try {
      const { syncCatalogRedirectIndex } = await import("./src/catalogRedirectIndex.js");
      const data = after.data() || {};
      await syncCatalogRedirectIndex(db, lojaId, data);
    } catch (e) {
      console.error("[onLojaWrittenSyncCatalogRedirect]", e);
    }
  }
);

// ======================================================================
// PUBLICAÇÃO AUTOMÁTICA DE LOJA (draft_config + draft_produtos)
// ======================================================================
export const publishLojaDraft = onDocumentWritten(
  { document: `${COLLECTION_LOJAS}/{lojaId}/draft_config/config`, timeoutSeconds: 120, memory: "512MiB" },
  async (event) => {
    const lojaId = event.params?.lojaId;
    const before = event.data?.before;
    const after = event.data?.after;

    if (!after?.exists) return;

    const oldData = before?.data() || {};
    const newData = after.data() || {};

    const oldFlag = !!oldData.admin_publish;
    const newFlag = !!newData.admin_publish;

    if (!newFlag || oldFlag === newFlag) {
      console.log(`[publishLojaDraft] Ignorando, admin_publish não mudou para true (lojaId=${lojaId})`);
      return;
    }

    console.log(`[publishLojaDraft] Publicando LOJA: ${lojaId}`);

    const lojaRef = db.collection(COLLECTION_LOJAS).doc(String(lojaId));
    const cfg = newData;

    await lojaRef.set({ ...cfg, updatedAt: nowTs }, { merge: true });

    const cores = cfg.cores || {};
    const whats = (cfg.whatsapp || "").toString().replace(/\D/g, "");

    const theme = {
      bg: cores.cor_fundo || "#FFFFFF",
      primary: cores.cor_primaria || "#111111",
      text: cores.cor_texto || "#111111",
    };

    const generalRef = lojaRef.collection("settings").doc("general");
    const generalSnap = await generalRef.get();
    const generalOld = generalSnap.exists ? (generalSnap.data() || {}) : {};

    await generalRef.set(
      {
        catalog: { public: true, createdAt: generalOld.createdAt || nowTs },
        theme,
        whatsappE164: whats ? `+55${whats}` : generalOld.whatsappE164 || "",
        updatedAt: nowTs,
      },
      { merge: true }
    );

    const draftProdCol = lojaRef.collection("draft_produtos");
    const draftSnap = await draftProdCol.get();

    console.log(`[publishLojaDraft] Encontrados ${draftSnap.size} produtos em draft_produtos para loja ${lojaId}`);

    const batch = db.batch();

    draftSnap.forEach((doc) => {
      const prodId = doc.id;
      const data = doc.data() || {};

      const baseData = {
        ...data,
        id: data.id || prodId,
        updatedAt: nowTs,
      };

      const prodRef = lojaRef.collection("produtos").doc(prodId);
      batch.set(prodRef, baseData, { merge: true });
    });

    // volta flag
    const draftCfgRef = lojaRef.collection("draft_config").doc("config");
    batch.set(draftCfgRef, { admin_publish: false, updatedAt: nowTs }, { merge: true });

    await batch.commit();
    console.log(`[publishLojaDraft] Publicação concluída para loja ${lojaId}`);
  }
);

// ============================== LINK CURTO – /c/:short → /loja/:slug ==============================
const WEB_BASE = process.env.WEB_BASE_URL || "https://app.mastepalm.com.br";

export const redirectCatalogo = onRequest(
  { cors: true },
  corsWrap(async (req, res) => {
    if (req.method !== "GET") return res.status(405).send("Method not allowed");
    const short = (req.path.replace(/^\/c\/?/, "") || "").trim().toLowerCase();
    if (!short) {
      return res.redirect(302, `${WEB_BASE}/`);
    }
    try {
      const { getRedirectTarget, syncCatalogRedirectIndex } = await import("./src/catalogRedirectIndex.js");
      const target = await getRedirectTarget(db, short);
      if (target && target.slug) {
        return res.redirect(302, `${WEB_BASE}/loja/${target.slug}`);
      }
      // Fallback: itera lojas (links antigos ainda não no índice)
      const lojasSnap = await db.collection(COLLECTION_LOJAS).get();
      for (const doc of lojasSnap.docs) {
        const d = doc.data();
        const slug = (d.slug || "").toString().trim();
        const linkCurto = (d.linkCurto || "").toString().trim().toLowerCase();
        if (linkCurto === short || slug === short) {
          const slugDisplay = slug || doc.id;
          try {
            await syncCatalogRedirectIndex(db, doc.id, { slug, linkCurto: d.linkCurto });
          } catch (_) {}
          return res.redirect(302, `${WEB_BASE}/loja/${slugDisplay}`);
        }
      }
      return res.redirect(302, `${WEB_BASE}/`);
    } catch (e) {
      console.error("redirectCatalogo error:", e);
      return res.redirect(302, `${WEB_BASE}/`);
    }
  })
);

// ============================== DEV/SEED – CRIAR/ATUALIZAR PEDIDO ==============================
// 🔒 Desabilitado em produção: só funciona com emulador (FUNCTIONS_EMULATOR=true)
export const devCreateOrder = onRequest(
  { cors: true },
  corsWrap(async (req, res) => {
    try {
      if (process.env.FUNCTIONS_EMULATOR !== "true") {
        return res.status(404).json({ error: "Not available in production" });
      }
      const token = (req.query?.token || req.headers["x-internal-token"] || "").toString();
      if (token !== "SO-INTERNO-123") {
        return res.status(401).json({ error: "unauthorized" });
      }

      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const { lojaId, orderId, data } = req.body || {};
      if (!lojaId || !orderId || !data) {
        return res.status(400).json({ error: "lojaId, orderId e data são obrigatórios" });
      }

      if (Array.isArray(data.items)) {
        data.items = data.items.map((it) => ({
          name: it?.name || "",
          qty: Number(it?.qty || 0),
          price: Number(String(it?.price ?? 0).toString().replace(",", ".")),
          imageUrl: it?.imageUrl || null,
          productId: it?.productId || null,
        }));
      } else {
        data.items = [];
      }

      const ref = db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("pedidos")
        .doc(String(orderId));

      await ref.set(
        { ...data, status: data.status || "pending", updatedAt: nowTs, createdAt: nowTs },
        { merge: true }
      );

      return res.json({ ok: true, path: `/${COLLECTION_LOJAS}/${lojaId}/pedidos/${orderId}` });
    } catch (e) {
      console.error("devCreateOrder error:", e);
      return res.status(500).json({ error: String(e) });
    }
  })
);

// ✅ Exporta os callables do plano (arquivo separado)
export {
  ensureUserPlan,
  rootGrantPlan,
  activateUserTrial90d,
  cancelPlanRenewalAtPeriodEnd,
  reactivatePlanRenewal,
  scheduledReconcileExpiredPaidPlans,
};

// ============================== WHATSAPP – Confirmação de pedido (Canais Meta) ==============================

/**
 * Envia mensagem de confirmação de pedido via WhatsApp Cloud API.
 * Usa as credenciais da loja em lojas/{lojaId}/canais/whatsapp (phone_number_id, access_token).
 *
 * Body: { lojaId, phone, message }
 * - phone: número do destinatário (com ou sem máscara; será normalizado para só dígitos)
 * - message: texto da mensagem (pode ser confirmação de pedido + número da sorte montados no app)
 */
async function sendWhatsAppViaGraph(lojaId, phone, message) {
  const canalSnap = await db
    .collection(COLLECTION_LOJAS)
    .doc(String(lojaId))
    .collection("canais")
    .doc("whatsapp")
    .get();

  if (!canalSnap.exists) {
    throw new Error("WhatsApp não configurado para esta loja. Configure em Canais Meta.");
  }
  const canal = canalSnap.data() || {};
  if (!canal.enabled) {
    throw new Error("Canal WhatsApp está desabilitado para esta loja.");
  }
  const phoneNumberId = (canal.phone_number_id || "").trim();
  const accessToken = (canal.access_token || "").trim();
  if (!phoneNumberId || !accessToken) {
    throw new Error("WhatsApp: phone_number_id ou access_token não configurados.");
  }

  const to = String(phone).replace(/\D/g, "");
  if (to.length < 10) {
    throw new Error("Número de telefone inválido.");
  }

  const url = `https://graph.facebook.com/v18.0/${phoneNumberId}/messages`;
  const r = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: to,
        type: "text",
        text: { body: message },
      }),
    },
    15000
  );

  if (!r.ok) {
    const errText = await r.text();
    console.error("[sendWhatsAppOrderConfirmation] API error:", r.status, errText);
    throw new Error(`WhatsApp API: ${r.status} ${errText}`);
  }
  return r.json();
}

export const sendWhatsAppOrderConfirmation = onRequest(
  { cors: true, timeoutSeconds: 30, memory: "256MiB" },
  corsWrap(async (req, res) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const body = req.body || {};
      const { lojaId, phone, message } = body;

      if (!lojaId || !phone || !message) {
        return res.status(400).json({
          error: "Parâmetros obrigatórios: lojaId, phone, message",
        });
      }

      const identifier = getClientIdentifier(req);
      await checkRateLimit("sendWhatsAppOrderConfirmation", identifier);

      await sendWhatsAppViaGraph(lojaId, phone, String(message));
      return res.status(200).json({ ok: true, message: "Mensagem enviada" });
    } catch (e) {
      console.error("[sendWhatsAppOrderConfirmation] error:", e);
      const status = e.message?.includes("não configurado") || e.message?.includes("inválido") ? 400 : 500;
      return res.status(status).json({
        error: e.message || "Erro ao enviar WhatsApp",
      });
    }
  })
);

// ============================== CLIENTE CATÁLOGO (LEITURA SEGURA) ==============================
/**
 * Callable: busca dados mínimos do cliente para catálogo (perfil, carrinho, favoritos, portalToken).
 * Usa Admin SDK; valida email para evitar leitura indevida.
 * NUNCA retorna senhaHash, cpf ou dados sensíveis.
 */
export const getClienteCatalog = onCall(
  { timeoutSeconds: 15 },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("getClienteCatalog", identifier);

      const { lojaId, clienteId, email } = request.data || {};
      const lojaIdStr = (lojaId || "").toString().trim();
      const clienteIdStr = (clienteId || "").toString().trim();
      const emailNorm = (email || "").toString().trim().toLowerCase();

      if (!lojaIdStr || !clienteIdStr || !emailNorm) {
        throw new HttpsError("invalid-argument", "lojaId, clienteId e email são obrigatórios.");
      }

      const docRef = db
        .collection(COLLECTION_LOJAS)
        .doc(lojaIdStr)
        .collection(COLLECTION_CLIENTES)
        .doc(clienteIdStr);

      const snap = await docRef.get();
      if (!snap.exists) {
        return null;
      }

      const data = snap.data() || {};
      const docEmail = (data.email || "").toString().trim().toLowerCase();
      if (docEmail !== emailNorm) {
        return null;
      }

      let portalToken = (data.portalToken || "").toString().trim();
      if (!portalToken) {
        portalToken = crypto.randomBytes(24).toString("base64url");
        await docRef.update({ portalToken });
      }

      const safe = {
        nome: data.nome ?? "",
        email: data.email ?? "",
        telefone: data.telefone ?? "",
        portalToken,
        endereco: data.endereco && typeof data.endereco === "object" ? data.endereco : null,
        enderecoFormatado: (data.enderecoFormatado || "").toString().trim() || null,
        carrinho: Array.isArray(data.carrinho) ? data.carrinho : [],
        favoritos: Array.isArray(data.favoritos) ? data.favoritos : [],
        cupons: Array.isArray(data.cupons) ? data.cupons : [],
        pedidos: Array.isArray(data.pedidos) ? data.pedidos : [],
      };
      return safe;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[getClienteCatalog] error:", err);
      throw new HttpsError(
        "internal",
        err?.message || "Erro ao buscar dados do cliente."
      );
    }
  }
);

// ============================== DOMÍNIO PRÓPRIO DO CATÁLOGO ==============================
export const catalogDomainSubmitRequest = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("catalogDomainSubmitRequest", identifier);
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login necessário.");
      }
      const { lojaId, dominioUserInput, providerId } = request.data || {};
      const out = await runCatalogDomainSubmit(db, {
        auth: request.auth,
        lojaId,
        dominioUserInput,
        providerId,
      });
      return out;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[catalogDomainSubmitRequest] error:", err);
      throw new HttpsError("internal", err?.message || "Erro ao registrar domínio.");
    }
  },
);

export const catalogDomainVerifyDns = onCall(
  { timeoutSeconds: 45, memory: "256MiB" },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("catalogDomainVerifyDns", identifier);
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login necessário.");
      }
      const { lojaId, hostNormalized } = request.data || {};
      const out = await runCatalogDomainVerify(db, {
        auth: request.auth,
        lojaId,
        hostNormalized,
      });
      return out;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[catalogDomainVerifyDns] error:", err);
      throw new HttpsError("internal", err?.message || "Erro ao verificar DNS.");
    }
  },
);

// ============================== REDEFINIÇÃO DE SENHA (CATÁLOGO WEB) ==============================
/**
 * Callable: solicitar redefinição de senha do cliente do catálogo.
 * Usado na Web (navegador não consegue enviar SMTP). Gera código de 6 dígitos,
 * salva em lojas/{lojaId}/clientes e envia o código por email.
 * Configure SMTP_EMAIL e SMTP_PASSWORD no .env (local) ou nas variáveis de ambiente das Functions.
 */
function gerarCodigo6Digitos() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

export const solicitarRedefinicaoSenhaCatalogo = onCall(
  { timeoutSeconds: 25, memory: "256MiB", secrets: [S_SMTP_EMAIL, S_SMTP_PASSWORD] },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("solicitarRedefinicaoSenhaCatalogo", identifier);

      const { lojaId, email } = request.data || {};
      const emailNorm = (email || "").toString().trim().toLowerCase();
      const lojaIdStr = (lojaId || "").toString().trim();

      if (!lojaIdStr || !emailNorm) {
        throw new HttpsError("invalid-argument", "Informe o email.");
      }

      const clientesSnap = await db
        .collection(COLLECTION_LOJAS)
        .doc(lojaIdStr)
        .collection("clientes")
        .where("email", "==", emailNorm)
        .limit(1)
        .get();

      if (clientesSnap.empty) {
        throw new HttpsError("not-found", "Email não encontrado nesta loja.");
      }

      const doc = clientesSnap.docs[0];
      const codigo = gerarCodigo6Digitos();
      const expiraEm = new Date(Date.now() + 15 * 60 * 1000);

      await doc.ref.update({
        senhaResetCodigo: codigo,
        senhaResetExpiraEm: Timestamp.fromDate(expiraEm),
      });

      const smtpUser = ((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
      const smtpPass = ((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();
      if (!smtpUser || !smtpPass) {
        await doc.ref.update({
          senhaResetCodigo: FieldValue.delete(),
          senhaResetExpiraEm: FieldValue.delete(),
        });
        throw new HttpsError(
          "failed-precondition",
          "Envio de email não configurado no servidor. Entre em contato com a loja."
        );
      }

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: { user: smtpUser, pass: smtpPass },
      });

      const mensagem =
        `Seu código para redefinir a senha é: ${codigo}\n\n` +
        "Ele é válido por 15 minutos. Se você não solicitou essa alteração, ignore este email.";
      try {
        await transporter.sendMail({
          from: `"Suporte MasterPalm" <${smtpUser}>`,
          to: emailNorm,
          subject: "Código para redefinir sua senha - MasterPalm",
          text: mensagem,
        });
      } catch (mailErr) {
        await doc.ref.update({
          senhaResetCodigo: FieldValue.delete(),
          senhaResetExpiraEm: FieldValue.delete(),
        });
        console.error("[solicitarRedefinicaoSenhaCatalogo] sendMail error:", mailErr);
        throw new HttpsError(
          "internal",
          "Não foi possível enviar o email. Tente novamente ou entre em contato com a loja."
        );
      }

      return { success: true };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[solicitarRedefinicaoSenhaCatalogo] error:", err);
      throw new HttpsError(
        "internal",
        err.message || "Não foi possível enviar o email. Tente novamente ou entre em contato com a loja."
      );
    }
  }
);

// ============================== VERIFICAÇÃO DE E-MAIL (QUALQUER DOMÍNIO) ==============================
/**
 * Callable: enviar e-mail de verificação para qualquer provedor (Hotmail/Gmail/Outlook etc).
 * Motivo: o envio padrão do Firebase pode ter entregabilidade diferente por provedor.
 * Aqui geramos o link via Admin SDK e enviamos via SMTP já usado no projeto.
 */
export const enviarEmailVerificacao = onCall(
  { timeoutSeconds: 25, memory: "256MiB", secrets: [S_SMTP_EMAIL, S_SMTP_PASSWORD] },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("enviarEmailVerificacao", identifier);

      const { email } = request.data || {};
      const emailNorm = (email || "").toString().trim().toLowerCase();
      if (!emailNorm) {
        throw new HttpsError("invalid-argument", "Informe o e-mail.");
      }

      // Segurança: se estiver autenticado, rejeita disparos para outro e-mail.
      const authedEmail = (request.auth?.token?.email || "")
        .toString()
        .trim()
        .toLowerCase();
      if (request.auth?.uid && authedEmail && authedEmail !== emailNorm) {
        throw new HttpsError("permission-denied", "O e-mail não corresponde ao usuário autenticado.");
      }

      console.log(
        `[enviarEmailVerificacao] chamado email=${emailNorm} authUid=${request.auth?.uid || "none"} authEmail=${authedEmail || "none"}`
      );

      const verificationLink = await admin
        .auth()
        .generateEmailVerificationLink(emailNorm);

      // Não logar o link completo (token sensível). Log apenas o host.
      try {
        const host = new URL(verificationLink).host;
        console.log(`[enviarEmailVerificacao] link gerado host=${host}`);
      } catch (_) {
        console.log(`[enviarEmailVerificacao] link gerado (host desconhecido)`);
      }

      const smtpUser = ((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
      const smtpPass = ((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();
      if (!smtpUser || !smtpPass) {
        throw new HttpsError(
          "failed-precondition",
          "Envio de email não configurado no servidor. Entre em contato com o administrador."
        );
      }

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: { user: smtpUser, pass: smtpPass },
      });

      const assunto = "Confirme seu e-mail - MasterPalm";
      const corpoTexto =
        `Olá!\n\n` +
        `Para confirmar seu e-mail, clique no link abaixo:\n${verificationLink}\n\n` +
        `Se você não solicitou este cadastro, ignore este e-mail.\n\n` +
        `Atenciosamente,\nMasterPalm`;

      const corpoHtml = `
<!DOCTYPE html>
<html>
  <body style="font-family: Arial, sans-serif; font-size: 14px; color: #333; line-height: 1.5;">
    <div style="margin: 18px 0;">
      <p>Olá!</p>
      <p>Para confirmar seu e-mail, clique no botão abaixo:</p>
      <p>
        <a href="${verificationLink}"
           style="display: inline-block; padding: 10px 16px; background:#6366F1; color:#fff; text-decoration:none; border-radius:6px;">
          Confirmar e-mail
        </a>
      </p>
      <p style="margin-top:18px;">
        Se o botão não funcionar, copie e cole o link no navegador:
        <br/>
        <code style="word-break: break-all;">${verificationLink}</code>
      </p>
      <p>Se você não solicitou este cadastro, ignore este e-mail.</p>
      <p>Atenciosamente,<br/>MasterPalm</p>
    </div>
  </body>
</html>`;

      await transporter.sendMail({
        from: `"MasterPalm" <${smtpUser}>`,
        to: emailNorm,
        subject: assunto,
        text: corpoTexto,
        html: corpoHtml,
      });

      console.log(`[enviarEmailVerificacao] sendMail OK destinatario=${emailNorm}`);
      return { success: true };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[enviarEmailVerificacao] error:", err?.message || err, err?.stack || "");
      throw new HttpsError("internal", err?.message || "Falha ao enviar e-mail de verificação.");
    }
  }
);

// ============================== IA LOJA (Descrição + Dicas) ==============================
// Usa Gemini (grátis) por padrão; OpenAI (ChatGPT, pago) se quiser. GEMINI: aistudio.google.com/app/apikey

export const sugerirDescricaoProduto = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("sugerirDescricaoProduto", identifier);
      const geminiKey = (await S_GEMINI_API_KEY.value()) || process.env.GEMINI_API_KEY || "";
      const openaiKey = (await S_OPENAI_API_KEY.value()) || process.env.OPENAI_API_KEY || "";
      if (!geminiKey.trim() && !openaiKey.trim()) {
        throw new HttpsError(
          "failed-precondition",
          "IA não configurada. Configure GEMINI_API_KEY (grátis) em aistudio.google.com e defina no Firebase."
        );
      }
      if (geminiKey.trim()) console.log("[sugerirDescricaoProduto] Usando Gemini");
      else console.log("[sugerirDescricaoProduto] Usando OpenAI");
      const { nome, categoria, subcategoria, preferirModelo } = request.data || {};
      const texto = await aiSugerirDescricao(openaiKey, geminiKey, {
        nome: nome || "",
        categoria: categoria || "",
        subcategoria: subcategoria || "",
        preferirModelo: preferirModelo || "openai",
      });
      return { descricao: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[sugerirDescricaoProduto] error:", err);
      throw new HttpsError("internal", err.message || "Erro ao gerar sugestão de descrição.");
    }
  }
);

export const chatDicasLoja = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const identifier = getCallableIdentifier(request);
      await checkRateLimit("chatDicasLoja", identifier);
      const geminiKey = (await S_GEMINI_API_KEY.value()) || process.env.GEMINI_API_KEY || "";
      const openaiKey = (await S_OPENAI_API_KEY.value()) || process.env.OPENAI_API_KEY || "";
      if (!geminiKey.trim() && !openaiKey.trim()) {
        throw new HttpsError(
          "failed-precondition",
          "IA não configurada. Configure GEMINI_API_KEY (grátis) em aistudio.google.com e defina no Firebase."
        );
      }
      if (geminiKey.trim()) console.log("[chatDicasLoja] Usando Gemini");
      else console.log("[chatDicasLoja] Usando OpenAI");
      const { mensagem, historico, preferirModelo, modo, nomeTela } = request.data || {};
      const resposta = await aiChatDicas(openaiKey, geminiKey, {
        mensagem: mensagem || "",
        historico: Array.isArray(historico) ? historico : [],
        preferirModelo: preferirModelo || "openai",
        modo: modo || "",
        nomeTela: nomeTela || "",
      });
      return { resposta };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[chatDicasLoja] error:", err);
      throw new HttpsError("internal", err.message || "Erro ao obter resposta da IA.");
    }
  }
);

// Helper: obtém chaves IA e valida
async function getIaKeys(request, callableName) {
  const identifier = getCallableIdentifier(request);
  await checkRateLimit(callableName, identifier);
  const geminiKey = (await S_GEMINI_API_KEY.value()) || process.env.GEMINI_API_KEY || "";
  const openaiKey = (await S_OPENAI_API_KEY.value()) || process.env.OPENAI_API_KEY || "";
  if (!geminiKey.trim() && !openaiKey.trim()) {
    throw new HttpsError("failed-precondition", "IA não configurada. Configure GEMINI_API_KEY em aistudio.google.com e defina no Firebase.");
  }
  return { geminiKey, openaiKey };
}

export const sugerirTituloProduto = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirTituloProduto");
      const { nome, categoria, preferirModelo } = request.data || {};
      const texto = await aiSugerirTitulo(openaiKey, geminiKey, { nome: nome || "", categoria: categoria || "", preferirModelo: preferirModelo || "openai" });
      return { titulo: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao gerar título.");
    }
  }
);

export const sugerirVariacoesDescricao = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirVariacoesDescricao");
      const { nome, descricaoAtual, preferirModelo } = request.data || {};
      const out = await aiSugerirVariacoesDescricao(openaiKey, geminiKey, { nome: nome || "", descricaoAtual: descricaoAtual || "", preferirModelo: preferirModelo || "openai" });
      return out;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao gerar variações.");
    }
  }
);

export const sugerirLegendaInstagram = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirLegendaInstagram");
      const { produtoNome, nome, descricao, preferirModelo } = request.data || {};
      const texto = await aiSugerirLegendaInstagram(openaiKey, geminiKey, {
        produtoNome: produtoNome || nome || "",
        descricao: descricao || "",
        preferirModelo: preferirModelo || "openai",
      });
      return { legenda: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao gerar legenda.");
    }
  }
);

export const sugerirMensagemWhatsApp = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirMensagemWhatsApp");
      const { tipo, contexto, preferirModelo } = request.data || {};
      const texto = await aiSugerirMensagemWhatsApp(openaiKey, geminiKey, { tipo: tipo || "promocao", contexto: contexto || "", preferirModelo: preferirModelo || "openai" });
      return { mensagem: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao gerar mensagem.");
    }
  }
);

export const sugerirCategoriaSubcategoria = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirCategoriaSubcategoria");
      const { nome, descricao, preferirModelo } = request.data || {};
      const out = await aiSugerirCategoriaSubcategoria(openaiKey, geminiKey, { nome: nome || "", descricao: descricao || "", preferirModelo: preferirModelo || "openai" });
      return out;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao sugerir categoria.");
    }
  }
);

export const sugerirPromocaoEstoqueParado = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirPromocaoEstoqueParado");
      const { produtos, preferirModelo } = request.data || {};
      const texto = await aiSugerirPromocaoEstoqueParado(openaiKey, geminiKey, { produtos: Array.isArray(produtos) ? produtos : [], preferirModelo: preferirModelo || "openai" });
      return { sugestao: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao sugerir promoção.");
    }
  }
);

export const analiseVendasNatural = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "analiseVendasNatural");
      const { pergunta, resumoVendas, preferirModelo } = request.data || {};
      const texto = await aiAnaliseVendasNatural(openaiKey, geminiKey, {
        pergunta: pergunta || "",
        resumoVendas: resumoVendas || "",
        preferirModelo: preferirModelo || "openai",
      });
      return { resposta: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro na análise.");
    }
  }
);

export const chatAtendimentoCatalogo = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "chatAtendimentoCatalogo");
      const { pergunta, contexto, preferirModelo } = request.data || {};
      const texto = await aiChatAtendimentoCatalogo(openaiKey, geminiKey, {
        pergunta: pergunta || "",
        contexto: contexto || {},
        preferirModelo: preferirModelo || "openai",
      });
      return { resposta: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro no atendimento.");
    }
  }
);

export const sugerirPrecoCombo = onCall(
  { timeoutSeconds: 60, memory: "256MiB", secrets: [S_GEMINI_API_KEY, S_OPENAI_API_KEY] },
  async (request) => {
    try {
      const { geminiKey, openaiKey } = await getIaKeys(request, "sugerirPrecoCombo");
      const { itens, somaItens, preferirModelo } = request.data || {};
      const texto = await aiSugerirPrecoCombo(openaiKey, geminiKey, {
        itens: Array.isArray(itens) ? itens : [],
        somaItens: typeof somaItens === "number" ? somaItens : 0,
        preferirModelo: preferirModelo || "openai",
      });
      return { sugestao: texto };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err.message || "Erro ao sugerir preço do combo.");
    }
  }
);

// ============================== CUPONS E NÚMEROS DA SORTE ==============================

/**
 * Gera código aleatório para cupom
 */
function gerarCodigoCupom(prefixo = 'CUPOM', tamanho = 8) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let codigo = prefixo + '-';
  for (let i = 0; i < tamanho; i++) {
    codigo += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return codigo;
}

/**
 * Número da sorte — 5 dígitos (10000–99999), alinhado ao app / mpWebhookPromo.
 */
function gerarNumeroSorte() {
  return String(Math.floor(10000 + Math.random() * 90000));
}

/**
 * Cloud Function: Gerar cupom e número da sorte após pedido finalizado
 */
export const gerarCupomNumeroSorte = onRequest(
  { cors: true },
  corsWrap(async (req, res) => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).send('Método não permitido');
      }

      const {
        lojaId,
        clienteId,
        pedidoId,
        valorPedido,
        clienteEmail,
        clienteNome,
        clienteTelefone
      } = req.body;

      // Validações
      if (!lojaId || !clienteId || !pedidoId) {
        return res.status(400).json({
          error: 'Parâmetros obrigatórios: lojaId, clienteId, pedidoId'
        });
      }

      // Rate limiting (evita abuso)
      const identifier = getClientIdentifier(req);
      await checkRateLimit("gerarCupomNumeroSorte", identifier);

      // Idempotência (retry pós-pagamento não duplica cupom)
      const idemKey = `${lojaId}:${pedidoId}:${clienteId}`;
      const { hit, result } = await checkIdempotency("gerarCupomNumeroSorte", idemKey);
      if (hit && result) {
        return res.status(200).json(result);
      }

      // Gerar cupom de desconto (10% para próxima compra)
      const codigoCupom = gerarCodigoCupom('CUPOM', 8);
      const dataValidade = new Date();
      dataValidade.setDate(dataValidade.getDate() + 30); // Válido por 30 dias

      const cupom = {
        codigo: codigoCupom,
        desconto: 10, // 10% de desconto
        validade: dataValidade.toLocaleDateString('pt-BR'),
        usado: false,
        criadoEm: nowTs,
        pedidoOrigem: pedidoId,
      };

      // Gerar número da sorte
      const numeroSorte = gerarNumeroSorte();

      // Adicionar cupom e número ao documento do cliente
      const clienteRef = db
        .collection(COLLECTION_LOJAS)
        .doc(lojaId)
        .collection('clientes')
        .doc(clienteId);

      await clienteRef.update({
        cupons: FieldValue.arrayUnion(cupom),
        pedidos: FieldValue.arrayUnion({
          id: pedidoId,
          numeroSorte: numeroSorte,
          data: new Date().toLocaleDateString('pt-BR'),
          valor: valorPedido || 0,
          status: 'Confirmado'
        })
      });

      // Registrar número da sorte na campanha ativa (coleção canônica: campanhas_sorteio)
      try {
        const agora = new Date();
        const campanhasSnapshot = await db
          .collection(COLLECTION_LOJAS)
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .where('ativa', '==', true)
          .where('dataInicio', '<=', agora)
          .where('dataFim', '>=', agora)
          .limit(1)
          .get();

        if (!campanhasSnapshot.empty) {
          const campanhaDoc = campanhasSnapshot.docs[0];
          await campanhaDoc.ref.collection('participantes').add({
            clienteId: clienteId,
            numeroSorte: numeroSorte,
            pedidoId: pedidoId,
            clienteNome: clienteNome,
            clienteEmail: clienteEmail,
            data: nowTs
          });
        }
      } catch (campErr) {
        console.error('Erro ao registrar na campanha:', campErr);
        // Continuar mesmo se houver erro na campanha
      }

      const response = {
        success: true,
        cupom: cupom,
        numeroSorte: numeroSorte,
        clienteEmail: clienteEmail,
        clienteTelefone: clienteTelefone,
        message: 'Cupom e número da sorte gerados com sucesso!'
      };

      await saveIdempotency("gerarCupomNumeroSorte", idemKey, response);

      return res.status(200).json(response);

    } catch (error) {
      if (error.code === "resource-exhausted") {
        return res.status(429).json({ error: error.message || "Muitas requisições.", retryAfter: 60 });
      }
      console.error('Erro ao gerar cupom e número:', error);
      return res.status(500).json({
        error: 'Erro ao gerar cupom e número da sorte',
        details: error.message
      });
    }
  })
);

// ======================================================================
// NOTIFICAÇÃO DE ATUALIZAÇÃO DO APP (quando apkVersion muda em site_config)
// Envia push FCM para tópico masterpalm_app_updates
// ======================================================================
export const onSiteConfigUpdated = onDocumentWritten(
  { document: "app_config/site_config" },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;

    if (!after?.exists) return;

    const oldData = before?.exists ? (before.data() || {}) : {};
    const newData = after.data() || {};

    const oldVersion = (oldData.apkVersion || "").toString().trim();
    const newVersion = (newData.apkVersion || "").toString().trim();

    if (!newVersion || oldVersion === newVersion) {
      console.log("[onSiteConfigUpdated] apkVersion não mudou, ignorando");
      return;
    }

    console.log(`[onSiteConfigUpdated] Nova versão: ${oldVersion} → ${newVersion}. Enviando push.`);

    try {
      const messaging = getMessaging();
      await messaging.send({
        topic: "masterpalm_app_updates",
        notification: {
          title: "Atualização disponível",
          body: `Nova versão ${newVersion} do MasterPalm. Toque para atualizar.`
        },
        data: {
          type: "app_update",
          version: newVersion,
          downloadUrl: (newData.apkDownloadUrl || "").toString()
        },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } }
      });
      console.log("[onSiteConfigUpdated] Push FCM enviado para tópico masterpalm_app_updates");
    } catch (e) {
      console.error("[onSiteConfigUpdated] Erro ao enviar FCM:", e);
    }
  }
);
