/**
 * Blindagem P1 — catálogo MP (strip público, idempotência curta, pedido não pagável).
 * node --test (Node 20+)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { stripPaymentsSecretsForPublic } from "../src/paymentsPublicStrip.js";
import { getIdempotencyTtlMs } from "../src/rateLimiter.js";
import { isOrderPayableForMp } from "../src/catalogMpOrderHelpers.js";

describe("stripPaymentsSecretsForPublic", () => {
  it("não copia access_token nem refresh_token do MP", () => {
    const raw = {
      mp: {
        access_token: "APP_USR-secret",
        token: "dup",
        refresh_token: "r",
        public_key: "pk",
        connected: true,
      },
      pagseguro: { token: "ps" },
    };
    const out = stripPaymentsSecretsForPublic(raw);
    assert.equal(out.mp?.access_token, undefined);
    assert.equal(out.mp?.token, undefined);
    assert.equal(out.mp?.refresh_token, undefined);
    assert.equal(out.mp?.public_key, "pk");
    assert.equal(out.pagseguro?.token, undefined);
  });

  it("não vaza segredos de outros gateways", () => {
    const out = stripPaymentsSecretsForPublic({
      ton: { client_secret: "x", client_id: "c" },
      infinitpay: { api_key: "k", merchantId: "m" },
    });
    assert.equal(out.ton?.client_secret, undefined);
    assert.equal(out.infinitpay?.api_key, undefined);
  });
});

describe("getIdempotencyTtlMs (mpCatalogPayment)", () => {
  it("TTL curto para mpCatalogPayment (10 min)", () => {
    assert.equal(getIdempotencyTtlMs("mpCatalogPayment"), 10 * 60 * 1000);
  });

  it("TTL padrão 24h para outros endpoints", () => {
    assert.equal(getIdempotencyTtlMs("createPreference"), 24 * 60 * 60 * 1000);
  });
});

describe("isOrderPayableForMp", () => {
  it("pedido já pago não gera nova cobrança", () => {
    assert.equal(
      isOrderPayableForMp({ total: 10, paidAt: "2024-01-01", status: "pendente" }),
      false,
    );
  });

  it("pedido cancelado não é pagável", () => {
    assert.equal(isOrderPayableForMp({ total: 10, status: "cancelado" }), false);
  });

  it("pedido pendente com total válido é pagável", () => {
    assert.equal(isOrderPayableForMp({ total: 99.9, status: "pendente" }), true);
  });
});
