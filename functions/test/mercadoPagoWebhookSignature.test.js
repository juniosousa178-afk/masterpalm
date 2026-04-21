/**
 * extractMercadoPagoWebhookDataId — prioridade query vs body (contrato MP).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { extractMercadoPagoWebhookDataId } from "../src/mercadoPagoWebhookSignature.js";

describe("extractMercadoPagoWebhookDataId", () => {
  it("prioriza query data.id sobre body", () => {
    const req = {
      query: { "data.id": "111" },
      body: { data: { id: "222" } },
    };
    assert.equal(extractMercadoPagoWebhookDataId(req), "111");
  });

  it("usa body.data.id quando query vazia", () => {
    const req = {
      query: {},
      body: { data: { id: "999888" } },
    };
    assert.equal(extractMercadoPagoWebhookDataId(req), "999888");
  });

  it("fallback body.id", () => {
    const req = { query: {}, body: { id: "77" } };
    assert.equal(extractMercadoPagoWebhookDataId(req), "77");
  });

  it("string vazia quando nada encontrado", () => {
    assert.equal(extractMercadoPagoWebhookDataId({ query: {}, body: {} }), "");
  });
});
