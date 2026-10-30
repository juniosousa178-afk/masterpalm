/**
 * node --test test/shippingExport.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Timestamp } from "firebase-admin/firestore";

import {
  SHIPPING_EXPORT_STATUS,
  SHIPPING_EXPORT_ERROR,
  SHIPPING_EXPORT_TRIGGER,
  shippingExportOperationId,
  shippingExportDocId,
  detectShippingExportTrigger,
  classifyShippingRequirement,
  readQuoteSnapshot,
  evaluateShippingCutover,
  parseShippingCutoverUtc,
  buildShippingOrder,
  buildMelhorEnvioCartRequest,
  classifyProviderHttpStatus,
  exportShippingOrder,
  handlePrePedidoShippingExportUpdate,
  createShippingExportHandlers,
  sanitizeProductName,
} from "../src/shippingExport.js";

const STORE_A = "loja-a";
const STORE_B = "loja-b";
const ORDER = "pedido-1";
const TOKEN_A = "token_loja_a_abcdefghijklmnopqrstuvwxyz";
const TOKEN_B = "token_loja_b_abcdefghijklmnopqrstuvwxyz";
const CUTOVER_MS = Date.parse("2026-10-30T00:00:00Z");
const CREATED_AFTER = CUTOVER_MS + 60_000;
const PAYMENT_ID = "123456789";

// ---------------------------------------------------------------------------
// Firestore em memória
// ---------------------------------------------------------------------------

const isPlain = (v) => v != null && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype;

function deepMerge(target, src) {
  const out = isPlain(target) ? { ...target } : {};
  for (const [k, v] of Object.entries(src)) {
    out[k] = isPlain(v) && isPlain(out[k]) ? deepMerge(out[k], v) : v;
  }
  return out;
}

function makeDb(initial = {}) {
  const docs = new Map(Object.entries(structuredClone(initial)));
  const writes = [];
  const reads = [];
  const docRef = (path) => ({
    path,
    collection: (name) => collectionRef(`${path}/${name}`),
    async get() {
      reads.push(path);
      const data = docs.get(path);
      return { exists: data !== undefined, data: () => data };
    },
    async set(data, opts = {}) {
      writes.push(path);
      docs.set(path, opts.merge ? deepMerge(docs.get(path), data) : { ...data });
    },
  });
  const collectionRef = (path) => ({ doc: (id) => docRef(`${path}/${id}`) });
  return {
    docs,
    writes,
    reads,
    collection: (name) => collectionRef(name),
    async runTransaction(fn) {
      const tx = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => ref.set(data, opts),
        update: (ref, data) => ref.set(data, { merge: true }),
      };
      return fn(tx);
    },
  };
}

// ---------------------------------------------------------------------------
// Dados
// ---------------------------------------------------------------------------

const SENDER = {
  name: "Loja A Ltda",
  companyDocument: "12345678000190",
  phone: "11988887777",
  postalCode: "01310100",
  address: "Rua da Loja",
  number: "50",
  district: "Centro",
  city: "Sao Paulo",
  state: "SP",
  shippingDocument: "declaracao_conteudo",
};

function order(provider = "melhor_envio", extra = {}) {
  const serviceId = provider === "superfrete" ? 1 : 4;
  return {
    lojaId: STORE_A,
    status: "pendente",
    total: 165,
    subtotal: 150,
    pagamento: "pix",
    cliente: {
      nome: "Maria Cliente",
      cpf: "98765432100",
      email: "maria@example.com",
      telefone: "11977776666",
      endereco: {
        cep: "20040020",
        rua: "Av Rio Branco",
        numero: "100",
        complemento: "ap 3",
        bairro: "Centro",
        cidade: "Rio de Janeiro",
        estado: "RJ",
      },
    },
    itens: [
      { productId: "p1", nome: "Colar Prata", quantidade: 2, precoUnitario: 50, total: 100 },
      { productId: "p2", nome: "Brinco\nFolheado", quantidade: 1, precoUnitario: 50, total: 50 },
    ],
    frete: {
      nome: "SEDEX",
      valor: 15,
      gratis: false,
      tipo: provider,
      plataforma: provider,
      ...(provider === "superfrete" ? { servico_id: serviceId } : { service_id: serviceId }),
      cotacao: {
        provider,
        serviceId: String(serviceId),
        serviceName: "SEDEX",
        carrierName: "Correios",
        quotedPrice: 15,
        quotedDeadlineDays: 3,
        pacote: { pesoGramas: 450, alturaCm: 10, larguraCm: 20, comprimentoCm: 30 },
      },
    },
    ...extra,
  };
}

function storeDocs({ storeId = STORE_A, token = TOKEN_A, provider = "melhor_envio", flag = true, sandbox = false, sender = SENDER } = {}) {
  const key = provider === "superfrete" ? "superfrete" : "melhor_envio";
  const flagKey = provider === "superfrete" ? "shippingAutoExportSuperFrete" : "shippingAutoExportMelhorEnvio";
  return {
    [`lojas/${storeId}/config/fretes_secrets`]: {
      ...(token ? { [key]: { token, sandbox } } : {}),
      automation: { [flagKey]: flag },
      ...(sender ? { sender } : {}),
    },
    [`lojas/${storeId}/config/fretes`]: { cepOrigem: "01310100" },
  };
}

function marker({ storeId = STORE_A, orderId = ORDER, status = "applied" } = {}) {
  return { [`_mp_webhook_processed/${PAYMENT_ID}`]: { status, lojaId: storeId, orderId } };
}

function paidAfter(o) {
  return { ...o, status: "paid", statusPagamento: "aprovado", paymentId: PAYMENT_ID, paidAt: "ts", saleOperationId: "op" };
}

function response(status, body) {
  return { ok: status >= 200 && status < 300, status, text: async () => (typeof body === "string" ? body : JSON.stringify(body)) };
}

/** fetch simulado: GET /me/cart devolve `cart`; POST responde com `post` (status/body) ou lança. */
function makeFetch({ cart = [], cartStatus = 200, post = { status: 201, body: { id: "me-cart-1" } }, throwOnPost = false } = {}) {
  const calls = [];
  const impl = async (url, opts = {}) => {
    calls.push({ url, method: opts.method, auth: opts.headers?.Authorization, body: opts.body ? JSON.parse(opts.body) : null });
    if (opts.method === "GET") return response(cartStatus, { data: cart, last_page: 1 });
    if (throwOnPost) throw new Error("Request timeout after 15000ms");
    return response(post.status, post.body);
  };
  impl.calls = calls;
  impl.posts = () => calls.filter((c) => c.method === "POST");
  return impl;
}

async function runPaid({ db, fetchImpl, o = order(), storeId = STORE_A, createTimeMs = CREATED_AFTER, cutoverMs = CUTOVER_MS }) {
  db.docs.set(`lojas/${storeId}/pre_pedidos/${ORDER}`, paidAfter(o));
  return handlePrePedidoShippingExportUpdate({
    db,
    collectionLojas: "lojas",
    storeId,
    orderId: ORDER,
    before: o,
    after: paidAfter(o),
    createTimeMs,
    cutoverMs,
    fetchImpl,
  });
}

const exportDoc = (db, provider = "melhor_envio", storeId = STORE_A) =>
  db.docs.get(`lojas/${storeId}/shipping_preorders/${shippingExportDocId(provider, ORDER)}`);
const orderDoc = (db, storeId = STORE_A) => db.docs.get(`lojas/${storeId}/pre_pedidos/${ORDER}`);

// ---------------------------------------------------------------------------
// Regras puras
// ---------------------------------------------------------------------------

describe("modelo e gatilho", () => {
  it("operationId determinístico por provedor/loja/pedido", () => {
    assert.equal(shippingExportOperationId("melhor_envio", STORE_A, ORDER), "shipping:melhor_envio:loja-a:pedido-1");
    assert.equal(shippingExportOperationId("melhor_envio", STORE_A, ORDER), shippingExportOperationId("melhor_envio", STORE_A, ORDER));
    assert.equal(shippingExportOperationId("", STORE_A, ORDER), "");
  });

  it("pagamento aprovado e confirmação do lojista disparam; o resto não", () => {
    const o = order();
    assert.equal(detectShippingExportTrigger(o, paidAfter(o))?.trigger, SHIPPING_EXPORT_TRIGGER.PAYMENT_APPROVED);
    assert.equal(detectShippingExportTrigger(paidAfter(o), paidAfter(o)), null);
    assert.equal(
      detectShippingExportTrigger(o, { ...o, status: "confirmado", vendaId: "v1" })?.trigger,
      SHIPPING_EXPORT_TRIGGER.MERCHANT_CONFIRMED,
    );
    assert.equal(detectShippingExportTrigger(o, { ...o, status: "confirmado" }), null);
    assert.equal(detectShippingExportTrigger(o, { ...o, status: "paid" }), null, "paid sem paymentId");
    assert.equal(detectShippingExportTrigger(o, { ...o, observacao: "x" }), null, "seleção/edição não dispara");
    assert.equal(detectShippingExportTrigger({ ...o, status: "confirmado" }, { ...o, status: "enviado", vendaId: "v" }), null);
    assert.equal(detectShippingExportTrigger(o, { ...o, status: "cancelado" }), null);
  });

  it("retirada, combinar, manual e cancelado não exigem envio", () => {
    assert.equal(classifyShippingRequirement(order()).required, true);
    assert.equal(classifyShippingRequirement({ frete: { tipo: "retirada", plataforma: "manual" } }).required, false);
    assert.equal(classifyShippingRequirement({ frete: { tipo: "combinar", plataforma: "manual" } }).required, false);
    assert.equal(classifyShippingRequirement({ frete: { tipo: "sedex", plataforma: "manual" } }).required, false);
    assert.equal(classifyShippingRequirement(order("melhor_envio", { status: "cancelado" })).required, false);
  });

  it("snapshot da cotação é obrigatório e precisa bater com o serviço do pedido", () => {
    assert.equal(readQuoteSnapshot(order(), "melhor_envio").ok, true);
    const semSnap = order();
    delete semSnap.frete.cotacao;
    assert.equal(readQuoteSnapshot(semSnap, "melhor_envio").code, SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING);
    const outroServico = order();
    outroServico.frete.service_id = 99;
    assert.equal(readQuoteSnapshot(outroServico, "melhor_envio").code, SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING);
    const semPeso = order();
    semPeso.frete.cotacao.pacote.pesoGramas = 0;
    assert.equal(readQuoteSnapshot(semPeso, "melhor_envio").ok, false);
  });

  it("corte: sem configuração ou pedido histórico nunca exporta", () => {
    assert.equal(evaluateShippingCutover({ createTimeMs: CREATED_AFTER, cutoverMs: null }).ok, false);
    assert.equal(evaluateShippingCutover({ createTimeMs: CUTOVER_MS - 1, cutoverMs: CUTOVER_MS }).reason, "historical_order");
    assert.equal(evaluateShippingCutover({ createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS }).ok, true);
    assert.equal(parseShippingCutoverUtc("2026-10-30T00:00:00Z"), CUTOVER_MS);
    assert.equal(parseShippingCutoverUtc(""), null);
    assert.equal(parseShippingCutoverUtc("lixo"), null);
  });

  it("payload Melhor Envio preserva serviço, pacote, itens e tag; sem e-mail", () => {
    const built = buildShippingOrder({ order: order(), storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: SENDER });
    assert.equal(built.ok, true);
    const body = buildMelhorEnvioCartRequest(built.shippingOrder);
    assert.equal(body.service, 4);
    assert.deepEqual(body.volumes, [{ height: 10, width: 20, length: 30, weight: 0.45 }]);
    assert.deepEqual(body.products, [
      { name: "Colar Prata", quantity: 2, unitary_value: 50 },
      { name: "Brinco Folheado", quantity: 1, unitary_value: 50 },
    ]);
    assert.equal(body.options.insurance_value, 150);
    assert.equal(body.options.non_commercial, true);
    assert.deepEqual(body.options.tags, [{ tag: "shipping:melhor_envio:loja-a:pedido-1" }]);
    assert.equal(body.from.company_document, "12345678000190");
    assert.equal(body.from.document, undefined);
    assert.equal(body.to.email, undefined);
    assert.equal(body.to.postal_code, "20040020");
    assert.equal(built.shippingOrder.quotedPrice, 15);
    assert.equal(built.shippingOrder.quotedDeadlineDays, 3);
  });

  it("remetente incompleto e NF exigida sem chave falham fechado", () => {
    const semRemetente = buildShippingOrder({ order: order(), storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: { ...SENDER, address: "" } });
    assert.equal(semRemetente.code, SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED);
    const nf = buildShippingOrder({ order: order(), storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: { ...SENDER, shippingDocument: "nota_fiscal" } });
    assert.equal(nf.code, SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED);
    const semNumero = order();
    semNumero.cliente.endereco.numero = "";
    assert.equal(
      buildShippingOrder({ order: semNumero, storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: SENDER }).code,
      SHIPPING_EXPORT_ERROR.RECIPIENT_DATA_INCOMPLETE,
    );
    assert.equal(sanitizeProductName("  a\u0000b\n c  "), "a b c");
  });

  it("classificação HTTP: 4xx falha, 408/5xx incerto", () => {
    assert.equal(classifyProviderHttpStatus(401).code, SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED);
    assert.equal(classifyProviderHttpStatus(403).outcome, "failed");
    assert.equal(classifyProviderHttpStatus(422).code, SHIPPING_EXPORT_ERROR.PROVIDER_VALIDATION_FAILED);
    assert.equal(classifyProviderHttpStatus(429).code, SHIPPING_EXPORT_ERROR.PROVIDER_RATE_LIMITED);
    assert.equal(classifyProviderHttpStatus(500).outcome, "unknown");
    assert.equal(classifyProviderHttpStatus(408).outcome, "unknown");
  });
});

// ---------------------------------------------------------------------------
// Melhor Envio — fluxo
// ---------------------------------------------------------------------------

describe("Melhor Envio — exportação após pagamento aprovado", () => {
  it("edição sem confirmação (seleção do frete) não chama o provedor", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    const o = order();
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, o);
    const res = await handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER,
      before: o, after: { ...o, observacao: "troca de frete" },
      createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS, fetchImpl,
    });
    assert.equal(res.skipped, true);
    assert.equal(fetchImpl.calls.length, 0);
    assert.equal(db.writes.length, 0);
  });

  it("o trigger de criação do pré-pedido não chama provedor", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const i = src.indexOf("export const onPrePedidoShippingPreOrder = onDocumentCreated(");
    assert.ok(i > 0);
    const block = src.slice(i, src.indexOf(");", i) + 2);
    assert.match(block, /async \(\) => \{\}/);
    assert.ok(!src.includes("onPrePedidoShippingPreOrderTrigger"));
  });

  it("pagamento aprovado cria um item no carrinho com o token da loja e grava o estado", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    const res = await runPaid({ db, fetchImpl });
    assert.equal(res.ok, true);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    const posts = fetchImpl.posts();
    assert.equal(posts.length, 1);
    assert.match(posts[0].url, /^https:\/\/melhorenvio\.com\.br\/api\/v2\/me\/cart$/);
    assert.equal(posts[0].auth, `Bearer ${TOKEN_A}`);
    assert.equal(posts[0].body.service, 4);
    const exp = exportDoc(db);
    assert.equal(exp.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(exp.providerShipmentId, "me-cart-1");
    assert.equal(exp.operationId, "shipping:melhor_envio:loja-a:pedido-1");
    const o = orderDoc(db);
    assert.equal(o.shipping.export.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(o.shipping.export.providerShipmentId, "me-cart-1");
    assert.equal(o.shipping.price, 15, "preço cobrado preservado");
    assert.equal(o.shipping.serviceName, "SEDEX");
    assert.equal(o.shipping.deadline, 3);
    assert.equal(o.total, 165, "total intocado");
    assert.equal(o.status, "paid", "status/pagamento intocados");
  });

  it("nenhuma escrita fora do pedido e do ledger de envio (estoque/venda/pagamento)", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch() });
    const allowed = new Set([
      `lojas/${STORE_A}/pre_pedidos/${ORDER}`,
      `lojas/${STORE_A}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`,
    ]);
    const extra = db.writes.filter((p) => !allowed.has(p));
    assert.deepEqual(extra, []);
  });

  it("webhook duplicado não duplica o envio", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    await runPaid({ db, fetchImpl });
    await runPaid({ db, fetchImpl });
    await runPaid({ db, fetchImpl });
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("sem marcador do webhook (ou de outra loja/pedido) não exporta", async () => {
    for (const m of [{}, marker({ storeId: STORE_B }), marker({ orderId: "outro" }), marker({ status: "sale_blocked" })]) {
      const db = makeDb({ ...storeDocs(), ...m });
      const fetchImpl = makeFetch();
      const res = await runPaid({ db, fetchImpl });
      assert.equal(res.reason, "payment_marker_not_verified");
      assert.equal(fetchImpl.calls.length, 0);
    }
  });

  it("feature flag desligada, corte ausente e pedido histórico não exportam", async () => {
    const off = makeDb({ ...storeDocs({ flag: false }), ...marker() });
    const f1 = makeFetch();
    assert.equal((await runPaid({ db: off, fetchImpl: f1 })).reason, "feature_disabled");
    const noCut = makeDb({ ...storeDocs(), ...marker() });
    const f2 = makeFetch();
    assert.equal((await runPaid({ db: noCut, fetchImpl: f2, cutoverMs: null })).reason, "cutover_not_configured");
    const hist = makeDb({ ...storeDocs(), ...marker() });
    const f3 = makeFetch();
    assert.equal((await runPaid({ db: hist, fetchImpl: f3, createTimeMs: CUTOVER_MS - 1 })).reason, "historical_order");
    assert.equal(f1.calls.length + f2.calls.length + f3.calls.length, 0);
  });

  it("retirada e cancelado não exportam", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    const retirada = order("melhor_envio");
    retirada.frete = { nome: "Retirada", valor: 0, tipo: "retirada", plataforma: "manual" };
    assert.equal((await runPaid({ db, fetchImpl, o: retirada })).reason, "no_shipment");
    const o = order();
    const cancel = await handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER,
      before: o, after: { ...o, status: "cancelado" }, createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS, fetchImpl,
    });
    assert.equal(cancel.skipped, true);
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("confirmação manual do lojista exporta (sem marcador de pagamento)", async () => {
    const db = makeDb(storeDocs());
    const fetchImpl = makeFetch();
    const o = order("melhor_envio", { pagamento: "dinheiro", statusPagamento: "aprovado" });
    const after = { ...o, status: "confirmado", vendaId: "venda-1" };
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, after);
    const res = await handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER,
      before: o, after, createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS, fetchImpl,
    });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("tenant A usa só o token de A; loja sem conta não usa token de outra", async () => {
    const db = makeDb({ ...storeDocs(), ...storeDocs({ storeId: STORE_B, token: TOKEN_B }), ...marker() });
    const fetchImpl = makeFetch();
    await runPaid({ db, fetchImpl });
    assert.ok(fetchImpl.calls.length > 0);
    assert.ok(fetchImpl.calls.every((c) => c.auth === `Bearer ${TOKEN_A}`));
    assert.ok(!db.reads.some((p) => p.startsWith(`lojas/${STORE_B}/`)));

    const dbNoAccount = makeDb({ ...storeDocs({ token: null }), ...storeDocs({ storeId: STORE_B, token: TOKEN_B }), ...marker() });
    const f2 = makeFetch();
    const res = await runPaid({ db: dbNoAccount, fetchImpl: f2 });
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.PROVIDER_ACCOUNT_NOT_CONNECTED);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(f2.calls.length, 0);
  });

  it("remetente não cadastrado ou snapshot ausente falham sem chamar o provedor", async () => {
    const db = makeDb({ ...storeDocs({ sender: null }), ...marker() });
    const fetchImpl = makeFetch();
    assert.equal((await runPaid({ db, fetchImpl })).lastErrorCode, SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED);
    const db2 = makeDb({ ...storeDocs(), ...marker() });
    const semSnap = order();
    delete semSnap.frete.cotacao;
    assert.equal((await runPaid({ db: db2, fetchImpl, o: semSnap })).lastErrorCode, SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING);
    assert.equal(fetchImpl.calls.length, 0);
  });

  for (const [status, code, final] of [
    [401, SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED, SHIPPING_EXPORT_STATUS.FAILED],
    [403, SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED, SHIPPING_EXPORT_STATUS.FAILED],
    [422, SHIPPING_EXPORT_ERROR.PROVIDER_VALIDATION_FAILED, SHIPPING_EXPORT_STATUS.FAILED],
    [429, SHIPPING_EXPORT_ERROR.PROVIDER_RATE_LIMITED, SHIPPING_EXPORT_STATUS.FAILED],
    [500, SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE, SHIPPING_EXPORT_STATUS.UNKNOWN],
    [503, SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE, SHIPPING_EXPORT_STATUS.UNKNOWN],
  ]) {
    it(`POST ${status} → ${final} (${code}) sem expor resposta`, async () => {
      const db = makeDb({ ...storeDocs(), ...marker() });
      const fetchImpl = makeFetch({ post: { status, body: { message: "segredo do provedor", token: "x" } } });
      const res = await runPaid({ db, fetchImpl });
      assert.equal(res.status, final);
      assert.equal(res.lastErrorCode, code);
      const exp = exportDoc(db);
      assert.ok(!JSON.stringify(exp).includes("segredo do provedor"));
      assert.ok(!JSON.stringify(orderDoc(db).shipping).includes("segredo do provedor"));
    });
  }

  it("timeout e 200 sem id ficam incertos (unknown), não falha", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const res = await runPaid({ db, fetchImpl: makeFetch({ throwOnPost: true }) });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    const db2 = makeDb({ ...storeDocs(), ...marker() });
    const res2 = await runPaid({ db: db2, fetchImpl: makeFetch({ post: { status: 200, body: "<html>" } }) });
    assert.equal(res2.status, SHIPPING_EXPORT_STATUS.UNKNOWN);
  });

  it("provedor fora do ar na reconciliação inicial não bloqueia a primeira tentativa", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch({ cartStatus: 503 });
    const res = await runPaid({ db, fetchImpl });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("item já presente no carrinho (tag) é reconhecido sem novo POST", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch({ cart: [{ id: "me-existente", tags: [{ tag: "shipping:melhor_envio:loja-a:pedido-1" }] }] });
    const res = await runPaid({ db, fetchImpl });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(res.providerShipmentId, "me-existente");
    assert.equal(fetchImpl.posts().length, 0);
  });
});

describe("retry e idempotência", () => {
  async function seedUnknown() {
    const db = makeDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch({ throwOnPost: true }) });
    assert.equal(exportDoc(db).status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    return db;
  }
  const retry = (db, fetchImpl) => exportShippingOrder({
    db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
    trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY, fetchImpl,
  });

  it("após incerto, retry consulta o carrinho e reaproveita o envio existente", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch({ cart: [{ id: "me-criado-no-timeout", tags: [{ tag: "shipping:melhor_envio:loja-a:pedido-1" }] }] });
    const res = await retry(db, fetchImpl);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(res.providerShipmentId, "me-criado-no-timeout");
    assert.equal(fetchImpl.posts().length, 0);
    assert.equal(exportDoc(db).operationId, "shipping:melhor_envio:loja-a:pedido-1");
  });

  it("após incerto, carrinho sem a tag → um único POST com a mesma operationId", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch();
    const res = await retry(db, fetchImpl);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
    assert.deepEqual(fetchImpl.posts()[0].body.options.tags, [{ tag: "shipping:melhor_envio:loja-a:pedido-1" }]);
  });

  it("após incerto, consulta indisponível mantém unknown e não faz POST", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch({ cartStatus: 500 });
    const res = await retry(db, fetchImpl);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    assert.equal(fetchImpl.posts().length, 0);
  });

  it("gatilho automático repetido após falha não tenta de novo; retry do lojista sim", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch({ post: { status: 422, body: {} } }) });
    const auto = makeFetch();
    const again = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      trigger: SHIPPING_EXPORT_TRIGGER.PAYMENT_APPROVED, fetchImpl: auto,
    });
    assert.equal(again.reason, "already_attempted");
    assert.equal(auto.calls.length, 0);
    const manual = makeFetch();
    const res = await retry(db, manual);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(manual.posts().length, 1);
    assert.equal(exportDoc(db).attempts, 2);
  });

  it("exportação em andamento (lease ativo) não cria outra", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, paidAfter(order()));
    db.docs.set(`lojas/${STORE_A}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`, {
      status: SHIPPING_EXPORT_STATUS.EXPORTING,
      leaseUntil: Timestamp.fromMillis(Date.now() + 60_000),
    });
    const fetchImpl = makeFetch();
    const res = await retry(db, fetchImpl);
    assert.equal(res.reason, "export_in_progress");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("já exportado → retorna o existente", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch() });
    const fetchImpl = makeFetch();
    const res = await retry(db, fetchImpl);
    assert.equal(res.idempotent, true);
    assert.equal(fetchImpl.calls.length, 0);
  });
});

describe("SuperFrete", () => {
  it("produção: sem reconciliação disponível → UNSUPPORTED_BY_CURRENT_API, sem chamada", async () => {
    const db = makeDb({ ...storeDocs({ provider: "superfrete", token: TOKEN_A, sandbox: false }), ...marker() });
    const fetchImpl = makeFetch();
    const res = await runPaid({ db, fetchImpl, o: order("superfrete") });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.UNSUPPORTED_BY_CURRENT_API);
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("sandbox: POST /api/v0/cart com servico_id preservado", async () => {
    const db = makeDb({ ...storeDocs({ provider: "superfrete", token: TOKEN_A, sandbox: true }), ...marker() });
    const fetchImpl = makeFetch({ post: { status: 200, body: { id: "sf-1" } } });
    const res = await runPaid({ db, fetchImpl, o: order("superfrete") });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    const posts = fetchImpl.posts();
    assert.equal(posts.length, 1);
    assert.match(posts[0].url, /^https:\/\/sandbox\.superfrete\.com\/api\/v0\/cart$/);
    assert.equal(posts[0].body.service, 1);
    assert.equal(posts[0].body.tag, "shipping:superfrete:loja-a:pedido-1");
  });

  it("sandbox: resposta incerta fica unknown e retry não faz novo POST", async () => {
    const db = makeDb({ ...storeDocs({ provider: "superfrete", token: TOKEN_A, sandbox: true }), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch({ post: { status: 502, body: "<html>" } }), o: order("superfrete") });
    assert.equal(exportDoc(db, "superfrete").status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    const fetchImpl = makeFetch();
    const res = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY, fetchImpl,
    });
    assert.equal(res.reason, "unknown_requires_manual_review");
    assert.equal(fetchImpl.calls.length, 0);
  });
});

describe("logs sem PII", () => {
  it("SHIPPING_EXPORT não contém nome, CEP, CPF, endereço, telefone ou token", async () => {
    const lines = [];
    const orig = console.log;
    console.log = (...a) => lines.push(a.join(" "));
    try {
      const db = makeDb({ ...storeDocs(), ...marker() });
      await runPaid({ db, fetchImpl: makeFetch() });
      const db2 = makeDb({ ...storeDocs(), ...marker() });
      await runPaid({ db: db2, fetchImpl: makeFetch({ post: { status: 422, body: {} } }) });
    } finally {
      console.log = orig;
    }
    const out = lines.join("\n");
    assert.match(out, /"event":"SHIPPING_EXPORT"/);
    for (const forbidden of ["Maria", "20040020", "98765432100", "Rio Branco", "11977776666", TOKEN_A, STORE_A, ORDER]) {
      assert.ok(!out.includes(forbidden), `log contém ${forbidden}`);
    }
  });
});

describe("callables do lojista", () => {
  function handlers(db, { allowed = true, data = {}, fetchImpl = makeFetch() } = {}) {
    return createShippingExportHandlers({
      db,
      collectionLojas: "lojas",
      canManageStoreConfigServerSide: async () => allowed,
      checkRateLimit: async () => {},
      getCallableIdentifier: () => "uid-1",
      fetchWithTimeout: fetchImpl,
      request: { auth: { uid: "uid-1", token: {} }, data },
    });
  }

  it("salvar configuração exige admin da loja", async () => {
    const db = makeDb();
    await assert.rejects(
      handlers(db, { allowed: false, data: { lojaId: STORE_A, flags: { melhorEnvio: true } } }).shippingSaveAutomationConfig(),
      (e) => e.code === "permission-denied",
    );
    assert.equal(db.writes.length, 0);
  });

  it("remetente incompleto é rejeitado; documento mascarado não sobrescreve", async () => {
    const db = makeDb();
    await assert.rejects(
      handlers(db, { data: { lojaId: STORE_A, sender: { ...SENDER, city: "" } } }).shippingSaveAutomationConfig(),
      (e) => e.code === "invalid-argument",
    );
    await handlers(db, { data: { lojaId: STORE_A, sender: SENDER, flags: { melhorEnvio: true } } }).shippingSaveAutomationConfig();
    await handlers(db, { data: { lojaId: STORE_A, sender: { ...SENDER, companyDocument: "••••0190" } } }).shippingSaveAutomationConfig();
    const saved = db.docs.get(`lojas/${STORE_A}/config/fretes_secrets`);
    assert.equal(saved.sender.companyDocument, "12345678000190");
    assert.equal(saved.automation.shippingAutoExportMelhorEnvio, true);
    const cfg = await handlers(db, { data: { lojaId: STORE_A } }).shippingGetAutomationConfig();
    assert.equal(cfg.flags.melhorEnvio, true);
    assert.equal(cfg.flags.superFrete, false);
    assert.equal(cfg.sender.companyDocumentMasked, "••••0190");
    assert.equal(cfg.senderComplete, true);
    assert.ok(!JSON.stringify(cfg).includes("12345678000190"));
  });

  it("retry só para falha/incerto e pedido confirmado", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, order());
    await assert.rejects(
      handlers(db, { data: { lojaId: STORE_A, orderId: ORDER } }).retryShippingExport(),
      (e) => e.code === "failed-precondition",
    );
    await runPaid({ db, fetchImpl: makeFetch({ post: { status: 429, body: {} } }) });
    const fetchImpl = makeFetch();
    const res = await handlers(db, { data: { lojaId: STORE_A, orderId: ORDER }, fetchImpl }).retryShippingExport();
    assert.equal(res.ok, true);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("retry ignora shipping.export forjado no pedido (estado vem do ledger)", async () => {
    const db = makeDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, order("melhor_envio", {
      status: "paid",
      paymentId: "pay-1",
      shipping: { export: { status: SHIPPING_EXPORT_STATUS.FAILED } },
    }));
    const fetchImpl = makeFetch();
    await assert.rejects(
      handlers(db, { data: { lojaId: STORE_A, orderId: ORDER }, fetchImpl }).retryShippingExport(),
      (e) => e.code === "failed-precondition",
    );
    assert.equal(fetchImpl.posts().length, 0);
  });
});
