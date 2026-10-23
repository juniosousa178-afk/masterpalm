/**
 * Emulator (Firestore + Auth): matriz de segurança do OAuth Mercado Pago.
 * firebase emulators:exec --only firestore,auth --project demo-mp-oauth "node --test test/mpOAuthSecure.emulator.test.mjs"
 */
import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import {
  runMpOAuthStart,
  handleMpOAuthExchangeHttp,
  buildInitForward,
  buildLegacyCallbackForward,
  hashOAuthValue,
  MP_OAUTH_STATE_COL,
  MP_OAUTH_STATE_TTL_MS,
  MpOAuthError,
} from "../src/mpOAuthSecure.js";

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "FIRESTORE_EMULATOR_HOST obrigatório");
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, "FIREBASE_AUTH_EMULATOR_HOST obrigatório");

const PROJECT = process.env.GCLOUD_PROJECT || "demo-mp-oauth";
if (!getApps().length) initializeApp({ projectId: PROJECT });
const db = getFirestore();
const adminAuth = getAuth();
const ORIGIN = "https://app.example.test";
const APP_ID = "1234567890";
const CLIENT_SECRET = "CLIENT-SECRET-DO-NOT-LOG";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST;

const LOJA_A = "loja-a";
const LOJA_B = "loja-b";
const U = {
  ownerA: { uid: "owner-a", email: "owner-a@test.local" },
  adminA: { uid: "admin-a", email: "admin-a@test.local" },
  sellerA: { uid: "seller-a", email: "seller-a@test.local" },
  inactiveAdminA: { uid: "inactive-admin-a", email: "inactive-a@test.local" },
  storeIdOnlyA: { uid: "storeid-only-a", email: "storeid-a@test.local" },
  ownerB: { uid: "owner-b", email: "owner-b@test.local" },
  ordinary: { uid: "ordinary", email: "ordinary@test.local" },
  legacyRoot: { uid: "legacy-root", email: "masterpalm@gmail.com" },
};
const PASSWORD = "Test#123456";
const tokens = {};
let anonToken;

async function signIn(email) {
  const r = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
  });
  const j = await r.json();
  assert.ok(j.idToken, `login ${email}`);
  return j.idToken;
}

const logs = [];
const log = (m) => logs.push(String(m));
const verifyIdToken = (t) => adminAuth.verifyIdToken(t, true);
const authFromToken = async (t) => { const d = await verifyIdToken(t); return { uid: d.uid, token: d }; };

/** MP simulado: cada code só pode ser trocado uma vez; exige PKCE coerente com o challenge emitido. */
const mp = { codes: new Map(), exchanges: 0, successes: 0, challenges: new Map() };
function mpIssueCode(authUrl) {
  const u = new URL(authUrl);
  const code = `TG-${crypto.randomBytes(8).toString("hex")}`;
  mp.codes.set(code, { used: false, challenge: u.searchParams.get("code_challenge"), userId: String(1000 + mp.codes.size) });
  return { code, state: u.searchParams.get("state") };
}
async function fakeFetch(url, init = {}) {
  if (String(url).endsWith("/oauth/token")) {
    mp.exchanges++;
    await new Promise((r) => setTimeout(r, 15));
    const b = JSON.parse(init.body);
    const entry = mp.codes.get(b.code);
    const pkceOk = entry && b.code_verifier &&
      crypto.createHash("sha256").update(b.code_verifier).digest("base64url") === entry.challenge;
    if (!entry || entry.used || !pkceOk || b.client_secret !== CLIENT_SECRET) {
      return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
    }
    entry.used = true;
    mp.successes++;
    return new Response(JSON.stringify({
      access_token: `APP_USR-SECRET-ACCESS-${entry.userId}`,
      refresh_token: `TG-SECRET-REFRESH-${entry.userId}`,
      public_key: `APP_USR-pk-${entry.userId}`,
      user_id: Number(entry.userId),
    }), { status: 200 });
  }
  if (String(url).endsWith("/users/me")) {
    return new Response(JSON.stringify({ id: 1, email: "mp-account@test.local" }), { status: 200 });
  }
  throw new Error(`unexpected fetch ${url}`);
}

function fakeRes() {
  return {
    statusCode: 0, body: null,
    status(c) { this.statusCode = c; return this; },
    json(b) { this.body = b; return this; },
  };
}
async function exchangeHttp({ token, code, state, extraBody = {}, method = "POST", nowMs }) {
  const req = { method, headers: token ? { authorization: `Bearer ${token}` } : {}, body: { code, state, ...extraBody } };
  const res = fakeRes();
  await handleMpOAuthExchangeHttp(req, res, {
    db, verifyIdToken, appId: APP_ID, clientSecret: CLIENT_SECRET, publicSiteOrigin: ORIGIN,
    fetchImpl: fakeFetch, log, ...(nowMs ? { nowMs } : {}),
  });
  return res;
}
async function start(userKey, lojaId, nowMs) {
  return runMpOAuthStart({
    db, auth: await authFromToken(tokens[userKey]), lojaId, appId: APP_ID, publicSiteOrigin: ORIGIN,
    ...(nowMs ? { nowMs } : {}),
  });
}
async function paymentsOf(lojaId) {
  const s = await db.doc(`lojas/${lojaId}/config/payments`).get();
  return s.exists ? s.data() : null;
}
async function expectStartError(p, code) {
  await assert.rejects(p, (e) => e instanceof MpOAuthError && e.code === code);
}

test.before(async () => {
  for (const u of Object.values(U)) {
    await adminAuth.createUser({ uid: u.uid, email: u.email, password: PASSWORD });
  }
  for (const [k, u] of Object.entries(U)) tokens[k] = await signIn(u.email);
  const r = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  anonToken = (await r.json()).idToken;

  await db.doc(`lojas/${LOJA_A}`).set({ ownerUid: U.ownerA.uid, nome: "A" });
  await db.doc(`lojas/${LOJA_B}`).set({ ownerUid: U.ownerB.uid, nome: "B" });
  await db.doc(`lojas/${LOJA_A}/members/${U.adminA.uid}`).set({ role: "admin" });
  await db.doc(`lojas/${LOJA_A}/members/${U.sellerA.uid}`).set({ role: "seller" });
  await db.doc(`lojas/${LOJA_A}/members/${U.inactiveAdminA.uid}`).set({ role: "admin", ativo: false });
  await db.doc(`users/${U.storeIdOnlyA.uid}`).set({ store_id: LOJA_A, role: "admin" });
  await db.doc(`lojas/${LOJA_B}/config/payments`).set({ mp: { access_token: "APP_USR-B-ORIGINAL", connected: true } });
});

// ---------------- INIT / START ----------------
test("start: dono autorizado cria state v2 server-side (hash, uid, loja, TTL 10min, consumedAt=null)", async () => {
  const now = Date.now();
  const { authUrl, expiresAtMs } = await start("ownerA", LOJA_A, now);
  const u = new URL(authUrl);
  const state = u.searchParams.get("state");
  assert.match(state, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(u.searchParams.get("redirect_uri"), `${ORIGIN}/mp-oauth-callback`);
  assert.equal(u.searchParams.get("code_challenge_method"), "S256");
  assert.ok(!authUrl.includes(LOJA_A), "lojaId não vai na URL");
  assert.equal(expiresAtMs, now + MP_OAUTH_STATE_TTL_MS);
  const rawDoc = await db.collection(MP_OAUTH_STATE_COL).doc(state).get();
  assert.equal(rawDoc.exists, false, "state em claro não é id de documento");
  const d = (await db.collection(MP_OAUTH_STATE_COL).doc(hashOAuthValue(state)).get()).data();
  assert.equal(d.v, 2);
  assert.equal(d.uid, U.ownerA.uid);
  assert.equal(d.lojaId, LOJA_A);
  assert.equal(d.consumedAt, null);
  assert.equal(d.expiresAt.toMillis() - d.createdAt.toMillis(), 10 * 60 * 1000);
});

test("start: admin da loja (members.role=admin) autorizado", async () => {
  const { authUrl } = await start("adminA", LOJA_A);
  assert.ok(authUrl.startsWith("https://auth.mercadopago.com/authorization?"));
});

test("start: vendedor sem autoridade de admin → forbidden", () => expectStartError(start("sellerA", LOJA_A), "forbidden_store"));
test("start: admin inativo → forbidden", () => expectStartError(start("inactiveAdminA", LOJA_A), "forbidden_store"));
test("start: utilizador autenticado comum → forbidden", () => expectStartError(start("ordinary", LOJA_A), "forbidden_store"));
test("start: utilizador de outra loja → forbidden (cross-tenant)", () => expectStartError(start("ownerB", LOJA_A), "forbidden_store"));
test("start: só users.store_id (ponteiro do cliente) não autoriza", () => expectStartError(start("storeIdOnlyA", LOJA_A), "forbidden_store"));
test("start: e-mail root legado não autoriza OAuth de loja alheia", () => expectStartError(start("legacyRoot", LOJA_A), "forbidden_store"));
test("start: loja inexistente → forbidden", () => expectStartError(start("ownerA", "loja-inexistente"), "forbidden_store"));
test("start: lojaId inválido → invalid_loja", async () => {
  await expectStartError(start("ownerA", "../lojas/x"), "invalid_loja");
  await expectStartError(start("ownerA", ""), "invalid_loja");
});
test("start: anónimo → bloqueado", async () => {
  await expectStartError(runMpOAuthStart({ db, auth: await authFromToken(anonToken), lojaId: LOJA_A, appId: APP_ID, publicSiteOrigin: ORIGIN }), "anonymous_forbidden");
});
test("start: sem autenticação → unauthenticated", () =>
  expectStartError(runMpOAuthStart({ db, auth: null, lojaId: LOJA_A, appId: APP_ID, publicSiteOrigin: ORIGIN }), "unauthenticated"));

// ---------------- EXCHANGE ----------------
test("exchange: sem Authorization → 401 e nada gravado", async () => {
  const { authUrl } = await start("ownerA", LOJA_A);
  const { code, state } = mpIssueCode(authUrl);
  const r = await exchangeHttp({ token: null, code, state });
  assert.equal(r.statusCode, 401);
  assert.equal(await paymentsOf(LOJA_A), null);
});

test("exchange: ID token inválido → 401", async () => {
  const r = await exchangeHttp({ token: "not-a-jwt", code: "TG-x", state: "a".repeat(43) });
  assert.equal(r.statusCode, 401);
});

test("exchange: anónimo → 403", async () => {
  const r = await exchangeHttp({ token: anonToken, code: "TG-x", state: "a".repeat(43) });
  assert.equal(r.statusCode, 403);
});

test("exchange: GET → 405", async () => {
  const r = await exchangeHttp({ token: tokens.ownerA, code: "x", state: "y", method: "GET" });
  assert.equal(r.statusCode, 405);
});

test("exchange: state ausente → 400", async () => {
  const r = await exchangeHttp({ token: tokens.ownerA, code: "TG-x", state: "" });
  assert.equal(r.statusCode, 400);
});

test("exchange: state aleatório (bem formado, desconhecido) → 400, MP não chamado", async () => {
  const before = mp.exchanges;
  const r = await exchangeHttp({ token: tokens.ownerA, code: "TG-random", state: crypto.randomBytes(32).toString("base64url") });
  assert.equal(r.statusCode, 400);
  assert.equal(mp.exchanges, before);
});

test("exchange: state legado (base64 JSON com lojaId adulterado) → rejeitado", async () => {
  const legacy = Buffer.from(JSON.stringify({ l: LOJA_B, n: "nonce", t: Date.now() })).toString("base64url");
  const r = await exchangeHttp({ token: tokens.ownerB, code: "TG-legacy", state: legacy });
  assert.equal(r.statusCode, 400);
  const p = await paymentsOf(LOJA_B);
  assert.equal(p.mp.access_token, "APP_USR-B-ORIGINAL");
});

test("exchange: documento de state legado v1 com o mesmo hash → rejeitado", async () => {
  const st = crypto.randomBytes(32).toString("base64url");
  await db.collection(MP_OAUTH_STATE_COL).doc(hashOAuthValue(st)).set({ lojaId: LOJA_B, used: false, expiresAt: Timestamp.fromMillis(Date.now() + 60000) });
  const r = await exchangeHttp({ token: tokens.ownerB, code: "TG-v1", state: st });
  assert.equal(r.statusCode, 400);
});

test("exchange: state expirado → 400, nada gravado", async () => {
  const past = Date.now() - MP_OAUTH_STATE_TTL_MS - 60_000;
  const { authUrl } = await start("ownerA", LOJA_A, past);
  const { code, state } = mpIssueCode(authUrl);
  const before = mp.exchanges;
  const r = await exchangeHttp({ token: tokens.ownerA, code, state });
  assert.equal(r.statusCode, 400);
  assert.equal(mp.exchanges, before);
  assert.equal(await paymentsOf(LOJA_A), null);
});

test("exchange: UID diferente do state (user B usa state de user A) → 403, state intacto, nada gravado", async () => {
  const { authUrl } = await start("ownerA", LOJA_A);
  const { code, state } = mpIssueCode(authUrl);
  const r = await exchangeHttp({ token: tokens.ownerB, code, state });
  assert.equal(r.statusCode, 403);
  const d = (await db.collection(MP_OAUTH_STATE_COL).doc(hashOAuthValue(state)).get()).data();
  assert.equal(d.consumedAt, null);
  assert.equal(await paymentsOf(LOJA_A), null);
  assert.equal((await paymentsOf(LOJA_B)).mp.access_token, "APP_USR-B-ORIGINAL");
});

test("exchange: autoridade revogada entre start e exchange → 403", async () => {
  await db.doc(`lojas/${LOJA_A}/members/tmp-admin`).set({ role: "admin" });
  await adminAuth.createUser({ uid: "tmp-admin", email: "tmp-admin@test.local", password: PASSWORD });
  const t = await signIn("tmp-admin@test.local");
  const { authUrl } = await runMpOAuthStart({ db, auth: await authFromToken(t), lojaId: LOJA_A, appId: APP_ID, publicSiteOrigin: ORIGIN });
  await db.doc(`lojas/${LOJA_A}/members/tmp-admin`).delete();
  const { code, state } = mpIssueCode(authUrl);
  const r = await exchangeHttp({ token: t, code, state });
  assert.equal(r.statusCode, 403);
  assert.equal(await paymentsOf(LOJA_A), null);
});

test("exchange: fluxo válido grava só na loja do state; lojaId do body é ignorado", async () => {
  const { authUrl } = await start("ownerA", LOJA_A);
  const { code, state } = mpIssueCode(authUrl);
  const r = await exchangeHttp({ token: tokens.ownerA, code, state, extraBody: { lojaId: LOJA_B } });
  assert.equal(r.statusCode, 200);
  assert.deepEqual(r.body, { ok: true, lojaId: LOJA_A, connected: true });
  const pa = await paymentsOf(LOJA_A);
  assert.match(pa.mp.access_token, /^APP_USR-SECRET-ACCESS-/);
  assert.equal(pa.mp.oauthConnectedByUid, U.ownerA.uid);
  assert.equal((await paymentsOf(LOJA_B)).mp.access_token, "APP_USR-B-ORIGINAL");
  const pub = (await db.doc(`lojas/${LOJA_A}/config/payments_public`).get()).data();
  assert.equal(pub.mp.access_token, undefined);
  assert.equal(pub.mp.refresh_token, undefined);
  const d = (await db.collection(MP_OAUTH_STATE_COL).doc(hashOAuthValue(state)).get()).data();
  assert.ok(d.consumedAt);
  assert.equal(d.code_verifier, undefined, "code_verifier apagado após uso");
  assert.equal(d.result, "connected");

  // replay: mesmo state + mesmo code
  const ex = mp.exchanges;
  const r2 = await exchangeHttp({ token: tokens.ownerA, code, state });
  assert.equal(r2.statusCode, 400);
  assert.equal(mp.exchanges, ex, "replay não chega ao MP");
});

test("exchange: mesmo code com outro state válido → bloqueado no servidor", async () => {
  const s1 = await start("adminA", LOJA_A);
  const { code, state } = mpIssueCode(s1.authUrl);
  assert.equal((await exchangeHttp({ token: tokens.adminA, code, state })).statusCode, 200);
  const s2 = await start("adminA", LOJA_A);
  const state2 = new URL(s2.authUrl).searchParams.get("state");
  const ex = mp.exchanges;
  const r = await exchangeHttp({ token: tokens.adminA, code, state: state2 });
  assert.equal(r.statusCode, 400);
  assert.equal(mp.exchanges, ex);
});

test("concorrência: 12 callbacks simultâneos com o mesmo state → no máximo 1 sucesso", async () => {
  const { authUrl } = await start("ownerA", LOJA_A);
  const state = new URL(authUrl).searchParams.get("state");
  const codes = Array.from({ length: 12 }, () => mpIssueCode(authUrl).code);
  const succ0 = mp.successes;
  const results = await Promise.all(codes.map((code) => exchangeHttp({ token: tokens.ownerA, code, state })));
  const ok = results.filter((r) => r.statusCode === 200).length;
  assert.equal(ok, 1, `sucessos=${ok}`);
  assert.equal(mp.successes - succ0, 1);
});

test("concorrência: mesmo code em 6 states paralelos → no máximo 1 sucesso", async () => {
  const starts = await Promise.all(Array.from({ length: 6 }, () => start("ownerA", LOJA_A)));
  const { code } = mpIssueCode(starts[0].authUrl);
  const results = await Promise.all(starts.map((s) => exchangeHttp({
    token: tokens.ownerA, code, state: new URL(s.authUrl).searchParams.get("state"),
  })));
  const ok = results.filter((r) => r.statusCode === 200).length;
  assert.ok(ok <= 1, `sucessos=${ok}`);
});

// ---------------- ENTRADAS LEGADAS ----------------
test("mpOAuthInit legado só reencaminha para /mp-oauth-start (sem state, sem MP)", async () => {
  assert.equal(buildInitForward({ lojaId: LOJA_A }, ORIGIN), `${ORIGIN}/mp-oauth-start?lojaId=${LOJA_A}`);
  assert.equal(buildInitForward({ lojaId: "../x" }, ORIGIN), `${ORIGIN}/mp-oauth-start`);
  assert.equal(buildInitForward({}, ORIGIN), `${ORIGIN}/mp-oauth-start`);
});

test("mpOAuthCallback legado nunca troca code: só reencaminha code/state para a página autenticada", async () => {
  const url = buildLegacyCallbackForward({ code: "TG-1", state: "s", lojaId: LOJA_B, l: LOJA_B }, ORIGIN);
  const u = new URL(url);
  assert.equal(u.origin + u.pathname, `${ORIGIN}/mp-oauth-callback`);
  assert.deepEqual([...u.searchParams.keys()].sort(), ["code", "state"]);
});

// ---------------- LOGS ----------------
test("nenhum token/código/segredo/state nos logs", async () => {
  const joined = logs.join("\n");
  for (const needle of ["SECRET-ACCESS", "SECRET-REFRESH", CLIENT_SECRET, "TG-", "code_verifier"]) {
    assert.ok(!joined.includes(needle), `log contém ${needle}`);
  }
  for (const k of mp.codes.keys()) assert.ok(!joined.includes(k));
});
