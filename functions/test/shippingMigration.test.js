/**
 * node --test test/shippingMigration.test.js
 *
 * Release do frete com recibo: pedidos legados (createTime < corte) continuam pagando como antes
 * e nunca exportam; pedidos novos exigem recibo. Expiração lógica independe da TTL.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Timestamp } from "firebase-admin/firestore";

import {
  SHIPPING_MODEL,
  SHIPPING_MODEL_VERSION,
  SHIPPING_QUOTE_ERROR,
  SHIPPING_QUOTE_RETENTION_MS,
  SHIPPING_QUOTE_VALIDITY_MS,
  SUPPORTED_PACKAGE_COUNT,
  SINGLE_VOLUME_MAX_WEIGHT_GRAMS,
  classifyShippingModel,
  computeCanonicalPackage,
  issueShippingQuoteReceipt,
  loadCanonicalShippingQuote,
  melhorEnvioQuotePackage,
  normalizeQuoteItems,
  parseMelhorEnvioQuoteOptions,
  validateOrderShippingForPayment,
} from "../src/shippingQuoteReceipt.js";
import {
  SHIPPING_EXPORT_STATUS,
  shippingExportDocId,
  handlePrePedidoShippingExportUpdate,
  createShippingExportHandlers,
} from "../src/shippingExport.js";
import { createShippingPreOrderHandlers } from "../src/shippingPreOrder.js";
import { makeDb } from "./shippingMemoryDb.js";

const STORE = "loja-a";
const ORDER = "pedido-1";
const PAYMENT_ID = "987654321";
const CUTOVER = Date.parse("2026-10-30T03:00:00Z");
const LEGACY_CREATED = CUTOVER - 1;
const NEW_CREATED = CUTOVER + 10 * 60_000;
const QUOTED_AT = NEW_CREATED - 5 * 60_000;
const clockAt = (ms) => () => ms;
const NOW = NEW_CREATED + 2 * 60_000;

const ITEMS = [{ productId: "p1", quantity: 2 }, { productId: "p2", quantity: 1 }];

function baseDocs({ flag = true } = {}) {
  return {
    [`lojas/${STORE}`]: { ownerUid: "owner-a" },
    [`lojas/${STORE}/produtos/p1`]: { peso: 100, tipoEmbalagem: "padrao" },
    [`lojas/${STORE}/produtos/p2`]: { peso: 150, tipoEmbalagem: "media" },
    [`lojas/${STORE}/config/fretes`]: { cepOrigem: "01310100" },
    [`lojas/${STORE}/config/fretes_secrets`]: {
      melhor_envio: { token: "token_loja_a_abcdefghijklmnopqrstuvwxyz", sandbox: false },
      automation: { shippingAutoExportMelhorEnvio: flag },
      sender: {
        name: "Loja A Ltda", companyDocument: "12345678000190", phone: "11988887777", postalCode: "01310100",
        address: "Rua da Loja", number: "50", district: "Centro", city: "Sao Paulo", state: "SP",
        shippingDocument: "declaracao_conteudo",
      },
    },
    [`_mp_webhook_processed/${PAYMENT_ID}`]: { status: "applied", lojaId: STORE, orderId: ORDER },
  };
}

async function issueReceipt(db, { quotedAt = QUOTED_AT } = {}) {
  const pkg = await computeCanonicalPackage({ db, collectionLojas: "lojas", storeId: STORE, items: ITEMS });
  const { quoteIds } = await issueShippingQuoteReceipt({
    db,
    collectionLojas: "lojas",
    storeId: STORE,
    provider: "melhor_envio",
    originCep: pkg.originCep,
    destinationCep: "20040020",
    canonicalPackage: pkg.package,
    providerPackage: melhorEnvioQuotePackage(pkg.package),
    insuranceValue: 150,
    items: ITEMS,
    options: parseMelhorEnvioQuoteOptions([
      { id: 4, name: "SEDEX", price: "15.00", delivery_time: 3, company: { id: 1, name: "Correios" } },
    ]),
    nowMs: quotedAt,
  });
  return quoteIds.get(0);
}

function order(quoteId, extra = {}) {
  return {
    lojaId: STORE,
    status: "pendente",
    subtotal: 150,
    total: 165,
    pagamento: "pix",
    cliente: {
      nome: "Maria Cliente",
      cpf: "98765432100",
      telefone: "11977776666",
      endereco: {
        cep: "20040020", rua: "Av Rio Branco", numero: "100", bairro: "Centro", cidade: "Rio de Janeiro", estado: "RJ",
      },
    },
    itens: [
      { productId: "p1", nome: "Colar", quantidade: 2, precoUnitario: 50, total: 100 },
      { productId: "p2", nome: "Brinco", quantidade: 1, precoUnitario: 50, total: 50 },
    ],
    frete: {
      nome: "SEDEX", valor: 15, gratis: false, tipo: "melhor_envio", plataforma: "melhor_envio", service_id: 4,
      ...(quoteId ? { shippingQuoteId: quoteId } : {}),
    },
    ...extra,
  };
}

const paid = (o) => ({ ...o, status: "paid", statusPagamento: "aprovado", paymentId: PAYMENT_ID, paidAt: "ts" });

function makeFetch() {
  const calls = [];
  const impl = async (url, opts = {}) => {
    calls.push({ url, method: opts.method });
    return { ok: true, status: 201, text: async () => JSON.stringify({ id: "me-cart-1" }) };
  };
  impl.calls = calls;
  return impl;
}

const pay = (db, o, createdMs, { cutoverMs = CUTOVER, nowMs = NOW } = {}) => validateOrderShippingForPayment({
  db, collectionLojas: "lojas", storeId: STORE, order: o, orderCreateTimeMs: createdMs, cutoverMs, nowMs,
});

const quoteReads = (db) => db.reads.filter((p) => p.includes("/shipping_quotes/")).length;

// ---------------------------------------------------------------------------

describe("classificação legado × novo (só timestamps do servidor)", () => {
  it("createTime < corte → legado; exatamente no corte e depois → recibo obrigatório", () => {
    assert.equal(classifyShippingModel({ createTimeMs: CUTOVER - 1, cutoverMs: CUTOVER }).model, SHIPPING_MODEL.LEGACY);
    assert.equal(classifyShippingModel({ createTimeMs: CUTOVER, cutoverMs: CUTOVER }).model, SHIPPING_MODEL.QUOTE_RECEIPT);
    assert.equal(classifyShippingModel({ createTimeMs: CUTOVER + 1, cutoverMs: CUTOVER }).model, SHIPPING_MODEL.QUOTE_RECEIPT);
  });

  it("sem corte válido ou sem createTime → recibo obrigatório (falha fechado)", () => {
    for (const cutoverMs of [null, undefined, NaN]) {
      assert.equal(classifyShippingModel({ createTimeMs: LEGACY_CREATED, cutoverMs }).model, SHIPPING_MODEL.QUOTE_RECEIPT);
    }
    assert.equal(classifyShippingModel({ createTimeMs: NaN, cutoverMs: CUTOVER }).model, SHIPPING_MODEL.QUOTE_RECEIPT);
  });
});

describe("pagamento na migração", () => {
  it("pedido legado sem recibo continua pagando (sem ler recibo, sem escrever nada)", async () => {
    const db = makeDb(baseDocs());
    const res = await pay(db, order(undefined), LEGACY_CREATED);
    assert.equal(res.ok, true);
    assert.equal(res.required, false);
    assert.equal(res.shippingModel, SHIPPING_MODEL.LEGACY);
    assert.equal(quoteReads(db), 0);
    assert.equal(db.writes.length, 0);
  });

  it("pedido novo sem recibo falha", async () => {
    const res = await pay(makeDb(baseDocs()), order(undefined), NEW_CREATED);
    assert.equal(res.ok, false);
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.MISSING);
  });

  it("pedido novo com recibo expirado falha", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db, { quotedAt: NEW_CREATED - SHIPPING_QUOTE_VALIDITY_MS - 1 });
    const res = await pay(db, order(id), NEW_CREATED);
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.EXPIRED);
  });

  it("pedido novo com recibo válido segue para a cobrança", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db);
    const res = await pay(db, order(id), NEW_CREATED);
    assert.equal(res.ok, true);
    assert.equal(res.required, true);
    assert.equal(res.shippingModel, SHIPPING_MODEL.QUOTE_RECEIPT);
  });

  it("pedido criado exatamente no corte segue o modelo novo", async () => {
    const res = await pay(makeDb(baseDocs()), order(undefined), CUTOVER);
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.MISSING);
  });

  it("createdAt/flags do cliente não contornam o corte", async () => {
    const forged = order(undefined, {
      createdAt: Timestamp.fromMillis(CUTOVER - 86_400_000),
      dataCriacao: Timestamp.fromMillis(CUTOVER - 86_400_000),
      legacy: true,
      createdBeforeCutover: true,
      shippingModelVersion: "legacy",
    });
    const res = await pay(makeDb(baseDocs()), forged, NEW_CREATED);
    assert.equal(res.ok, false);
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.MISSING);
  });

  it("pedido legado não vira modelo novo por campo do cliente", async () => {
    const db = makeDb(baseDocs());
    const res = await pay(db, order("f".repeat(32) + ".0", { shippingModelVersion: 2 }), LEGACY_CREATED);
    assert.equal(res.shippingModel, SHIPPING_MODEL.LEGACY);
    assert.equal(quoteReads(db), 0);
  });

  it("corte ausente em runtime → pedido antigo também exige recibo (falha fechado)", async () => {
    const res = await pay(makeDb(baseDocs()), order(undefined), LEGACY_CREATED, { cutoverMs: null });
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.MISSING);
  });

  it("mpCatalogPayment classifica pelo createTime do documento e pelo corte do deploy", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const payBlock = src.slice(src.indexOf("export const mpCatalogPayment"));
    const call = payBlock.slice(payBlock.indexOf("validateOrderShippingForPayment("), payBlock.indexOf("if (!shippingCheck.ok)"));
    assert.match(call, /orderCreateTimeMs: resolvedOrder\.createTimeMs/);
    assert.match(call, /cutoverMs: shippingCutoverMs\(\)/);
    const helper = readFileSync(new URL("../src/catalogMpOrderHelpers.js", import.meta.url), "utf8");
    assert.match(helper, /createTimeMs: typeof snap\.createTime\?\.toMillis === "function" \? snap\.createTime\.toMillis\(\) : null/);
  });
});

describe("pedido legado nunca exporta", () => {
  async function runLegacy({ trigger }) {
    const db = makeDb(baseDocs(), { createTimeMs: LEGACY_CREATED });
    const id = await issueReceipt(db);
    const o = order(id, { shippingModelVersion: SHIPPING_MODEL_VERSION });
    const after = trigger === "paid" ? paid(o) : { ...o, status: "confirmado", vendaId: "v1" };
    db.docs.set(`lojas/${STORE}/pre_pedidos/${ORDER}`, after);
    const writesBefore = db.writes.length;
    const fetchImpl = makeFetch();
    const res = await handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE, orderId: ORDER, before: o, after,
      createTimeMs: LEGACY_CREATED, cutoverMs: CUTOVER, fetchImpl, now: clockAt(NOW),
      authType: "unknown", authId: "owner-a", isStoreAdminUid: async () => true,
    });
    return { res, calls: fetchImpl.calls.length, writes: db.writes.length - writesBefore };
  }

  for (const trigger of ["paid", "merchant_confirmed"]) {
    it(`${trigger}: skip historical_order, sem chamada e sem escrita (mesmo com flag e marcador forjado)`, async () => {
      const { res, calls, writes } = await runLegacy({ trigger });
      assert.equal(res.reason, "historical_order");
      assert.equal(calls, 0);
      assert.equal(writes, 0);
    });
  }

  it("retry do lojista em pedido legado é recusado antes de qualquer chamada", async () => {
    const db = makeDb(baseDocs(), { createTimeMs: LEGACY_CREATED });
    db.docs.set(`lojas/${STORE}/pre_pedidos/${ORDER}`, paid(order(undefined)));
    db.docs.set(`lojas/${STORE}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`, { status: "failed" });
    for (const cutoverMs of [CUTOVER, null]) {
      const fetchImpl = makeFetch();
      const h = createShippingExportHandlers({
        db, collectionLojas: "lojas", canManageStoreConfigServerSide: async () => true,
        checkRateLimit: async () => {}, getCallableIdentifier: () => "owner-a", fetchWithTimeout: fetchImpl,
        request: { auth: { uid: "owner-a", token: {} }, data: { lojaId: STORE, orderId: ORDER } },
        cutoverMs, now: clockAt(NOW),
      });
      await assert.rejects(h.retryShippingExport(), (e) => e.code === "failed-precondition"
        && e.details?.code === "SHIPPING_EXPORT_LEGACY_ORDER");
      assert.equal(fetchImpl.calls.length, 0);
    }
  });
});

describe("sem exportação dupla (fluxo antigo × novo)", () => {
  const preOrderHandlers = (db, fetchImpl, cutoverMs) => createShippingPreOrderHandlers({
    db, collectionLojas: "lojas", canManageStoreConfigServerSide: async () => true,
    checkRateLimit: async () => {}, getCallableIdentifier: () => "owner-a", fetchWithTimeout: fetchImpl,
    request: { auth: { uid: "owner-a", token: {} }, data: { lojaId: STORE, orderId: ORDER } },
    cutoverMs,
  });

  it("retry do fluxo antigo recusa pedido novo, mesmo com shippingPreOrder.status=failed gravado", async () => {
    for (const cutoverMs of [CUTOVER, null]) {
      const db = makeDb(baseDocs(), { createTimeMs: NEW_CREATED });
      db.docs.set(`lojas/${STORE}/pre_pedidos/${ORDER}`, order(undefined, { shippingPreOrder: { status: "failed" } }));
      const fetchImpl = makeFetch();
      await assert.rejects(preOrderHandlers(db, fetchImpl, cutoverMs).retryShippingPreOrder(),
        (e) => e.code === "failed-precondition" && e.details?.code === "PRE_ORDER_FLOW_RETIRED");
      assert.equal(fetchImpl.calls.length, 0);
      assert.equal(db.writes.length, 0);
    }
  });

  it("pedido legado continua com as regras do fluxo antigo (passa do corte)", async () => {
    const db = makeDb(baseDocs(), { createTimeMs: LEGACY_CREATED });
    db.docs.set(`lojas/${STORE}/pre_pedidos/${ORDER}`, order(undefined));
    const fetchImpl = makeFetch();
    await assert.rejects(preOrderHandlers(db, fetchImpl, CUTOVER).retryShippingPreOrder(),
      (e) => e.details?.code === "PRE_ORDER_NOT_RETRYABLE");
    assert.equal(fetchImpl.calls.length, 0);
  });

  it("pedido novo exporta uma vez e o ledger leva shippingModelVersion do servidor", async () => {
    const db = makeDb(baseDocs(), { createTimeMs: NEW_CREATED });
    const id = await issueReceipt(db);
    const o = order(id, { shippingModelVersion: "legacy" });
    db.docs.set(`lojas/${STORE}/pre_pedidos/${ORDER}`, paid(o));
    const fetchImpl = makeFetch();
    const res = await handlePrePedidoShippingExportUpdate({
      db, collectionLojas: "lojas", storeId: STORE, orderId: ORDER, before: o, after: paid(o),
      createTimeMs: NEW_CREATED, cutoverMs: CUTOVER, fetchImpl, now: clockAt(NOW),
    });
    assert.equal(res.status, SHIPPING_EXPORT_STATUS.EXPORTED);
    assert.equal(fetchImpl.calls.filter((c) => c.method === "POST").length, 1);
    const ledger = db.docs.get(`lojas/${STORE}/shipping_preorders/${shippingExportDocId("melhor_envio", ORDER)}`);
    assert.equal(ledger.shippingModelVersion, SHIPPING_MODEL_VERSION);
    assert.equal(ledger.providerShipmentId, "me-cart-1");
  });

  it("rules: cliente não grava shippingModelVersion na criação do pré-pedido", () => {
    const rules = readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8");
    const create = rules.slice(rules.indexOf("function isValidPrePedidoCreate"), rules.indexOf("function isValidPrePedidoGovernancaSubstituicao"));
    assert.match(create, /hasAny\(\['shipping', 'shippingPreOrder', 'shippingModelVersion'\]\)/);
  });
});

describe("TTL é limpeza; a expiração é lógica", () => {
  it("recibo ainda no banco após expiresAt: pedido criado depois da validade é rejeitado", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db);
    const res = await loadCanonicalShippingQuote({
      db, collectionLojas: "lojas", storeId: STORE, provider: "melhor_envio", order: order(id),
      orderCreateTimeMs: QUOTED_AT + SHIPPING_QUOTE_VALIDITY_MS + 1, nowMs: QUOTED_AT + 2 * SHIPPING_QUOTE_VALIDITY_MS,
    });
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.EXPIRED);
  });

  it("recibo além da retenção ainda não apagado pela TTL é rejeitado", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db);
    const base = { db, collectionLojas: "lojas", storeId: STORE, provider: "melhor_envio", order: order(id), orderCreateTimeMs: NEW_CREATED };
    assert.equal((await loadCanonicalShippingQuote({ ...base, nowMs: QUOTED_AT + SHIPPING_QUOTE_RETENTION_MS })).ok, true);
    const late = await loadCanonicalShippingQuote({ ...base, nowMs: QUOTED_AT + SHIPPING_QUOTE_RETENTION_MS + 1 });
    assert.equal(late.code, SHIPPING_QUOTE_ERROR.EXPIRED);
  });

  it("sem retainUntilMs usa deleteAt; sem nenhum dos dois, rejeita", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db);
    const path = `lojas/${STORE}/shipping_quotes/${id.split(".")[0]}`;
    const { retainUntilMs: _r, ...withoutRetain } = db.docs.get(path);
    db.docs.set(path, withoutRetain);
    const base = { db, collectionLojas: "lojas", storeId: STORE, provider: "melhor_envio", order: order(id), orderCreateTimeMs: NEW_CREATED };
    assert.equal((await loadCanonicalShippingQuote({ ...base, nowMs: NOW })).ok, true);
    assert.equal((await loadCanonicalShippingQuote({ ...base, nowMs: QUOTED_AT + SHIPPING_QUOTE_RETENTION_MS + 1 })).code,
      SHIPPING_QUOTE_ERROR.EXPIRED);
    const { deleteAt: _d, ...neither } = withoutRetain;
    db.docs.set(path, neither);
    assert.equal((await loadCanonicalShippingQuote({ ...base, nowMs: NOW })).code, SHIPPING_QUOTE_ERROR.EXPIRED);
  });

  it("deleteAt é Timestamp do Firestore gravado só pelo servidor", async () => {
    const db = makeDb(baseDocs());
    const id = await issueReceipt(db);
    const saved = db.docs.get(`lojas/${STORE}/shipping_quotes/${id.split(".")[0]}`);
    assert.ok(saved.deleteAt instanceof Timestamp);
    assert.equal(saved.deleteAt.toMillis(), QUOTED_AT + SHIPPING_QUOTE_RETENTION_MS);
    assert.equal(saved.retainUntilMs, saved.deleteAt.toMillis());

    const rules = readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8");
    assert.match(rules, /match \/shipping_quotes\/\{receiptId\} \{\s*allow read, write: if false;/);
    const writers = ["../src/shippingQuoteReceipt.js", "../src/shippingExport.js", "../src/superFreteIntegration.js", "../index.js"]
      .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
      .join("\n");
    assert.equal((writers.match(/collection\(SHIPPING_QUOTES_COL\)/g) ?? []).length, 2, "um set (emissão) e um get (validação)");
    assert.ok(!/["']shipping_quotes["']/.test(writers.replace('export const SHIPPING_QUOTES_COL = "shipping_quotes";', "")));
  });

  it("política TTL preparada no firestore.indexes.json (shipping_quotes.deleteAt)", () => {
    const cfg = JSON.parse(readFileSync(new URL("../../firestore.indexes.json", import.meta.url), "utf8"));
    const ttl = cfg.fieldOverrides.find((f) => f.collectionGroup === "shipping_quotes" && f.fieldPath === "deleteAt");
    assert.deepEqual(ttl, { collectionGroup: "shipping_quotes", fieldPath: "deleteAt", ttl: true, indexes: [] });
  });
});

describe("volume único", () => {
  const pkgFor = (docs, items = ITEMS) => computeCanonicalPackage({
    db: makeDb({ ...baseDocs(), ...docs }), collectionLojas: "lojas", storeId: STORE, items,
  });

  it("um volume por pedido; acima do limite não cota (sem somar em pacote inválido)", async () => {
    assert.equal(SUPPORTED_PACKAGE_COUNT, 1);
    const heavy = await pkgFor({ [`lojas/${STORE}/produtos/p1`]: { peso: 20000, tipoEmbalagem: "padrao" } });
    assert.equal(heavy.code, SHIPPING_QUOTE_ERROR.MULTI_VOLUME_REQUIRED);
    const tall = await pkgFor({
      [`lojas/${STORE}/config/fretes`]: { cepOrigem: "01310100", embalagens: [{ id: "padrao", peso: 50, tamanho: 1, altura: 120, largura: 20, comprimento: 30 }] },
    });
    assert.equal(tall.code, SHIPPING_QUOTE_ERROR.MULTI_VOLUME_REQUIRED);
    const sum = await pkgFor({
      [`lojas/${STORE}/config/fretes`]: { cepOrigem: "01310100", embalagens: [{ id: "padrao", peso: 50, tamanho: 1, altura: 70, largura: 70, comprimento: 70 }] },
    });
    assert.equal(sum.code, SHIPPING_QUOTE_ERROR.MULTI_VOLUME_REQUIRED);
  });

  it("no limite exato ainda cota", async () => {
    const items = normalizeQuoteItems([{ productId: "p1", quantidade: 1 }]).items;
    const res = await pkgFor({
      [`lojas/${STORE}/produtos/p1`]: { peso: SINGLE_VOLUME_MAX_WEIGHT_GRAMS - 50, tipoEmbalagem: "padrao" },
    }, items);
    assert.equal(res.ok, true);
    assert.equal(res.package.weightGrams, SINGLE_VOLUME_MAX_WEIGHT_GRAMS);
  });

  it("cotação devolve lista vazia com o código (carrinho fica com as opções manuais)", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const me = src.slice(src.indexOf("export const calcularMelhorEnvio"), src.indexOf("export const testarMelhorEnvioToken"));
    assert.match(me, /if \(!pkg\.ok\) return \{ servicos: \[\], erro: pkg\.code \};/);
  });
});
