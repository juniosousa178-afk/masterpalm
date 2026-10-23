/**
 * Mercado Pago OAuth — vínculo conta MP ↔ loja.
 *
 * Invariante: UID autenticado → administra lojaId → servidor cria state (hash, uid, lojaId, TTL, uso único)
 * → autorização MP → troca autenticada pelo MESMO uid → tokens gravados só na loja do state.
 * O lojaId nunca vem do browser depois que o state foi criado.
 */
import crypto from "node:crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

export const MP_AUTH_URL = "https://auth.mercadopago.com/authorization";
export const MP_TOKEN_URL = "https://api.mercadopago.com/oauth/token";
export const MP_USERS_ME_URL = "https://api.mercadopago.com/users/me";
export const MP_OAUTH_STATE_COL = "_mp_oauth_states";
export const MP_OAUTH_CODE_COL = "_mp_oauth_codes";
export const MP_OAUTH_STATE_VERSION = 2;
export const MP_OAUTH_STATE_TTL_MS = 10 * 60 * 1000;

const STATE_RE = /^[A-Za-z0-9_-]{43}$/;
const CODE_RE = /^[A-Za-z0-9._~+/=-]{1,512}$/;
const LOJA_ID_RE = /^[A-Za-z0-9._@-]{1,150}$/;

export class MpOAuthError extends Error {
  /**
   * @param {string} code interno (estável para testes/logs)
   * @param {number} httpStatus
   * @param {string} publicMessage mensagem segura para o cliente
   */
  constructor(code, httpStatus, publicMessage) {
    super(code);
    this.code = code;
    this.httpStatus = httpStatus;
    this.publicMessage = publicMessage;
  }
}

const STATE_INVALID_MSG = "State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.";

export function hashOAuthValue(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

export function newOAuthState() {
  return crypto.randomBytes(32).toString("base64url");
}

export function generateMpPkcePair() {
  const codeVerifier = crypto.randomBytes(32).toString("base64url");
  const codeChallenge = crypto.createHash("sha256").update(codeVerifier).digest("base64url");
  return { codeVerifier, codeChallenge };
}

export function isValidLojaIdForOAuth(lojaId) {
  const s = String(lojaId || "");
  return LOJA_ID_RE.test(s) && s !== "." && s !== ".." && !s.startsWith("__");
}

/**
 * Autoridade canónica do tenant: lojas/{lojaId}.ownerUid ou members/{uid}.role ∈ {owner, admin} (ativo ≠ false).
 * Não usa e-mail, users.store_id, role do cliente nem conta "root".
 */
export async function isMpOAuthStoreAdmin(db, { uid, lojaId }) {
  if (!uid || !isValidLojaIdForOAuth(lojaId)) return false;
  const lojaRef = db.collection("lojas").doc(String(lojaId));
  const [lojaSnap, memberSnap] = await Promise.all([
    lojaRef.get(),
    lojaRef.collection("members").doc(String(uid)).get(),
  ]);
  if (!lojaSnap.exists) return false;
  const loja = lojaSnap.data() || {};
  if (loja.ownerUid && String(loja.ownerUid) === String(uid)) return true;
  if (!memberSnap.exists) return false;
  const m = memberSnap.data() || {};
  if (m.ativo === false) return false;
  const role = String(m.role || "").trim().toLowerCase();
  return role === "owner" || role === "admin";
}

function assertRealUser(auth) {
  if (!auth?.uid) {
    throw new MpOAuthError("unauthenticated", 401, "Faça login para conectar o Mercado Pago.");
  }
  if (auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new MpOAuthError("anonymous_forbidden", 403, "Faça login com a conta da loja para conectar o Mercado Pago.");
  }
}

/**
 * Cria o state server-side e devolve a URL de autorização do MP.
 * @param {{db: FirebaseFirestore.Firestore, auth: {uid: string, token?: object}|null, lojaId: unknown,
 *   appId: string, publicSiteOrigin: string, nowMs?: number}} p
 */
export async function runMpOAuthStart({ db, auth, lojaId, appId, publicSiteOrigin, nowMs = Date.now() }) {
  assertRealUser(auth);
  const loja = String(lojaId || "").trim();
  if (!isValidLojaIdForOAuth(loja)) {
    throw new MpOAuthError("invalid_loja", 400, "lojaId inválido.");
  }
  if (!appId) {
    throw new MpOAuthError("not_configured", 500, "OAuth não configurado no servidor.");
  }
  const allowed = await isMpOAuthStoreAdmin(db, { uid: auth.uid, lojaId: loja });
  if (!allowed) {
    throw new MpOAuthError("forbidden_store", 403, "Sem permissão para conectar o Mercado Pago desta loja.");
  }

  const state = newOAuthState();
  const stateHash = hashOAuthValue(state);
  const { codeVerifier, codeChallenge } = generateMpPkcePair();
  await db.collection(MP_OAUTH_STATE_COL).doc(stateHash).create({
    v: MP_OAUTH_STATE_VERSION,
    stateHash,
    uid: String(auth.uid),
    lojaId: loja,
    createdAt: Timestamp.fromMillis(nowMs),
    expiresAt: Timestamp.fromMillis(nowMs + MP_OAUTH_STATE_TTL_MS),
    consumedAt: null,
    code_verifier: codeVerifier,
  });

  const params = new URLSearchParams({
    client_id: String(appId),
    response_type: "code",
    platform_id: "mp",
    state,
    redirect_uri: `${publicSiteOrigin}/mp-oauth-callback`,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
  });
  return {
    authUrl: `${MP_AUTH_URL}?${params.toString()}`,
    expiresAtMs: nowMs + MP_OAUTH_STATE_TTL_MS,
  };
}

/**
 * Consome o state (uma vez), troca o code e grava as credenciais só na loja do state.
 * @param {{db: FirebaseFirestore.Firestore, auth: {uid: string, token?: object}|null, code: unknown, state: unknown,
 *   appId: string, clientSecret: string, publicSiteOrigin: string, fetchImpl?: typeof fetch, nowMs?: number,
 *   log?: (msg: string) => void}} p
 */
export async function runMpOAuthExchange({
  db, auth, code, state, appId, clientSecret, publicSiteOrigin,
  fetchImpl = fetch, nowMs = Date.now(), log = console.log,
}) {
  assertRealUser(auth);
  const stateStr = String(state || "").trim();
  const codeStr = String(code || "").trim();
  if (!STATE_RE.test(stateStr)) throw new MpOAuthError("state_malformed", 400, STATE_INVALID_MSG);
  if (!CODE_RE.test(codeStr)) throw new MpOAuthError("code_malformed", 400, "Código de autorização ausente ou inválido.");
  if (!appId || !clientSecret) throw new MpOAuthError("not_configured", 500, "OAuth não configurado no servidor.");

  const stateHash = hashOAuthValue(stateStr);
  const stateRef = db.collection(MP_OAUTH_STATE_COL).doc(stateHash);
  const codeRef = db.collection(MP_OAUTH_CODE_COL).doc(hashOAuthValue(codeStr));

  const pre = await stateRef.get();
  const preData = pre.exists ? (pre.data() || {}) : null;
  if (!preData || preData.v !== MP_OAUTH_STATE_VERSION) {
    throw new MpOAuthError("state_unknown", 400, STATE_INVALID_MSG);
  }
  if (String(preData.uid) !== String(auth.uid)) {
    throw new MpOAuthError("state_uid_mismatch", 403, STATE_INVALID_MSG);
  }
  const lojaId = String(preData.lojaId || "");
  if (!(await isMpOAuthStoreAdmin(db, { uid: auth.uid, lojaId }))) {
    throw new MpOAuthError("forbidden_store", 403, "Sem permissão para conectar o Mercado Pago desta loja.");
  }

  const codeVerifier = await db.runTransaction(async (tx) => {
    const [snap, codeSnap] = await Promise.all([tx.get(stateRef), tx.get(codeRef)]);
    const d = snap.exists ? (snap.data() || {}) : null;
    if (!d || d.v !== MP_OAUTH_STATE_VERSION) throw new MpOAuthError("state_unknown", 400, STATE_INVALID_MSG);
    if (String(d.uid) !== String(auth.uid) || String(d.lojaId) !== lojaId) {
      throw new MpOAuthError("state_uid_mismatch", 403, STATE_INVALID_MSG);
    }
    if (d.consumedAt != null) throw new MpOAuthError("state_consumed", 400, STATE_INVALID_MSG);
    const expMs = typeof d.expiresAt?.toMillis === "function" ? d.expiresAt.toMillis() : 0;
    if (!(expMs > nowMs)) throw new MpOAuthError("state_expired", 400, STATE_INVALID_MSG);
    if (codeSnap.exists) throw new MpOAuthError("code_reused", 400, "Código de autorização já utilizado.");
    tx.update(stateRef, { consumedAt: Timestamp.fromMillis(nowMs), consumedByUid: String(auth.uid) });
    tx.create(codeRef, { stateHash, createdAt: Timestamp.fromMillis(nowMs) });
    return String(d.code_verifier || "");
  });

  const finish = (result) => stateRef.update({ result, code_verifier: FieldValue.delete(), completedAt: FieldValue.serverTimestamp() });

  let tokenData;
  try {
    const tokenResp = await fetchImpl(MP_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: appId,
        client_secret: clientSecret,
        code: codeStr,
        grant_type: "authorization_code",
        redirect_uri: `${publicSiteOrigin}/mp-oauth-callback`,
        ...(codeVerifier ? { code_verifier: codeVerifier } : {}),
      }),
      signal: AbortSignal.timeout(12000),
    });
    tokenData = await tokenResp.json().catch(() => ({}));
    if (!tokenResp.ok || !tokenData?.access_token) {
      log(`[mpOAuthExchange] troca recusada pelo MP status=${tokenResp.status} loja=${lojaId}`);
      await finish("exchange_failed");
      throw new MpOAuthError("mp_exchange_failed", 502, "Falha de comunicação com o Mercado Pago.");
    }
  } catch (e) {
    if (e instanceof MpOAuthError) throw e;
    log(`[mpOAuthExchange] erro de rede na troca loja=${lojaId} type=${e?.name || typeof e}`);
    await finish("exchange_error");
    throw new MpOAuthError("mp_exchange_error", 502, "Falha de comunicação com o Mercado Pago.");
  }

  const accessToken = String(tokenData.access_token);
  const refreshToken = tokenData.refresh_token || null;
  const publicKey = tokenData.public_key || null;
  const userId = tokenData.user_id != null ? String(tokenData.user_id) : null;

  let email = null;
  try {
    const userResp = await fetchImpl(MP_USERS_ME_URL, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(8000),
    });
    if (userResp.ok) {
      const u = await userResp.json();
      email = u?.email ?? null;
    }
  } catch (_) {
    log(`[mpOAuthExchange] users/me indisponível loja=${lojaId}`);
  }

  const nowTs = FieldValue.serverTimestamp();
  const cfg = db.collection("lojas").doc(lojaId).collection("config");
  await cfg.doc("payments").set(
    {
      mp: {
        access_token: accessToken,
        token: accessToken,
        refresh_token: refreshToken,
        public_key: publicKey,
        user_id: userId,
        email,
        connected: true,
        oauthConnectedByUid: String(auth.uid),
        oauthConnectedAt: nowTs,
      },
      updatedAt: nowTs,
    },
    { merge: true }
  );
  await cfg.doc("payments_public").set(
    {
      mp: { public_key: publicKey, user_id: userId, email, connected: true },
      updatedAt: nowTs,
    },
    { merge: true }
  );
  await finish("connected");
  log(`[mpOAuthExchange] MP conectado loja=${lojaId} uid=${auth.uid}`);
  return { ok: true, lojaId, connected: true };
}

/** Callback legado: nunca troca code; reencaminha para a página web que exige sessão + state v2. */
export function buildLegacyCallbackForward(query, publicSiteOrigin) {
  const fwd = new URLSearchParams();
  for (const k of ["code", "state", "error", "error_description"]) {
    const v = query?.[k];
    if (typeof v === "string" && v.length > 0 && v.length <= 1024) fwd.set(k, v);
  }
  const qs = fwd.toString();
  return `${publicSiteOrigin}/mp-oauth-callback${qs ? `?${qs}` : ""}`;
}

/** Entrada antiga (/mp-oauth?lojaId=) usada pelo APK: só reencaminha para a página web autenticada. */
export function buildInitForward(query, publicSiteOrigin) {
  const loja = String(query?.lojaId || "").trim();
  const qs = isValidLojaIdForOAuth(loja) ? `?lojaId=${encodeURIComponent(loja)}` : "";
  return `${publicSiteOrigin}/mp-oauth-start${qs}`;
}

/**
 * HTTP POST { code, state } com Authorization: Bearer <Firebase ID token>.
 * @param {{verifyIdToken: (t: string) => Promise<object>}} deps
 */
export async function handleMpOAuthExchangeHttp(req, res, deps) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Método não permitido." });
    return;
  }
  const authz = String(req.headers?.authorization || req.headers?.Authorization || "");
  const m = authz.match(/^Bearer\s+(.+)$/i);
  let auth = null;
  if (m) {
    try {
      const decoded = await deps.verifyIdToken(m[1].trim());
      auth = { uid: decoded.uid, token: decoded };
    } catch (_) {
      auth = null;
    }
  }
  const body = req.body && typeof req.body === "object" ? req.body : {};
  try {
    const out = await runMpOAuthExchange({ ...deps, auth, code: body.code, state: body.state });
    res.status(200).json(out);
  } catch (e) {
    if (e instanceof MpOAuthError) {
      if (e.code !== "unauthenticated") {
        (deps.log || console.log)(`[mpOAuthExchange] rejeitado code=${e.code} uid=${auth?.uid || "none"}`);
      }
      res.status(e.httpStatus).json({ error: e.publicMessage });
      return;
    }
    (deps.log || console.log)(`[mpOAuthExchange] erro interno type=${e?.name || typeof e}`);
    res.status(500).json({ error: "Erro interno ao conectar Mercado Pago." });
  }
}
