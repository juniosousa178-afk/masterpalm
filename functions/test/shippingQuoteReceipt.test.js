/**
 * node --test test/shippingQuoteReceipt.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  SHIPPING_QUOTE_ERROR,
  SHIPPING_QUOTE_VALIDITY_MS,
  normalizeQuoteItems,
  computeCanonicalPackage,
  melhorEnvioQuotePackage,
  parseMelhorEnvioQuoteOptions,
  issueShippingQuoteReceipt,
  loadCanonicalShippingQuote,
  validateOrderShippingForPayment,
  parseShippingQuoteId,
} from "../src/shippingQuoteReceipt.js";
import { createSuperFreteHandlers, SUPERFRETE_QUOTE_PATH } from "../src/superFreteIntegration.js";
import { makeDb } from "./shippingMemoryDb.js";

const STORE_A = "loja-a";
const STORE_B = "loja-b";
const NOW = Date.parse("2026-11-03T12:00:00Z");
const ITEMS = [{ productId: "p1", quantity: 2 }, { productId: "p2", quantity: 1 }];

function productDocs(storeId = STORE_A) {
  return {
    [`lojas/${storeId}`]: { published: true },
    [`lojas/${storeId}/produtos/p1`]: { peso: 100, tipoEmbalagem: "padrao" },
    [`lojas/${storeId}/produtos/p2`]: { peso: 150, tipoEmbalagem: "media" },
    [`lojas/${storeId}/config/fretes`]: { cepOrigem: "01310-100" },
  };
}

async function issue(db, { storeId = STORE_A, provider = "melhor_envio", price = 15, nowMs = NOW } = {}) {
  const pkg = await computeCanonicalPackage({ db, collectionLojas: "lojas", storeId, items: ITEMS });
  const providerPackage = melhorEnvioQuotePackage(pkg.package);
  return issueShippingQuoteReceipt({
    db,
    collectionLojas: "lojas",
    storeId,
    provider,
    originCep: pkg.originCep,
    destinationCep: "20040020",
    canonicalPackage: pkg.package,
    providerPackage,
    insuranceValue: 150,
    items: ITEMS,
    options: parseMelhorEnvioQuoteOptions([
      { id: 3, name: ".Package", price: "9.90", delivery_time: 6, company: { id: 2, name: "Jadlog" } },
      { id: 4, name: "SEDEX", price: String(price), delivery_time: 3, company: { id: 1, name: "Correios" } },
      { id: 17, name: "Mini", error: "Indisponível" },
    ]),
    nowMs,
  });
}

function order(quoteId, extra = {}) {
  return {
    status: "pendente",
    subtotal: 150,
    total: 165,
    cliente: { nome: "Cliente", cpf: "98765432100", endereco: { cep: "20040-020", bairro: "Centro" } },
    itens: [
      { productId: "p1", quantidade: 1, precoUnitario: 50 },
      { productId: "p2", quantidade: 1, precoUnitario: 50 },
      { productId: "p1", quantidade: 1, precoUnitario: 50 },
    ],
    frete: { nome: "SEDEX", valor: 15, gratis: false, tipo: "melhor_envio", plataforma: "melhor_envio", service_id: 4, shippingQuoteId: quoteId },
    ...extra,
  };
}

const validate = (db, o, { storeId = STORE_A, createdMs = NOW + 60_000 } = {}) => loadCanonicalShippingQuote({
  db, collectionLojas: "lojas", storeId, provider: "melhor_envio", order: o, orderCreateTimeMs: createdMs,
});

describe("pacote canônico", () => {
  it("vem dos produtos/embalagens da loja (mesma regra do carrinho)", async () => {
    const db = makeDb(productDocs());
    const res = await computeCanonicalPackage({ db, collectionLojas: "lojas", storeId: STORE_A, items: ITEMS });
    assert.equal(res.ok, true);
    // 2×100 + 1×150 + embalagem "media" (padrão do carrinho: 200 g, 20×30×40)
    assert.deepEqual(res.package, { weightGrams: 550, heightCm: 20, widthCm: 30, lengthCm: 40 });
    assert.equal(res.originCep, "01310100");
    assert.deepEqual(melhorEnvioQuotePackage(res.package), { weight: 0.55, height: 20, width: 30, length: 40 });
  });

  it("embalagens da loja substituem o padrão; produto sem peso falha", async () => {
    const db = makeDb({
      ...productDocs(),
      [`lojas/${STORE_A}/config/fretes`]: { embalagens: [{ id: "media", peso: 10, tamanho: 3, altura: 5, largura: 11, comprimento: 16 }] },
    });
    const res = await computeCanonicalPackage({ db, collectionLojas: "lojas", storeId: STORE_A, items: ITEMS });
    assert.deepEqual(res.package, { weightGrams: 360, heightCm: 5, widthCm: 11, lengthCm: 16 });
    const semPeso = makeDb({ [`lojas/${STORE_A}/produtos/p1`]: { peso: 0 } });
    const r2 = await computeCanonicalPackage({ db: semPeso, collectionLojas: "lojas", storeId: STORE_A, items: [{ productId: "p1", quantity: 1 }] });
    assert.equal(r2.code, SHIPPING_QUOTE_ERROR.PRODUCT_SHIPPING_DATA_MISSING);
  });

  it("itens: agrega por produto, rejeita quantidade/ID inválidos", () => {
    assert.deepEqual(
      normalizeQuoteItems([{ productId: "p2", quantidade: 1 }, { productId: "p1", quantidade: 1 }, { id: "p1", quantity: 1 }]).items,
      ITEMS,
    );
    for (const bad of [[], [{ productId: "a/b", quantity: 1 }], [{ productId: "p1", quantity: 0 }], [{ productId: "p1", quantity: 1.5 }], "x"]) {
      assert.equal(normalizeQuoteItems(bad).ok, false);
    }
  });
});

describe("recibo da cotação", () => {
  it("cada opção válida recebe shippingQuoteId opaco; nada de credencial no recibo", async () => {
    const db = makeDb(productDocs());
    const { receiptId, quoteIds } = await issue(db);
    assert.match(receiptId, /^[a-f0-9]{32}$/);
    assert.deepEqual([...quoteIds.keys()], [0, 1], "opção com erro não recebe ID");
    const id = quoteIds.get(1);
    assert.deepEqual(parseShippingQuoteId(id), { receiptId, optionIndex: 1 });
    const saved = db.docs.get(`lojas/${STORE_A}/shipping_quotes/${receiptId}`);
    assert.equal(saved.storeId, STORE_A);
    assert.equal(saved.options[1].price, 15);
    assert.equal(saved.options[1].serviceId, "4");
    assert.equal(saved.expiresAtMs, NOW + SHIPPING_QUOTE_VALIDITY_MS);
    assert.ok(saved.deleteAt, "TTL");
    assert.ok(!/token|authorization|bearer/i.test(JSON.stringify(saved)));
  });

  it("pedido íntegro é aceito com dados só do recibo", async () => {
    const db = makeDb(productDocs());
    const { quoteIds } = await issue(db);
    const res = await validate(db, order(quoteIds.get(1)));
    assert.equal(res.ok, true);
    assert.equal(res.quote.quotedPrice, 15);
    assert.equal(res.quote.chargedPrice, 15);
    assert.equal(res.quote.serviceName, "SEDEX");
    assert.deepEqual(res.quote.providerPackage, { weight: 0.55, height: 20, width: 30, length: 40 });
  });

  const cases = [
    ["sem shippingQuoteId", (id) => order(undefined), SHIPPING_QUOTE_ERROR.MISSING],
    ["ID forjado", () => order("0".repeat(32) + ".1"), SHIPPING_QUOTE_ERROR.NOT_FOUND],
    ["preço adulterado", (id) => order(id, { frete: { ...order(id).frete, valor: 5 }, total: 155 }), SHIPPING_QUOTE_ERROR.PRICE_MISMATCH],
    ["preço acima do cotado", (id) => order(id, { frete: { ...order(id).frete, valor: 20 }, total: 170 }), SHIPPING_QUOTE_ERROR.PRICE_MISMATCH],
    ["troca de serviço", (id) => order(id, { frete: { ...order(id).frete, service_id: 3 } }), SHIPPING_QUOTE_ERROR.SERVICE_MISMATCH],
    ["opção de outro serviço do mesmo recibo", (id) => order(id.replace(/\.1$/, ".0")), SHIPPING_QUOTE_ERROR.SERVICE_MISMATCH],
    ["outro CEP", (id) => order(id, { cliente: { ...order(id).cliente, endereco: { cep: "01001000" } } }), SHIPPING_QUOTE_ERROR.DESTINATION_MISMATCH],
    ["itens alterados (peso/pacote)", (id) => order(id, { itens: [{ productId: "p1", quantidade: 5, precoUnitario: 30 }] }), SHIPPING_QUOTE_ERROR.ITEMS_MISMATCH],
    ["seguro menor que o subtotal", (id) => order(id, { subtotal: 300, total: 315 }), SHIPPING_QUOTE_ERROR.INSURANCE_MISMATCH],
    ["total inconsistente sem desconto", (id) => order(id, { total: 100 }), SHIPPING_QUOTE_ERROR.TOTAL_INCONSISTENT],
    ["total acima do esperado", (id) => order(id, { total: 200 }), SHIPPING_QUOTE_ERROR.TOTAL_INCONSISTENT],
  ];
  for (const [name, build, code] of cases) {
    it(`rejeita: ${name}`, async () => {
      const db = makeDb(productDocs());
      const { quoteIds } = await issue(db);
      const res = await validate(db, build(quoteIds.get(1)));
      assert.equal(res.ok, false);
      assert.equal(res.code, code);
    });
  }

  it("peso/dimensões enviados pelo cliente no pedido são ignorados", async () => {
    const db = makeDb(productDocs());
    const { quoteIds } = await issue(db);
    const o = order(quoteIds.get(1));
    o.frete.cotacao = { pacote: { pesoGramas: 30000, alturaCm: 1, larguraCm: 1, comprimentoCm: 1 } };
    o.frete.peso = 1;
    const res = await validate(db, o);
    assert.deepEqual(res.quote.providerPackage, { weight: 0.55, height: 20, width: 30, length: 40 });
  });

  it("expirado: pedido criado após a validade (createTime do servidor)", async () => {
    const db = makeDb(productDocs());
    const { quoteIds } = await issue(db);
    const res = await validate(db, order(quoteIds.get(1)), { createdMs: NOW + SHIPPING_QUOTE_VALIDITY_MS + 1 });
    assert.equal(res.code, SHIPPING_QUOTE_ERROR.EXPIRED);
    const sem = await validate(db, order(quoteIds.get(1)), { createdMs: NaN });
    assert.equal(sem.code, SHIPPING_QUOTE_ERROR.EXPIRED);
  });

  it("outra loja: recibo de B não vale em A; recibo copiado com storeId de B é recusado", async () => {
    const db = makeDb({ ...productDocs(), ...productDocs(STORE_B) });
    const { receiptId, quoteIds } = await issue(db, { storeId: STORE_B });
    const notFound = await validate(db, order(quoteIds.get(1)));
    assert.equal(notFound.code, SHIPPING_QUOTE_ERROR.NOT_FOUND);
    db.docs.set(`lojas/${STORE_A}/shipping_quotes/${receiptId}`, db.docs.get(`lojas/${STORE_B}/shipping_quotes/${receiptId}`));
    const mismatch = await validate(db, order(quoteIds.get(1)));
    assert.equal(mismatch.code, SHIPPING_QUOTE_ERROR.STORE_MISMATCH);
  });

  it("desconto de frete só com cupom de frete/frete grátis; desconto no total só com cupom", async () => {
    const db = makeDb(productDocs());
    const { quoteIds } = await issue(db);
    const id = quoteIds.get(1);
    const cupomFrete = order(id, { frete: { ...order(id).frete, valor: 5 }, total: 155, cupomFrete: { codigo: "FRETE10" } });
    assert.equal((await validate(db, cupomFrete)).ok, true);
    const gratis = order(id, { frete: { ...order(id).frete, valor: 0, gratis: true }, total: 150 });
    assert.equal((await validate(db, gratis)).ok, true);
    const cupom = order(id, { total: 150, cupom: { codigo: "DEZ", desconto: 15 } });
    assert.equal((await validate(db, cupom)).ok, true);
  });

  it("pagamento: frete manual não exige recibo; provedor exige", async () => {
    const db = makeDb(productDocs());
    const manual = await validateOrderShippingForPayment({
      db, collectionLojas: "lojas", storeId: STORE_A, orderCreateTimeMs: NOW,
      order: { frete: { tipo: "retirada", plataforma: "manual", valor: 0 } },
    });
    assert.deepEqual(manual, { ok: true, required: false });
    const disfarçado = await validateOrderShippingForPayment({
      db, collectionLojas: "lojas", storeId: STORE_A, orderCreateTimeMs: NOW,
      order: { frete: { tipo: "melhor_envio", plataforma: "manual", valor: 1 } },
    });
    assert.equal(disfarçado.ok, false, "tipo do provedor com plataforma trocada ainda exige recibo");
    assert.equal(disfarçado.code, SHIPPING_QUOTE_ERROR.MISSING);
  });
});

describe("integração com os callables de cotação", () => {
  it("superFreteQuote com itens: ignora peso/dimensões do cliente e devolve shippingQuoteId", async () => {
    const db = makeDb({
      ...productDocs(),
      [`lojas/${STORE_A}/config/fretes_secrets`]: { superfrete: { token: "sf_token_abcdefghijklmnop", sandbox: true } },
    });
    let sentPackage = null;
    let sentFrom = null;
    const fetchImpl = async (url, opts) => {
      assert.ok(String(url).includes(SUPERFRETE_QUOTE_PATH));
      const body = JSON.parse(opts.body);
      sentPackage = body.package;
      sentFrom = body.from.postal_code;
      return {
        status: 200,
        ok: true,
        text: async () => JSON.stringify([
          { id: 1, name: "PAC", price: 12.5, delivery_time: 5, company: { name: "Correios" } },
          { id: 2, name: "SEDEX", price: 0, company: { name: "Correios" } },
        ]),
      };
    };
    const h = createSuperFreteHandlers({
      db,
      canManageStoreConfigServerSide: async () => false,
      checkRateLimit: async () => {},
      getCallableIdentifier: () => "anon",
      fetchWithTimeout: fetchImpl,
      collectionLojas: "lojas",
      request: {
        auth: null,
        data: {
          lojaId: STORE_A, destinationCep: "20040020", cepOrigem: "99999999",
          peso: 1, altura: 1, largura: 1, comprimento: 1, valorDeclarado: 150,
          items: [{ productId: "p1", quantidade: 2 }, { productId: "p2", quantidade: 1 }],
        },
      },
      overrides: { fetchWithTimeout: fetchImpl },
    });
    const res = await h.superFreteQuote();
    assert.equal(res.sucesso, true);
    assert.deepEqual(sentPackage, { height: 20, width: 30, length: 40, weight: 0.55 });
    assert.equal(sentFrom, "01310100", "origem da config da loja, não do cliente");
    const pac = res.opcoes.find((o) => o.nome === "PAC");
    const semPreco = res.opcoes.find((o) => o.nome === "SEDEX");
    assert.match(pac.shippingQuoteId, /^[a-f0-9]{32}\.0$/);
    assert.equal(semPreco.shippingQuoteId, undefined, "opção sem preço não recebe ID");
    const receiptId = parseShippingQuoteId(pac.shippingQuoteId).receiptId;
    const saved = db.docs.get(`lojas/${STORE_A}/shipping_quotes/${receiptId}`);
    assert.equal(saved.provider, "superfrete");
    assert.deepEqual(saved.providerPackage, sentPackage);
    assert.equal(saved.insuranceValue, 150);
  });

  it("calcularMelhorEnvio emite recibo com pacote do servidor; mpCatalogPayment valida antes de cobrar", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const me = src.slice(src.indexOf("export const calcularMelhorEnvio"), src.indexOf("export const testarMelhorEnvioToken"));
    assert.match(me, /computeCanonicalPackage\(/);
    assert.match(me, /package: quoted \? quoted\.providerPackage/);
    assert.match(me, /issueShippingQuoteReceipt\(/);
    const pay = src.slice(src.indexOf("export const mpCatalogPayment"));
    const check = pay.indexOf("validateOrderShippingForPayment(");
    assert.ok(check > 0);
    assert.ok(check < pay.indexOf("api.mercadopago.com"), "validação antes de chamar o MP");
  });

  it("rules: recibos fechados ao cliente; criação pública sem estado de envio", () => {
    const rules = readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8");
    assert.match(rules, /match \/shipping_quotes\/\{receiptId\} \{\s*allow read, write: if false;/);
    assert.match(rules, /!request\.resource\.data\.keys\(\)\.hasAny\(\['shipping', 'shippingPreOrder'\]\)/);
  });
});
