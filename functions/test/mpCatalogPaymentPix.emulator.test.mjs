/**
 * Emulator (Firestore): handler mpCatalogPayment — PIX (normalização de valor e erros do provedor),
 * validação, isolamento por loja, retry e back_urls. Mercado Pago simulado; nenhuma chamada externa.
 * firebase emulators:exec --only firestore --project demo-mp-catalog-payment "node --test test/mpCatalogPaymentPix.emulator.test.mjs"
 */
import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";

const EMU = process.env.FIRESTORE_EMULATOR_HOST;
assert.ok(EMU, "FIRESTORE_EMULATOR_HOST obrigatório");
const PROJECT = process.env.GCLOUD_PROJECT || "demo-mp-catalog-payment";
assert.ok(PROJECT.startsWith("demo-"), "use um projeto demo-*");

process.env.MP_ACCESS_TOKEN = "PLATFORM-TOKEN-NOT-USED-BY-CATALOG";
process.env.WEB_BASE_URL = "https://web-base.example.test";
process.env.PROJECT_ID = PROJECT;
delete process.env.WEBHOOK_URL;

const TOKEN_A = `APP_USR-${"a".repeat(40)}`;
const TOKEN_B = `APP_USR-${"b".repeat(40)}`;
const AMOUNT_MSG =
  "Não foi possível gerar o PIX por inconsistência no valor do pedido. Atualize o carrinho e tente novamente.";
const INVALID_MSG = "Dados inválidos para PIX. Verifique e-mail e CPF e tente novamente.";
const DEFAULT_MSG = "Erro ao gerar PIX. Verifique e-mail e CPF e tente novamente.";

const realFetch = globalThis.fetch;
let mpCalls = [];
let mpResponder = () => ({ status: 500, text: "{}" });
globalThis.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.startsWith("https://api.mercadopago.com/")) {
    const auth = String(opts.headers?.Authorization || "");
    mpCalls.push({
      url: u,
      token: auth === `Bearer ${TOKEN_A}` ? "A" : auth === `Bearer ${TOKEN_B}` ? "B" : "?",
      idempotencyKey: opts.headers?.["X-Idempotency-Key"] || null,
      body: JSON.parse(opts.body),
    });
    const r = mpResponder(mpCalls.length);
    return new Response(r.text, { status: r.status, headers: { "content-type": "application/json" } });
  }
  if (/^https?:\/\/(127\.0\.0\.1|localhost)[:/]/.test(u)) return realFetch(url, opts);
  throw new Error(`fetch externo bloqueado no teste: ${u}`);
};

const diag = [];
const origWarn = console.warn;
console.warn = (...a) => {
  if (a[0] === "[PIX-AMOUNT-DIAG]") diag.push(a[1]);
  else origWarn(...a);
};

const { mpCatalogPayment } = await import("../index.js");
const { getFirestore } = await import("firebase-admin/firestore");
const db = getFirestore();

async function reset({ orders = {}, tokenA = TOKEN_A, tokenB = TOKEN_B } = {}) {
  const r = await realFetch(`http://${EMU}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  assert.ok(r.ok, "limpar emulador");
  if (tokenA) await db.doc("lojas/lojaA/config/payments").set({ mp: { access_token: tokenA } });
  if (tokenB) await db.doc("lojas/lojaB/config/payments").set({ mp: { access_token: tokenB } });
  for (const [path, data] of Object.entries(orders)) await db.doc(path).set(data);
  mpCalls = [];
  diag.length = 0;
}

function call(method, body) {
  return new Promise((resolve, reject) => {
    const res = Object.assign(new EventEmitter(), {
      statusCode: 200,
      headers: {},
      setHeader(k, v) { this.headers[String(k).toLowerCase()] = v; },
      getHeader(k) { return this.headers[String(k).toLowerCase()]; },
      removeHeader(k) { delete this.headers[String(k).toLowerCase()]; },
      set(k, v) { this.setHeader(k, v); return this; },
      status(c) { this.statusCode = c; return this; },
      json(b) { return done(this, b); },
      send(b) { return done(this, b); },
      end(b) { return done(this, b ?? null); },
    });
    function done(r, b) {
      r.emit("finish");
      resolve({ status: r.statusCode, body: b });
      return r;
    }
    const headers = { "content-type": "application/json", origin: "https://app.example.test" };
    const req = {
      method, body, headers, url: "/", path: "/", query: {},
      header: (k) => headers[String(k).toLowerCase()],
      get: (k) => headers[String(k).toLowerCase()],
    };
    Promise.resolve(mpCatalogPayment(req, res)).catch(reject);
  });
}

const order = (total, extra = {}) => ({
  total,
  status: "pendente",
  cliente: { nome: "Cliente Teste", email: "comprador@example.test", cpf: "52998224725" },
  ...extra,
});
const pix = (lojaId, orderId, extra = {}) => ({
  lojaId, type: "pix", orderId, descricao: "Pedido catálogo", email: "comprador@example.test", cpf: "529.982.247-25", ...extra,
});
const pref = (lojaId, orderId, extra = {}) => ({ lojaId, type: "preference", orderId, titulo: "Pedido catálogo", ...extra });
const pixOk = () => ({
  status: 201,
  text: JSON.stringify({
    id: 987, status: "pending",
    point_of_interaction: { transaction_data: { qr_code: "QR", qr_code_base64: "QR64", ticket_url: "https://mp.example.test/t" } },
  }),
});
const prefOk = () => ({ status: 201, text: JSON.stringify({ id: "pref-1", init_point: "https://mp.example.test/i", sandbox_init_point: "https://mp.example.test/s" }) });
const mpError = (status, payload) => () => ({ status, text: typeof payload === "string" ? payload : JSON.stringify(payload) });

async function pixWithTotal(total, collection = "pedidos") {
  await reset({ orders: { [`lojas/lojaA/${collection}/o1`]: order(total) } });
  mpResponder = pixOk;
  const r = await call("POST", pix("lojaA", "o1"));
  assert.equal(r.status, 200);
  assert.equal(mpCalls.length, 1);
  return mpCalls[0].body.transaction_amount;
}

test("PIX válido: payload, resposta e token da loja", async () => {
  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(100) } });
  mpResponder = pixOk;
  const r = await call("POST", pix("lojaA", "o1", { valor: 1 }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { id: 987, status: "pending", qr_code: "QR", qr_code_base64: "QR64", ticket_url: "https://mp.example.test/t" });
  assert.equal(mpCalls.length, 1);
  const c = mpCalls[0];
  assert.equal(c.url, "https://api.mercadopago.com/v1/payments");
  assert.equal(c.token, "A");
  assert.ok(c.idempotencyKey);
  assert.deepEqual(c.body, {
    transaction_amount: 100,
    description: "Pedido catálogo",
    payment_method_id: "pix",
    external_reference: "o1",
    metadata: { lojaId: "lojaA" },
    notification_url: `https://southamerica-east1-${PROJECT}.cloudfunctions.net/mpWebhook`,
    payer: { email: "comprador@example.test", identification: { type: "CPF", number: "52998224725" } },
  });
});

test("PIX: transaction_amount normalizado para centavos do pedido", async () => {
  assert.equal(await pixWithTotal(59.9), 59.9);
  assert.equal(await pixWithTotal(10.999), 11);
  assert.equal(await pixWithTotal(33.333333), 33.33);
  assert.equal(await pixWithTotal(33.335), 33.34);
  assert.equal(await pixWithTotal(1.005), 1);
  assert.equal(await pixWithTotal(0.01), 0.01);
  assert.equal(await pixWithTotal("25.50"), 25.5);
  assert.equal(await pixWithTotal(45.678, "pre_pedidos"), 45.68);
});

test("PIX: erros de valor do provedor → mensagem de inconsistência + diagnóstico", async () => {
  const cases = [
    mpError(400, { message: "Invalid transaction_amount", error: "bad_request" }),
    mpError(400, { cause: [{ code: "invalid_transaction_amount" }] }),
    mpError(400, { error: "amount_mismatch" }),
    mpError(400, { cause: [{ description: "Valor inválido para a transação" }] }),
    mpError(400, "transaction amount must be positive"),
  ];
  for (const responder of cases) {
    await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10.999) } });
    mpResponder = responder;
    const r = await call("POST", pix("lojaA", "o1"));
    assert.equal(r.status, 400);
    assert.deepEqual(r.body, { error: AMOUNT_MSG });
    assert.equal(diag.length, 1);
    assert.equal(diag[0].normalized, 11);
    assert.equal(diag[0].cents, 1100);
  }
});

test("PIX: valor citado só no corpo bruto não troca a mensagem da causa principal", async () => {
  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10) } });
  mpResponder = mpError(400, { message: "payer.email invalid", detail: "transaction_amount ok" });
  let r = await call("POST", pix("lojaA", "o1"));
  assert.deepEqual([r.status, r.body], [400, { error: INVALID_MSG }]);
  assert.equal(diag.length, 1);

  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10) } });
  mpResponder = mpError(400, { detail: "transaction_amount rejected" });
  r = await call("POST", pix("lojaA", "o1"));
  assert.deepEqual([r.status, r.body], [400, { error: DEFAULT_MSG }]);
  assert.equal(diag.length, 1);
});

test("PIX: erros do provedor sem relação com valor", async () => {
  const cases = [
    [mpError(400, { message: "payer.email invalid" }), 400, INVALID_MSG],
    [mpError(400, { error: "bad_request" }), 400, INVALID_MSG],
    [mpError(500, { message: "Internal server error" }), 500, "Internal server error"],
    [mpError(400, { cause: [{ code: "payer_email_required" }] }), 400, "payer_email_required"],
    [mpError(502, "<html>bad gateway</html>"), 502, DEFAULT_MSG],
    [mpError(503, ""), 503, DEFAULT_MSG],
  ];
  for (const [responder, status, msg] of cases) {
    await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10) } });
    mpResponder = responder;
    const r = await call("POST", pix("lojaA", "o1"));
    assert.deepEqual([r.status, r.body], [status, { error: msg }]);
    assert.equal(diag.length, 0);
  }
});

test("requisições inválidas não chamam o Mercado Pago", async () => {
  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10) } });
  mpResponder = pixOk;
  assert.equal((await call("GET", {})).status, 405);
  assert.deepEqual(await call("POST", { type: "pix", orderId: "o1" }), { status: 400, body: { error: "lojaId e type são obrigatórios" } });
  assert.equal((await call("POST", { lojaId: "lojaA", type: "pix" })).status, 400);
  assert.deepEqual(await call("POST", { lojaId: "lojaA", type: "boleto", orderId: "o1" }), {
    status: 400, body: { error: "type deve ser 'pix' ou 'preference'" },
  });
  assert.deepEqual(await call("POST", pix("lojaA", "o1", { descricao: "" })), { status: 400, body: { error: "PIX requer descricao" } });
  assert.equal(mpCalls.length, 0);
});

test("isolamento por loja: pedido de outra loja não é encontrado; cada loja usa o próprio token", async () => {
  await reset({ orders: { "lojas/lojaB/pedidos/oB": order(50) } });
  mpResponder = pixOk;
  const wrong = await call("POST", pix("lojaA", "oB"));
  assert.deepEqual(wrong, { status: 404, body: { error: "Pedido não encontrado para esta loja." } });
  assert.equal(mpCalls.length, 0);

  const right = await call("POST", pix("lojaB", "oB"));
  assert.equal(right.status, 200);
  assert.equal(mpCalls.length, 1);
  assert.equal(mpCalls[0].token, "B");
  assert.deepEqual(mpCalls[0].body.metadata, { lojaId: "lojaB" });
});

test("pedido ausente, pago ou loja sem token não geram cobrança", async () => {
  await reset();
  mpResponder = pixOk;
  assert.equal((await call("POST", pix("lojaA", "nao-existe"))).status, 404);

  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10, { paidAt: "2026-01-01T00:00:00Z" }) } });
  assert.equal((await call("POST", pix("lojaA", "o1"))).status, 400);

  await reset({ tokenA: null, orders: { "lojas/lojaA/pedidos/o1": order(10) } });
  const noToken = await call("POST", pix("lojaA", "o1"));
  assert.equal(noToken.status, 400);
  assert.equal(noToken.body.code, "MP_LOJA_TOKEN_REQUIRED");
  assert.equal(mpCalls.length, 0);
});

test("retry: sucesso reaproveitado sem nova cobrança; após erro do provedor repete com a mesma chave", async () => {
  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10.999) } });
  mpResponder = pixOk;
  const first = await call("POST", pix("lojaA", "o1"));
  const second = await call("POST", pix("lojaA", "o1"));
  assert.equal(first.status, 200);
  assert.deepEqual(second, first);
  assert.equal(mpCalls.length, 1);

  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(10) } });
  mpResponder = (n) => (n === 1 ? mpError(400, { message: "Invalid transaction_amount" })() : pixOk());
  assert.equal((await call("POST", pix("lojaA", "o1"))).status, 400);
  assert.equal((await call("POST", pix("lojaA", "o1"))).status, 200);
  assert.equal(mpCalls.length, 2);
  assert.equal(mpCalls[0].idempotencyKey, mpCalls[1].idempotencyKey);
});

test("preferência: back_urls do cliente (retorno para a loja) preservadas; fallback sem back_urls", async () => {
  const backUrls = {
    success: "https://app.example.test/loja/loja-a?pagamento=sucesso",
    failure: "https://app.example.test/loja/loja-a?pagamento=falha",
    pending: "https://app.example.test/loja/loja-a?pagamento=pendente",
  };
  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(99.99) } });
  mpResponder = prefOk;
  const r = await call("POST", pref("lojaA", "o1", { backUrls }));
  assert.deepEqual(r, { status: 200, body: { id: "pref-1", init_point: "https://mp.example.test/i", sandbox_init_point: "https://mp.example.test/s" } });
  assert.equal(mpCalls[0].url, "https://api.mercadopago.com/checkout/preferences");
  assert.deepEqual(mpCalls[0].body.back_urls, backUrls);
  assert.equal(mpCalls[0].body.items[0].currency_id, "BRL");
  assert.equal(mpCalls[0].body.items[0].unit_price, 99.99);

  await reset({ orders: { "lojas/lojaA/pedidos/o1": order(99.99) } });
  await call("POST", pref("lojaA", "o1"));
  assert.deepEqual(mpCalls[0].body.back_urls, {
    success: "https://web-base.example.test/pagamento/sucesso?loja=lojaA",
    failure: "https://web-base.example.test/pagamento/falha?loja=lojaA",
    pending: "https://web-base.example.test/pagamento/pendente?loja=lojaA",
  });
});
