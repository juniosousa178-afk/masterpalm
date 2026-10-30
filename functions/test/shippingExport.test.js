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
  SHIPPING_EXPORT_RESOLUTION,
  SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED,
  shippingExportOperationId,
  shippingExportDocId,
  detectShippingExportTrigger,
  classifyShippingRequirement,
  evaluateShippingCutover,
  parseShippingCutoverUtc,
  buildShippingOrder,
  buildMelhorEnvioCartRequest,
  classifyProviderHttpStatus,
  classifyProviderNetworkError,
  exportShippingOrder,
  exportSuperFrete,
  handlePrePedidoShippingExportUpdate,
  authorizeMerchantConfirmation,
  createShippingExportHandlers,
  sanitizeProductName,
} from "../src/shippingExport.js";
import { SHIPPING_QUOTE_ERROR, SHIPPING_QUOTE_RETENTION_MS } from "../src/shippingQuoteReceipt.js";
import { makeDb } from "./shippingMemoryDb.js";

const STORE_A = "loja-a";
const STORE_B = "loja-b";
const ORDER = "pedido-1";
const TOKEN_A = "token_loja_a_abcdefghijklmnopqrstuvwxyz";
const TOKEN_B = "token_loja_b_abcdefghijklmnopqrstuvwxyz";
const CUTOVER_MS = Date.parse("2026-10-30T00:00:00Z");
const CREATED_AFTER = CUTOVER_MS + 60_000;
const PAYMENT_ID = "123456789";
const RECEIPT = "a".repeat(32);
const QUOTE_ID = `${RECEIPT}.0`;
const ME_PACKAGE = { weight: 0.45, height: 10, width: 20, length: 30 };

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
      shippingQuoteId: QUOTE_ID,
    },
    ...extra,
  };
}

function receiptDocs({ storeId = STORE_A, provider = "melhor_envio" } = {}) {
  const serviceId = provider === "superfrete" ? "1" : "4";
  return {
    [`lojas/${storeId}/shipping_quotes/${RECEIPT}`]: {
      storeId,
      provider,
      originCep: "01310100",
      destinationCep: "20040020",
      items: [{ productId: "p1", quantity: 2 }, { productId: "p2", quantity: 1 }],
      canonicalPackage: { weightGrams: 450, heightCm: 10, widthCm: 20, lengthCm: 30 },
      providerPackage: ME_PACKAGE,
      insuranceValue: 150,
      options: [{ serviceId, serviceName: "SEDEX", carrierName: "Correios", companyId: "1", price: 15, deadlineDays: 3 }],
      quotedAtMs: CREATED_AFTER - 60_000,
      expiresAtMs: CREATED_AFTER + 60 * 60_000,
      // Relativo ao relógio real, como os leases destes testes (exportShippingOrder usa Date.now()).
      retainUntilMs: Date.now() + SHIPPING_QUOTE_RETENTION_MS,
    },
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
    ...receiptDocs({ storeId, provider }),
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

/** fetch simulado: POST responde com `post` (status/body) ou lança `throwOnPost`. */
function makeFetch({ post = { status: 201, body: { id: "me-cart-1" } }, throwOnPost = null } = {}) {
  const calls = [];
  const impl = async (url, opts = {}) => {
    calls.push({ url, method: opts.method, auth: opts.headers?.Authorization, body: opts.body ? JSON.parse(opts.body) : null });
    if (throwOnPost) throw throwOnPost;
    return response(post.status, post.body);
  };
  impl.calls = calls;
  impl.posts = () => calls.filter((c) => c.method === "POST");
  return impl;
}

const timeoutError = () => new Error("Request timeout after 15000ms");
const dnsError = () => Object.assign(new TypeError("fetch failed"), { cause: { code: "ENOTFOUND" } });

const newDb = (docs) => makeDb(docs, { createTimeMs: CREATED_AFTER });

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

function handlers(db, { allowed = true, data = {}, fetchImpl = makeFetch(), cutoverMs = CUTOVER_MS } = {}) {
  return createShippingExportHandlers({
    db,
    collectionLojas: "lojas",
    canManageStoreConfigServerSide: async () => allowed,
    checkRateLimit: async () => {},
    getCallableIdentifier: () => "uid-1",
    fetchWithTimeout: fetchImpl,
    request: { auth: { uid: "uid-1", token: {} }, data },
    cutoverMs,
  });
}

const retryCallable = (db, fetchImpl, resolution) =>
  handlers(db, { data: { lojaId: STORE_A, orderId: ORDER, ...(resolution ? { resolution } : {}) }, fetchImpl }).retryShippingExport();

// ---------------------------------------------------------------------------
// Regras puras
// ---------------------------------------------------------------------------

describe("modelo e gatilho", () => {
  it("operationId determinístico por provedor/loja/pedido", () => {
    assert.equal(shippingExportOperationId("melhor_envio", STORE_A, ORDER), "shipping:melhor_envio:loja-a:pedido-1");
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

  it("corte: só UTC explícito; sem configuração ou pedido histórico nunca exporta", () => {
    assert.equal(evaluateShippingCutover({ createTimeMs: CREATED_AFTER, cutoverMs: null }).ok, false);
    assert.equal(evaluateShippingCutover({ createTimeMs: CUTOVER_MS - 1, cutoverMs: CUTOVER_MS }).reason, "historical_order");
    assert.equal(evaluateShippingCutover({ createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS }).ok, true);
    assert.equal(parseShippingCutoverUtc("2026-10-30T00:00:00Z"), CUTOVER_MS);
    assert.equal(parseShippingCutoverUtc("2026-10-30T00:00:00.000Z"), CUTOVER_MS);
    for (const bad of ["", "lixo", "2026-10-30T00:00:00", "2026-10-30T00:00:00-03:00", "2026-10-30", "30/10/2026"]) {
      assert.equal(parseShippingCutoverUtc(bad), null, bad);
    }
  });

  it("corte obrigatório no deploy: defineString sem padrão, com regex UTC; nada de process.env/relógio", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const i = src.indexOf("const SHIPPING_AUTO_EXPORT_CUTOVER = defineString(");
    assert.ok(i > 0);
    const block = src.slice(i, src.indexOf("});", i) + 3);
    assert.ok(!/default\s*:/.test(block), "sem default → deploy falha fechado se ausente");
    assert.match(block, /validationRegex: SHIPPING_CUTOVER_UTC_PATTERN/);
    assert.ok(!/default\s*:|ex\.:\s*\d{4}-/.test(block), "sem data de exemplo/padrão");
    assert.ok(!src.includes("process.env[SHIPPING_AUTO_EXPORT_CUTOVER_ENV]"));
    assert.match(src, /function shippingCutoverMs\(\) \{\s*return parseShippingCutoverUtc\(SHIPPING_AUTO_EXPORT_CUTOVER\.value\(\)\);/);
    assert.equal((src.match(/cutoverMs: shippingCutoverMs\(\)/g) ?? []).length, 4, "pagamento, trigger e dois callables");
  });

  it("payload Melhor Envio: contrato do carrinho (strings, volume cotado, documento/bairro, sem e-mail)", () => {
    const quote = {
      provider: "melhor_envio", shippingQuoteId: QUOTE_ID, serviceId: "4", serviceName: "SEDEX",
      carrierName: "Correios", quotedPrice: 15, chargedPrice: 15, deadlineDays: 3,
      insuranceValue: 150, providerPackage: ME_PACKAGE,
    };
    const built = buildShippingOrder({ order: order(), storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: SENDER, quote });
    assert.equal(built.ok, true);
    const body = buildMelhorEnvioCartRequest(built.shippingOrder);
    assert.equal(body.service, 4);
    assert.deepEqual(body.volumes, [{ height: 10, width: 20, length: 30, weight: 0.45 }]);
    assert.deepEqual(body.products, [
      { name: "Colar Prata", quantity: "2", unitary_value: "50.00" },
      { name: "Brinco Folheado", quantity: "1", unitary_value: "50.00" },
    ]);
    assert.equal(body.options.insurance_value, 150);
    assert.equal(body.options.non_commercial, true);
    assert.equal(body.options.invoice, undefined);
    assert.equal(body.from.company_document, "12345678000190");
    assert.equal(body.from.state_register, undefined);
    assert.equal(body.to.document, "98765432100");
    assert.equal(body.to.district, "Centro");
    assert.equal(body.to.email, undefined);
    assert.equal(body.to.postal_code, "20040020");

    const nfOk = buildShippingOrder({
      order: order("melhor_envio", { notaFiscal: { chave: "1".repeat(44) } }),
      storeId: STORE_A, orderId: ORDER, provider: "melhor_envio",
      sender: { ...SENDER, shippingDocument: "nota_fiscal", stateRegister: "123456789" }, quote,
    });
    const nfBody = buildMelhorEnvioCartRequest(nfOk.shippingOrder);
    assert.equal(nfBody.options.non_commercial, false);
    assert.deepEqual(nfBody.options.invoice, { key: "1".repeat(44) });
    assert.equal(nfBody.from.state_register, "123456789");
  });

  it("dados fiscais/destinatário incompletos falham fechado (nada inventado)", () => {
    const quote = { provider: "melhor_envio", serviceId: "4", insuranceValue: 150, providerPackage: ME_PACKAGE };
    const b = (o, sender = SENDER) => buildShippingOrder({ order: o, storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender, quote });
    assert.equal(b(order(), { ...SENDER, address: "" }).code, SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED);
    const nfSemChave = b(order(), { ...SENDER, shippingDocument: "nota_fiscal", stateRegister: "123" });
    assert.equal(nfSemChave.code, SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED);
    const nfSemIE = b(order("melhor_envio", { notaFiscal: { chave: "1".repeat(44) } }), { ...SENDER, shippingDocument: "nota_fiscal" });
    assert.equal(nfSemIE.code, SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED);
    for (const field of ["numero", "bairro"]) {
      const o = order();
      o.cliente.endereco[field] = "";
      assert.equal(b(o).code, SHIPPING_EXPORT_ERROR.RECIPIENT_DATA_INCOMPLETE, field);
    }
    const semCpf = order();
    semCpf.cliente.cpf = "";
    assert.equal(b(semCpf).code, SHIPPING_EXPORT_ERROR.RECIPIENT_DATA_INCOMPLETE);
    assert.equal(b(order(), SENDER).ok, true);
    assert.equal(buildShippingOrder({ order: order(), storeId: STORE_A, orderId: ORDER, provider: "melhor_envio", sender: SENDER, quote: null }).ok, false);
    assert.equal(sanitizeProductName("  a\u0000b\n c  "), "a b c");
  });

  it("classificação: 4xx falha; 408/5xx/timeout incerto; erro antes de conectar falha", () => {
    assert.equal(classifyProviderHttpStatus(401).code, SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED);
    assert.equal(classifyProviderHttpStatus(403).outcome, "failed");
    assert.equal(classifyProviderHttpStatus(422).code, SHIPPING_EXPORT_ERROR.PROVIDER_VALIDATION_FAILED);
    assert.equal(classifyProviderHttpStatus(429).code, SHIPPING_EXPORT_ERROR.PROVIDER_RATE_LIMITED);
    assert.equal(classifyProviderHttpStatus(500).outcome, "unknown");
    assert.equal(classifyProviderHttpStatus(408).outcome, "unknown");
    assert.equal(classifyProviderNetworkError(timeoutError()).outcome, "unknown");
    assert.equal(classifyProviderNetworkError(new TypeError("fetch failed")).outcome, "unknown");
    assert.equal(classifyProviderNetworkError(dnsError()).outcome, "failed");
    assert.equal(classifyProviderNetworkError({ cause: { code: "ECONNRESET" } }).outcome, "unknown");
  });

  it("sem reconciliação por tag: nenhuma listagem do carrinho é usada", () => {
    const src = readFileSync(new URL("../src/shippingExport.js", import.meta.url), "utf8");
    assert.ok(!src.includes("me/cart?page"));
    assert.ok(!src.includes("findMelhorEnvioCartItemByTag"));
    assert.ok(!src.includes("cartItemHasTag"));
  });
});

// ---------------------------------------------------------------------------
// Melhor Envio — fluxo
// ---------------------------------------------------------------------------

describe("Melhor Envio — exportação após pagamento aprovado", () => {
  it("edição sem confirmação (seleção do frete) não chama o provedor", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
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

  it("gatilho antigo desligado: criação do pré-pedido é no-op e não há outro gatilho de criação", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const i = src.indexOf("export const onPrePedidoShippingPreOrder = onDocumentCreated(");
    assert.ok(i > 0);
    const block = src.slice(i, src.indexOf(");", i) + 2);
    assert.match(block, /async \(\) => \{\}/);
    assert.ok(!src.includes("onPrePedidoShippingPreOrderTrigger"));
    assert.ok(!src.includes("handlePrePedidoShippingPreOrderCreated"));
    assert.match(src, /export const onPrePedidoShippingExport = onDocumentUpdatedWithAuthContext\(/);
  });

  it("pagamento aprovado cria um item no carrinho com o token da loja e o pacote cotado", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    const res = await runPaid({ db, fetchImpl });
    assert.equal(res.ok, true);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    const posts = fetchImpl.posts();
    assert.equal(posts.length, 1);
    assert.match(posts[0].url, /^https:\/\/melhorenvio\.com\.br\/api\/v2\/me\/cart$/);
    assert.equal(posts[0].auth, `Bearer ${TOKEN_A}`);
    assert.equal(posts[0].body.service, 4);
    assert.deepEqual(posts[0].body.volumes, [ME_PACKAGE]);
    assert.equal(posts[0].body.options.insurance_value, 150);
    const exp = exportDoc(db);
    assert.equal(exp.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(exp.providerShipmentId, "me-cart-1", "ID do provedor persistido no ledger");
    assert.equal(exp.shippingQuoteId, QUOTE_ID);
    const o = orderDoc(db);
    assert.equal(o.shipping.export.providerShipmentId, "me-cart-1");
    assert.equal(o.shipping.price, 15);
    assert.equal(o.shipping.serviceName, "SEDEX");
    assert.equal(o.shipping.carrierName, "Correios");
    assert.equal(o.shipping.deadline, 3);
    assert.equal(o.total, 165, "total intocado");
    assert.equal(o.status, "paid", "status/pagamento intocados");
  });

  it("nenhuma escrita fora do pedido e do ledger de envio (estoque/venda/pagamento)", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch() });
    const allowed = new Set([
      `lojas/${STORE_A}/pre_pedidos/${ORDER}`,
      `lojas/${STORE_A}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`,
    ]);
    assert.deepEqual(db.writes.filter((p) => !allowed.has(p)), []);
  });

  it("webhook repetido não duplica o envio", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    await runPaid({ db, fetchImpl });
    await runPaid({ db, fetchImpl });
    await runPaid({ db, fetchImpl });
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("gatilhos concorrentes: um único POST", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, paidAfter(order()));
    const fire = () => handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER,
      before: order(), after: paidAfter(order()), createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS, fetchImpl,
    });
    const results = await Promise.all([fire(), fire(), fire(), retryCallable(db, fetchImpl).catch((e) => e)]);
    assert.equal(fetchImpl.posts().length, 1);
    assert.equal(results.filter((r) => r?.status === SHIPPING_EXPORT_STATUS.EXPORTED && r.ok && !r.idempotent).length, 1);
  });

  it("sem marcador do webhook (ou de outra loja/pedido) não exporta", async () => {
    for (const m of [{}, marker({ storeId: STORE_B }), marker({ orderId: "outro" }), marker({ status: "sale_blocked" })]) {
      const db = newDb({ ...storeDocs(), ...m });
      const fetchImpl = makeFetch();
      const res = await runPaid({ db, fetchImpl });
      assert.equal(res.reason, "payment_marker_not_verified");
      assert.equal(fetchImpl.calls.length, 0);
    }
  });

  it("feature flag desligada, corte ausente e pedido histórico não exportam", async () => {
    const off = newDb({ ...storeDocs({ flag: false }), ...marker() });
    const f1 = makeFetch();
    assert.equal((await runPaid({ db: off, fetchImpl: f1 })).reason, "feature_disabled");
    const noCut = newDb({ ...storeDocs(), ...marker() });
    const f2 = makeFetch();
    assert.equal((await runPaid({ db: noCut, fetchImpl: f2, cutoverMs: null })).reason, "cutover_not_configured");
    const hist = newDb({ ...storeDocs(), ...marker() });
    const f3 = makeFetch();
    assert.equal((await runPaid({ db: hist, fetchImpl: f3, createTimeMs: CUTOVER_MS - 1 })).reason, "historical_order");
    assert.equal(f1.calls.length + f2.calls.length + f3.calls.length, 0);
  });

  it("pedido do fluxo antigo (ledger legado ou shippingPreOrder) nunca exporta de novo", async () => {
    const db = newDb({
      ...storeDocs(),
      ...marker(),
      [`lojas/${STORE_A}/shipping_preorders/melhor_envio_${ORDER}`]: { status: "created", providerCartId: "antigo" },
    });
    const fetchImpl = makeFetch();
    assert.equal((await runPaid({ db, fetchImpl })).reason, "legacy_preorder_exists");
    const db2 = newDb({ ...storeDocs(), ...marker() });
    assert.equal((await runPaid({ db: db2, fetchImpl, o: order("melhor_envio", { shippingPreOrder: { status: "created" } }) })).reason, "legacy_preorder_exists");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("retirada e cancelado não exportam", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
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

  describe("confirmação do lojista: só dono/admin da mesma loja", () => {
    const o = order("melhor_envio", { pagamento: "dinheiro", statusPagamento: "aprovado" });
    const after = { ...o, status: "confirmado", vendaId: "venda-1" };
    // Admins por loja (espelha canManageStoreConfigServerSide: ownerUid / members owner|admin).
    const admins = { [STORE_A]: new Set(["owner-a", "admin-a"]), [STORE_B]: new Set(["admin-b"]) };
    const isStoreAdminUid = async (storeId, uid) => admins[storeId]?.has(uid) === true;
    const run = async (authType, authId) => {
      const db = newDb(storeDocs());
      db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, after);
      const fetchImpl = makeFetch();
      const res = await handlePrePedidoShippingExportUpdate({
        db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER,
        before: o, after, createTimeMs: CREATED_AFTER, cutoverMs: CUTOVER_MS, fetchImpl,
        authType, authId, isStoreAdminUid,
      });
      return { res, posts: fetchImpl.posts().length, writes: db.writes.length };
    };

    for (const [name, authType, authId, reason] of [
      ["anônimo", "unauthenticated", null, "merchant_confirmation_unauthenticated"],
      ["cliente comum", "unknown", "cliente-1", "merchant_confirmation_not_store_admin"],
      ["autenticado sem papel de admin", "api_key", "vendedor-a", "merchant_confirmation_not_store_admin"],
      ["admin de outra loja", "unknown", "admin-b", "merchant_confirmation_not_store_admin"],
      ["sem identificação do autor", "unknown", null, "merchant_confirmation_actor_unknown"],
      ["evento de sistema", "system", null, "merchant_confirmation_actor_unknown"],
    ]) {
      it(`${name}: não exporta`, async () => {
        const { res, posts, writes } = await run(authType, authId);
        assert.equal(res.reason, reason);
        assert.equal(posts, 0);
        assert.equal(writes, 0);
      });
    }

    for (const [name, authId] of [["dono", "owner-a"], ["admin", "admin-a"]]) {
      it(`${name} da loja: exporta uma vez`, async () => {
        const { res, posts } = await run("unknown", authId);
        assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
        assert.equal(posts, 1);
      });
    }

    it("backend (Admin SDK / service account) é confiável; erro na checagem nega", async () => {
      const { res } = await run("service_account", "sa@project.iam");
      assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
      const denied = await authorizeMerchantConfirmation({
        authType: "unknown", authId: "owner-a", storeId: STORE_A, isStoreAdminUid: async () => { throw new Error("x"); },
      });
      assert.equal(denied.ok, false);
    });

    it("index.js passa authId e a checagem de admin por uid ao trigger", () => {
      const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
      const i = src.indexOf("export const onPrePedidoShippingExport = onDocumentUpdatedWithAuthContext(");
      const block = src.slice(i, src.indexOf("export const onPrePedidoClienteEmail", i));
      assert.match(block, /authId: event\.authId \?\? null/);
      assert.match(block, /isStoreAdminUid: \(storeId, uid\) => canManageStoreConfigServerSide\(\{\s*lojaId: storeId, uid,/);
    });
  });

  it("rules: cliente não confirma pedido nem grava estado de envio", () => {
    const rules = readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8");
    const i = rules.indexOf("match /pre_pedidos/{pedidoId}");
    const block = rules.slice(i, rules.indexOf("}", rules.indexOf("allow delete", i)));
    assert.match(block, /allow update: if \(isStoreAdmin\(lojaId\)\s*\|\| \(resource\.data\.lojaId == lojaId\s*&& isValidPrePedidoGovernancaSubstituicao\(\)\)\)/);
    const gov = rules.slice(rules.indexOf("function isValidPrePedidoGovernancaSubstituicao"));
    assert.match(gov, /hasOnly\(\['governancaStatus', 'substituidoPor', 'substituidoEm', 'dataAtualizacao'\]\)/);
    const create = rules.slice(rules.indexOf("function isValidPrePedidoCreate"), rules.indexOf("function isValidPrePedidoGovernancaSubstituicao"));
    assert.match(create, /!request\.resource\.data\.keys\(\)\.hasAny\(\['shipping', 'shippingPreOrder', 'shippingModelVersion'\]\)/);
    assert.match(rules, /match \/shipping_preorders\/\{shippingPreOrderId\} \{[^}]*allow create, update, delete: if false;/);
  });

  it("tenant A usa só o token de A; loja sem conta não usa token de outra", async () => {
    const db = newDb({ ...storeDocs(), ...storeDocs({ storeId: STORE_B, token: TOKEN_B }), ...marker() });
    const fetchImpl = makeFetch();
    await runPaid({ db, fetchImpl });
    assert.ok(fetchImpl.calls.length > 0);
    assert.ok(fetchImpl.calls.every((c) => c.auth === `Bearer ${TOKEN_A}`));
    assert.ok(!db.reads.some((p) => p.startsWith(`lojas/${STORE_B}/`)));

    const dbNoAccount = newDb({ ...storeDocs({ token: null }), ...storeDocs({ storeId: STORE_B, token: TOKEN_B }), ...marker() });
    const f2 = makeFetch();
    const res = await runPaid({ db: dbNoAccount, fetchImpl: f2 });
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.PROVIDER_ACCOUNT_NOT_CONNECTED);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(f2.calls.length, 0);
  });

  const tampered = [
    ["preço adulterado", (o) => ({ ...o, frete: { ...o.frete, valor: 1 }, total: 151 }), SHIPPING_QUOTE_ERROR.PRICE_MISMATCH],
    ["serviço trocado", (o) => ({ ...o, frete: { ...o.frete, service_id: 1 } }), SHIPPING_QUOTE_ERROR.SERVICE_MISMATCH],
    ["outro CEP", (o) => ({ ...o, cliente: { ...o.cliente, endereco: { ...o.cliente.endereco, cep: "01001000" } } }), SHIPPING_QUOTE_ERROR.DESTINATION_MISMATCH],
    ["itens/peso alterados", (o) => ({ ...o, itens: [{ productId: "p1", nome: "X", quantidade: 9, precoUnitario: 1 }] }), SHIPPING_QUOTE_ERROR.ITEMS_MISMATCH],
    ["sem recibo", (o) => ({ ...o, frete: { ...o.frete, shippingQuoteId: undefined } }), SHIPPING_QUOTE_ERROR.MISSING],
  ];
  for (const [name, mutate, code] of tampered) {
    it(`frete adulterado (${name}) falha sem chamar o provedor`, async () => {
      const db = newDb({ ...storeDocs(), ...marker() });
      const fetchImpl = makeFetch();
      const res = await runPaid({ db, fetchImpl, o: mutate(order()) });
      assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
      assert.equal(res.lastErrorCode, code);
      assert.equal(fetchImpl.calls.length, 0);
    });
  }

  it("recibo de outra loja ou expirado falha sem chamar o provedor", async () => {
    const other = newDb({ ...storeDocs(), ...marker() });
    other.docs.delete(`lojas/${STORE_A}/shipping_quotes/${RECEIPT}`);
    Object.entries(receiptDocs({ storeId: STORE_B })).forEach(([k, v]) => other.docs.set(k, v));
    const f1 = makeFetch();
    assert.equal((await runPaid({ db: other, fetchImpl: f1 })).lastErrorCode, SHIPPING_QUOTE_ERROR.NOT_FOUND);
    const expired = newDb({ ...storeDocs(), ...marker() });
    const f2 = makeFetch();
    const res = await runPaid({ db: expired, fetchImpl: f2, createTimeMs: CREATED_AFTER + 61 * 60_000 });
    assert.equal(res.lastErrorCode, SHIPPING_QUOTE_ERROR.EXPIRED);
    assert.equal(f1.calls.length + f2.calls.length, 0);
  });

  it("estado/ID de envio forjado pelo cliente no pedido é ignorado", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    const fetchImpl = makeFetch();
    const forged = order("melhor_envio", {
      shipping: { export: { status: "exported", providerShipmentId: "forjado", operationId: "x" }, price: 0 },
    });
    const res = await runPaid({ db, fetchImpl, o: forged });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
    assert.equal(exportDoc(db).providerShipmentId, "me-cart-1");
    assert.equal(orderDoc(db).shipping.export.providerShipmentId, "me-cart-1");
    assert.equal(orderDoc(db).shipping.price, 15, "preço do resumo vem do recibo");
  });

  it("remetente não cadastrado falha sem chamar o provedor", async () => {
    const db = newDb({ ...storeDocs({ sender: null }), ...marker() });
    const fetchImpl = makeFetch();
    assert.equal((await runPaid({ db, fetchImpl })).lastErrorCode, SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED);
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
      const db = newDb({ ...storeDocs(), ...marker() });
      const fetchImpl = makeFetch({ post: { status, body: { message: "segredo do provedor", token: "x" } } });
      const res = await runPaid({ db, fetchImpl });
      assert.equal(res.status, final);
      assert.equal(res.lastErrorCode, code);
      assert.ok(!JSON.stringify(exportDoc(db)).includes("segredo do provedor"));
      assert.ok(!JSON.stringify(orderDoc(db).shipping).includes("segredo do provedor"));
    });
  }

  it("timeout e 2xx sem id ficam incertos (unknown); falha de DNS é falha definitiva", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    assert.equal((await runPaid({ db, fetchImpl: makeFetch({ throwOnPost: timeoutError() }) })).status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    const db2 = newDb({ ...storeDocs(), ...marker() });
    assert.equal((await runPaid({ db: db2, fetchImpl: makeFetch({ post: { status: 200, body: "<html>" } }) })).status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    const db3 = newDb({ ...storeDocs(), ...marker() });
    const res = await runPaid({ db: db3, fetchImpl: makeFetch({ throwOnPost: dnsError() }) });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.PROVIDER_UNREACHABLE);
  });
});

describe("resultado incerto, retry e idempotência", () => {
  async function seedUnknown(extraDocs = {}) {
    const db = newDb({ ...storeDocs(), ...marker(), ...extraDocs });
    await runPaid({ db, fetchImpl: makeFetch({ throwOnPost: timeoutError() }) });
    assert.equal(exportDoc(db).status, SHIPPING_EXPORT_STATUS.UNKNOWN);
    return db;
  }

  it("após timeout, nenhum gatilho automático faz novo POST", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch();
    await runPaid({ db, fetchImpl });
    const auto = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      orderCreateTimeMs: CREATED_AFTER, trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_CONFIRMED, fetchImpl,
    });
    assert.equal(auto.reason, "already_attempted");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("retry do lojista sem decisão explícita é recusado (sem POST)", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch();
    await assert.rejects(retryCallable(db, fetchImpl), (e) => e.code === "failed-precondition"
      && e.details?.code === "SHIPPING_EXPORT_RESOLUTION_REQUIRED");
    const direct = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      orderCreateTimeMs: CREATED_AFTER, trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY, fetchImpl,
    });
    assert.equal(direct.reason, "uncertain_requires_merchant_resolution");
    assert.equal(fetchImpl.calls.length, 0);
    await assert.rejects(retryCallable(db, fetchImpl, "qualquer"), (e) => e.code === "invalid-argument");
  });

  it("lojista confirma que já está no carrinho → exportado manualmente, sem POST", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch();
    const res = await retryCallable(db, fetchImpl, SHIPPING_EXPORT_RESOLUTION.ALREADY_IN_CART);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.calls.length, 0);
    const exp = exportDoc(db);
    assert.equal(exp.reconciledManually, true);
    assert.equal(exp.providerShipmentId, null);
    assert.equal(exp.resolvedByUid, "uid-1");
  });

  it("lojista confirma que não está no carrinho → exatamente um POST", async () => {
    const db = await seedUnknown();
    const fetchImpl = makeFetch();
    const res = await retryCallable(db, fetchImpl, SHIPPING_EXPORT_RESOLUTION.NOT_IN_CART);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
    assert.equal(exportDoc(db).attempts, 2);
    assert.equal(exportDoc(db).providerShipmentId, "me-cart-1");
  });

  it("exportação travada (lease vencido) é tratada como incerta", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, paidAfter(order()));
    db.docs.set(`lojas/${STORE_A}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`, {
      status: SHIPPING_EXPORT_STATUS.EXPORTING,
      leaseUntil: Timestamp.fromMillis(Date.now() - 1000),
    });
    const fetchImpl = makeFetch();
    await assert.rejects(retryCallable(db, fetchImpl), (e) => e.details?.code === "SHIPPING_EXPORT_RESOLUTION_REQUIRED");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("exportação em andamento (lease ativo) não cria outra", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, paidAfter(order()));
    db.docs.set(`lojas/${STORE_A}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`, {
      status: SHIPPING_EXPORT_STATUS.EXPORTING,
      leaseUntil: Timestamp.fromMillis(Date.now() + 60_000),
    });
    const fetchImpl = makeFetch();
    await assert.rejects(retryCallable(db, fetchImpl), (e) => e.code === "failed-precondition");
    const res = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      orderCreateTimeMs: CREATED_AFTER, trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY, fetchImpl,
    });
    assert.equal(res.reason, "export_in_progress");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("falha definitiva: gatilho automático não repete; retry do lojista sim", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch({ post: { status: 422, body: {} } }) });
    const auto = makeFetch();
    await runPaid({ db, fetchImpl: auto });
    assert.equal(auto.calls.length, 0);
    const manual = makeFetch();
    const res = await retryCallable(db, manual);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(manual.posts().length, 1);
    assert.equal(exportDoc(db).attempts, 2);
  });

  it("já exportado → retry recusado e nenhuma chamada", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    await runPaid({ db, fetchImpl: makeFetch() });
    const fetchImpl = makeFetch();
    await assert.rejects(retryCallable(db, fetchImpl), (e) => e.code === "failed-precondition");
    const res = await exportShippingOrder({
      db, collectionLojas: "lojas", storeId: STORE_A, orderId: ORDER, order: orderDoc(db),
      orderCreateTimeMs: CREATED_AFTER, trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY, fetchImpl,
    });
    assert.equal(res.idempotent, true);
    assert.equal(fetchImpl.calls.length, 0);
  });
});

describe("SuperFrete", () => {
  it("contrato de exportação não verificado: produção falha fechado, sem chamada", async () => {
    assert.equal(SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED, false);
    const db = newDb({ ...storeDocs({ provider: "superfrete", token: TOKEN_A, sandbox: false }), ...marker() });
    const fetchImpl = makeFetch();
    const res = await runPaid({ db, fetchImpl, o: order("superfrete") });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED);
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("token de sandbox também não exporta enquanto o contrato não for verificado", async () => {
    const db = newDb({ ...storeDocs({ provider: "superfrete", token: TOKEN_A, sandbox: true }), ...marker() });
    const fetchImpl = makeFetch({ post: { status: 200, body: { id: "sf-1" } } });
    const res = await runPaid({ db, fetchImpl, o: order("superfrete") });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.FAILED);
    assert.equal(res.lastErrorCode, SHIPPING_EXPORT_ERROR.PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED);
    assert.equal(fetchImpl.calls.length, 0);
  });

  const sfShippingOrder = () => buildShippingOrder({
    order: order("superfrete"), storeId: STORE_A, orderId: ORDER, provider: "superfrete", sender: SENDER,
    quote: {
      provider: "superfrete", shippingQuoteId: QUOTE_ID, serviceId: "1", serviceName: "PAC",
      quotedPrice: 15, chargedPrice: 15, insuranceValue: 150,
      providerPackage: { height: 10, width: 20, length: 30, weight: 0.45 },
    },
  }).shippingOrder;

  it("homologação (contrato verificado só no teste): POST /api/v0/cart com serviço e pacote cotados", async () => {
    const fetchImpl = makeFetch({ post: { status: 200, body: { id: "sf-1" } } });
    const res = await exportSuperFrete({
      shippingOrder: sfShippingOrder(), credentials: { token: TOKEN_A, sandbox: true }, fetchImpl, contractVerified: true,
    });
    assert.equal(res.outcome, "exported");
    const posts = fetchImpl.posts();
    assert.equal(posts.length, 1);
    assert.match(posts[0].url, /^https:\/\/sandbox\.superfrete\.com\/api\/v0\/cart$/);
    assert.equal(posts[0].body.service, 1);
    assert.deepEqual(posts[0].body.volume, { height: 10, width: 20, length: 30, weight: 0.45 });
    assert.equal(posts[0].body.tag, "shipping:superfrete:loja-a:pedido-1");
  });

  it("homologação: resposta inválida vira incerto (sem novo POST)", async () => {
    const fetchImpl = makeFetch({ post: { status: 502, body: "<html>" } });
    const res = await exportSuperFrete({
      shippingOrder: sfShippingOrder(), credentials: { token: TOKEN_A, sandbox: true }, fetchImpl, contractVerified: true,
    });
    assert.equal(res.outcome, "unknown");
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("flag SuperFrete não pode ser ligada; desligar é permitido", async () => {
    const db = newDb();
    await assert.rejects(
      handlers(db, { data: { lojaId: STORE_A, flags: { superFrete: true } } }).shippingSaveAutomationConfig(),
      (e) => e.code === "failed-precondition" && e.details?.code === SHIPPING_EXPORT_ERROR.PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED,
    );
    assert.equal(db.writes.length, 0);
    await handlers(db, { data: { lojaId: STORE_A, flags: { superFrete: false, melhorEnvio: false } } }).shippingSaveAutomationConfig();
    const saved = db.docs.get(`lojas/${STORE_A}/config/fretes_secrets`);
    assert.equal(saved.automation.shippingAutoExportSuperFrete, false);
    assert.equal(saved.automation.shippingAutoExportMelhorEnvio, false);
  });
});

describe("logs sem PII", () => {
  it("SHIPPING_EXPORT não contém nome, CEP, CPF, endereço, telefone ou token", async () => {
    const lines = [];
    const orig = console.log;
    console.log = (...a) => lines.push(a.join(" "));
    try {
      const db = newDb({ ...storeDocs(), ...marker() });
      await runPaid({ db, fetchImpl: makeFetch() });
      const db2 = newDb({ ...storeDocs(), ...marker() });
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
  it("salvar configuração exige admin da loja", async () => {
    const db = newDb();
    await assert.rejects(
      handlers(db, { allowed: false, data: { lojaId: STORE_A, flags: { melhorEnvio: true } } }).shippingSaveAutomationConfig(),
      (e) => e.code === "permission-denied",
    );
    assert.equal(db.writes.length, 0);
  });

  it("retry exige admin da loja (cliente não dispara exportação)", async () => {
    const db = await (async () => {
      const d = newDb({ ...storeDocs(), ...marker() });
      await runPaid({ db: d, fetchImpl: makeFetch({ post: { status: 422, body: {} } }) });
      return d;
    })();
    const fetchImpl = makeFetch();
    await assert.rejects(
      handlers(db, { allowed: false, data: { lojaId: STORE_A, orderId: ORDER }, fetchImpl }).retryShippingExport(),
      (e) => e.code === "permission-denied",
    );
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("remetente incompleto é rejeitado; documento mascarado não sobrescreve; IE salva", async () => {
    const db = newDb();
    await assert.rejects(
      handlers(db, { data: { lojaId: STORE_A, sender: { ...SENDER, city: "" } } }).shippingSaveAutomationConfig(),
      (e) => e.code === "invalid-argument",
    );
    await handlers(db, { data: { lojaId: STORE_A, sender: { ...SENDER, stateRegister: "isento" }, flags: { melhorEnvio: true } } }).shippingSaveAutomationConfig();
    await handlers(db, { data: { lojaId: STORE_A, sender: { ...SENDER, companyDocument: "••••0190" } } }).shippingSaveAutomationConfig();
    const saved = db.docs.get(`lojas/${STORE_A}/config/fretes_secrets`);
    assert.equal(saved.sender.companyDocument, "12345678000190");
    assert.equal(saved.sender.stateRegister, "ISENTO");
    assert.equal(saved.automation.shippingAutoExportMelhorEnvio, true);
    const cfg = await handlers(db, { data: { lojaId: STORE_A } }).shippingGetAutomationConfig();
    assert.equal(cfg.flags.melhorEnvio, true);
    assert.equal(cfg.flags.superFrete, false);
    assert.equal(cfg.superFreteExportContractVerified, false);
    assert.equal(cfg.sender.companyDocumentMasked, "••••0190");
    assert.equal(cfg.senderComplete, true);
    assert.ok(!JSON.stringify(cfg).includes("12345678000190"));
  });

  it("retry só para falha/incerto e pedido confirmado", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, order());
    await assert.rejects(retryCallable(db, makeFetch()), (e) => e.code === "failed-precondition");
    await runPaid({ db, fetchImpl: makeFetch({ post: { status: 429, body: {} } }) });
    const fetchImpl = makeFetch();
    const res = await retryCallable(db, fetchImpl);
    assert.equal(res.ok, true);
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.posts().length, 1);
  });

  it("retry ignora shipping.export forjado no pedido (estado vem do ledger)", async () => {
    const db = newDb({ ...storeDocs(), ...marker() });
    db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, order("melhor_envio", {
      status: "paid",
      paymentId: "pay-1",
      shipping: { export: { status: SHIPPING_EXPORT_STATUS.FAILED } },
    }));
    const fetchImpl = makeFetch();
    await assert.rejects(retryCallable(db, fetchImpl), (e) => e.code === "failed-precondition");
    for (const forged of [SHIPPING_EXPORT_STATUS.UNKNOWN, SHIPPING_EXPORT_STATUS.EXPORTING]) {
      db.docs.set(`lojas/${STORE_A}/pre_pedidos/${ORDER}`, { ...orderDoc(db), shipping: { export: { status: forged } } });
      await assert.rejects(
        retryCallable(db, fetchImpl, SHIPPING_EXPORT_RESOLUTION.NOT_IN_CART),
        (e) => e.code === "failed-precondition",
      );
    }
    assert.equal(fetchImpl.posts().length, 0);
  });
});
