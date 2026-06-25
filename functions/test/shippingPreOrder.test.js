/**
 * node --test test/shippingPreOrder.test.js
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { Timestamp } from "firebase-admin/firestore";

import {
  buildShippingPreOrderDocId,
  buildProviderReference,
  resolveShippingProviderFromOrder,
  shouldCreateExternalShippingPreOrder,
  validateOrderShippingEligibility,
  computeShippingPackage,
  pickEmbalagemFromConfig,
  processShippingPreOrder,
  isProcessingLeaseActive,
  PROCESSING_LEASE_MS,
  SHIPPING_PROVIDER,
  SHIPPING_PREORDER_STATUS,
  SHIPPING_ERROR_CODE,
} from "../src/shippingPreOrder.js";
import { detectLegacyMelhorEnvioToken } from "../src/melhorEnvioIntegration.js";

const LOJA = "loja-ship";
const ORDER = "pedido-abc";
const TOKEN_SF = "sf_test_token_abcdefghijklmnop";
const TOKEN_ME = "me_test_token_abcdefghijklmnop";
const PROVIDER_REF_ME = buildProviderReference(LOJA, ORDER, SHIPPING_PROVIDER.MELHOR_ENVIO);

function baseOrder(provider, extra = {}) {
  return {
    status: "pendente",
    total: 120,
    cliente: {
      nome: "Cliente Teste",
      email: "cliente@test.com",
      telefone: "11999999999",
      cpf: "12345678901",
      endereco: {
        cep: "01310100",
        rua: "Av Paulista",
        numero: "100",
        bairro: "Bela Vista",
        cidade: "São Paulo",
        estado: "SP",
      },
    },
    frete: {
      nome: "PAC",
      valor: 15,
      tipo: "pac",
      plataforma: provider,
      service_id: provider === SHIPPING_PROVIDER.SUPERFRETE ? 1 : 4,
      servico_id: provider === SHIPPING_PROVIDER.SUPERFRETE ? 1 : undefined,
    },
    itens: [
      {
        productId: "prod-1",
        quantidade: 1,
        peso: 500,
        total: 100,
      },
    ],
    ...extra,
  };
}

function makeMockDb({
  prePedidos = {},
  shippingPreorders = {},
  fretes = {},
  fretesSecrets = {},
  produtos = {},
} = {}) {
  const state = {
    prePedidos: structuredClone(prePedidos),
    shippingPreorders: structuredClone(shippingPreorders),
    fretes: structuredClone(fretes),
    fretesSecrets: structuredClone(fretesSecrets),
    produtos: structuredClone(produtos),
  };

  function pathRef(path) {
    return {
      path,
      async get() {
        const parts = path.split("/");
        if (parts.length >= 4 && parts[2] === "pre_pedidos") {
          const data = state.prePedidos[parts[3]];
          return { exists: !!data, data: () => data };
        }
        if (parts.length >= 4 && parts[2] === "shipping_preorders") {
          const data = state.shippingPreorders[parts[3]];
          return { exists: !!data, data: () => data };
        }
        if (parts.length >= 4 && parts[2] === "config" && parts[3] === "fretes") {
          const data = state.fretes[parts[1]];
          return { exists: !!data, data: () => data };
        }
        if (parts.length >= 4 && parts[2] === "config" && parts[3] === "fretes_secrets") {
          const data = state.fretesSecrets[parts[1]];
          return { exists: !!data, data: () => data };
        }
        if (parts.length >= 4 && parts[2] === "produtos") {
          const data = state.produtos[parts[3]];
          return { exists: !!data, data: () => data };
        }
        return { exists: false, data: () => undefined };
      },
      async set(data, opts = {}) {
        const parts = path.split("/");
        if (parts.length >= 4 && parts[2] === "pre_pedidos") {
          const id = parts[3];
          state.prePedidos[id] = opts.merge
            ? { ...(state.prePedidos[id] ?? {}), ...data }
            : structuredClone(data);
        } else if (parts.length >= 4 && parts[2] === "shipping_preorders") {
          const id = parts[3];
          state.shippingPreorders[id] = opts.merge
            ? { ...(state.shippingPreorders[id] ?? {}), ...data }
            : structuredClone(data);
        }
      },
      collection(name) {
        const parent = path;
        return {
          doc(id) {
            return pathRef(`${parent}/${name}/${id}`);
          },
        };
      },
    };
  }

  const db = {
    state,
    collection(name) {
      return {
        doc(id) {
          return pathRef(`${name}/${id}`);
        },
      };
    },
    async runTransaction(fn) {
      let wrote = false;
      const tx = {
        async get(ref) {
          if (wrote) {
            throw new Error(
              "Firestore transactions require all reads to be executed before all writes.",
            );
          }
          return ref.get();
        },
        set(ref, data, opts) {
          wrote = true;
          return ref.set(data, opts);
        },
      };
      return fn(tx);
    },
  };

  return db;
}

function okMelhorEnvioFetch({ reconcileHit = false } = {}) {
  return async (url, opts) => {
    const u = String(url);
    if (u.includes("/me/cart") && (!opts || opts.method === "GET")) {
      if (reconcileHit) {
        return {
          status: 200,
          ok: true,
          async text() {
            return JSON.stringify({
              current_page: 1,
              last_page: 1,
              data: [
                {
                  id: "me-cart-existing",
                  protocol: "ME-RECONCILE",
                  tags: [{ tag: PROVIDER_REF_ME }],
                },
              ],
            });
          },
        };
      }
      return {
        status: 200,
        ok: true,
        async text() {
          return JSON.stringify({ current_page: 1, last_page: 1, data: [] });
        },
      };
    }
    if (u.includes("/me/cart") && opts?.method === "POST") {
      return {
        status: 201,
        ok: true,
        async text() {
          return JSON.stringify({ id: "me-cart-1", protocol: "ME-PROTO-1" });
        },
      };
    }
    throw new Error(`unexpected url ${url}`);
  };
}

describe("shippingPreOrder helpers", () => {
  it("providerReference determinística", () => {
    assert.equal(
      buildProviderReference(LOJA, ORDER, SHIPPING_PROVIDER.MELHOR_ENVIO),
      `masterpalm:${LOJA}:${ORDER}:melhor_envio`,
    );
  });

  it("retirada e manual não criam carrinho", () => {
    assert.equal(
      shouldCreateExternalShippingPreOrder(
        baseOrder(SHIPPING_PROVIDER.SUPERFRETE, {
          frete: { plataforma: "manual", tipo: "manual" },
        }),
      ),
      false,
    );
  });

  it("produto sem peso gera needs_product_data", () => {
    const pkg = computeShippingPackage(
      baseOrder(SHIPPING_PROVIDER.SUPERFRETE, {
        itens: [{ productId: "x", quantidade: 1 }],
      }),
      pickEmbalagemFromConfig({ embalagens: [{ id: "padrao", peso: 50, altura: 10, largura: 20, comprimento: 30 }] }),
      { pesoTotalGrams: 0, missingWeight: true, maxTipoEmbalagem: "padrao" },
    );
    assert.equal(pkg.ok, false);
    assert.equal(pkg.code, SHIPPING_ERROR_CODE.PRODUCT_SHIPPING_DATA_MISSING);
  });

  it("lease ativa bloqueia reprocessamento", () => {
    const record = {
      status: SHIPPING_PREORDER_STATUS.PROCESSING,
      processingLeaseUntil: Timestamp.fromMillis(Date.now() + PROCESSING_LEASE_MS),
    };
    assert.equal(isProcessingLeaseActive(record), true);
  });
});

describe("processShippingPreOrder", () => {
  it("1. SuperFrete bloqueado sem reconciliação externa (NO-GO)", async () => {
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.SUPERFRETE) },
      fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN_SF } } },
      fretes: { [LOJA]: { cepOrigem: "01310100", embalagens: [] } },
    });
    let calls = 0;
    const fetchImpl = async () => {
      calls += 1;
      throw new Error("should not call");
    };
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.SUPERFRETE),
      fetchImpl,
    });
    assert.equal(res.ok, false);
    assert.equal(res.errorCode, SHIPPING_ERROR_CODE.EXTERNAL_RECONCILIATION_UNAVAILABLE);
    assert.equal(calls, 0);
  });

  it("2. Melhor Envio lê token somente de fretes_secrets", async () => {
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO) },
      fretesSecrets: { [LOJA]: { melhor_envio: { token: TOKEN_ME } } },
      fretes: {
        [LOJA]: {
          cepOrigem: "01310100",
          integrations: { melhor_envio: { configured: true } },
          embalagens: [{ id: "padrao", peso: 50, altura: 10, largura: 20, comprimento: 30 }],
        },
      },
    });
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO),
      fetchImpl: okMelhorEnvioFetch(),
    });
    assert.equal(res.ok, true);
    assert.equal(res.status, SHIPPING_PREORDER_STATUS.CREATED);
  });

  it("3. token legado público Melhor Envio retorna LEGACY_TOKEN_NEEDS_ROTATION", async () => {
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO) },
      fretes: {
        [LOJA]: {
          cepOrigem: "01310100",
          melhorEnvio: { token: "legacy_public" },
          embalagens: [],
        },
      },
    });
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO),
      fetchImpl: okMelhorEnvioFetch(),
    });
    assert.equal(res.ok, false);
    assert.equal(res.errorCode, SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION);
  });

  it("6. pedido repetido não cria dois carrinhos", async () => {
    const docId = buildShippingPreOrderDocId(SHIPPING_PROVIDER.MELHOR_ENVIO, ORDER);
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO) },
      shippingPreorders: {
        [docId]: {
          status: SHIPPING_PREORDER_STATUS.CREATED,
          providerCartId: "me-cart-existing",
        },
      },
      fretesSecrets: { [LOJA]: { melhor_envio: { token: TOKEN_ME } } },
      fretes: { [LOJA]: { cepOrigem: "01310100", embalagens: [] } },
    });
    let calls = 0;
    const fetchImpl = async (...args) => {
      calls += 1;
      return okMelhorEnvioFetch()(...args);
    };
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO),
      fetchImpl,
    });
    assert.equal(res.idempotent, true);
    assert.equal(calls, 0);
  });

  it("14. reconciliação externa evita segundo POST", async () => {
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO) },
      fretesSecrets: { [LOJA]: { melhor_envio: { token: TOKEN_ME } } },
      fretes: {
        [LOJA]: {
          cepOrigem: "01310100",
          embalagens: [{ id: "padrao", peso: 50, altura: 10, largura: 20, comprimento: 30 }],
        },
      },
    });
    let postCalls = 0;
    const fetchImpl = async (url, opts) => {
      if (String(url).includes("/me/cart") && opts?.method === "POST") {
        postCalls += 1;
      }
      return okMelhorEnvioFetch({ reconcileHit: true })(url, opts);
    };
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO),
      fetchImpl,
    });
    assert.equal(res.ok, true);
    assert.equal(res.reconciled, true);
    assert.equal(postCalls, 0);
    assert.equal(res.providerCartId, "me-cart-existing");
  });

  it("12. token não aparece em retorno", async () => {
    const db = makeMockDb({
      prePedidos: { [ORDER]: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO) },
      fretesSecrets: { [LOJA]: { melhor_envio: { token: TOKEN_ME } } },
      fretes: { [LOJA]: { cepOrigem: "01310100", embalagens: [] } },
    });
    const res = await processShippingPreOrder({
      db,
      collectionLojas: "lojas",
      lojaId: LOJA,
      orderId: ORDER,
      orderData: baseOrder(SHIPPING_PROVIDER.MELHOR_ENVIO),
      fetchImpl: okMelhorEnvioFetch(),
    });
    assert.ok(!JSON.stringify(res).includes(TOKEN_ME));
  });
});

describe("legacy detection", () => {
  it("detecta token legado Melhor Envio em config público", () => {
    assert.equal(
      detectLegacyMelhorEnvioToken({ melhorEnvio: { token: "x" } }, {}),
      true,
    );
  });
});
