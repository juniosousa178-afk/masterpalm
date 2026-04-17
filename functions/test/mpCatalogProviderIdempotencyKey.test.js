/**
 * Idempotência determinística do provedor (Mercado Pago) — fluxo catálogo.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { buildMpCatalogProviderIdempotencyKey } from "../src/mpCatalogProviderIdempotencyKey.js";

describe("buildMpCatalogProviderIdempotencyKey", () => {
  it("mesma entrada lojaId/orderId/type → mesma chave (retry seguro)", () => {
    const a = buildMpCatalogProviderIdempotencyKey("L1", "pedido-1", "pix");
    const b = buildMpCatalogProviderIdempotencyKey("L1", "pedido-1", "pix");
    assert.equal(a, b);
    assert.equal(a.length, 64);
    assert.match(a, /^[a-f0-9]{64}$/);
  });

  it("entradas diferentes → chaves diferentes", () => {
    const pix = buildMpCatalogProviderIdempotencyKey("L1", "pedido-1", "pix");
    const pref = buildMpCatalogProviderIdempotencyKey("L1", "pedido-1", "preference");
    const otherOrder = buildMpCatalogProviderIdempotencyKey("L1", "pedido-2", "pix");
    assert.notEqual(pix, pref);
    assert.notEqual(pix, otherOrder);
  });

  it("normaliza type em minúsculas para estabilidade", () => {
    assert.equal(
      buildMpCatalogProviderIdempotencyKey("a", "b", "PIX"),
      buildMpCatalogProviderIdempotencyKey("a", "b", "pix"),
    );
  });

  it("não depende de timestamp (formato fixo hex 64)", () => {
    const k = buildMpCatalogProviderIdempotencyKey("loja", "ord", "preference");
    assert.equal(k.length, 64);
  });
});
