/**
 * mercadoPagoWebhookSignature — extração de data.id e validação HMAC.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";

import {
  extractMercadoPagoWebhookDataId,
  validateMercadoPagoWebhookSignature,
  detectMercadoPagoWebhookNotificationFormat,
  buildMercadoPagoWebhookSignatureLogContext,
} from "../src/mercadoPagoWebhookSignature.js";

const TEST_SECRET = "unit-test-mp-webhook-secret-value";

function buildSignedReq({
  paymentId,
  secret = TEST_SECRET,
  requestId = "req-test-1",
  query = {},
  body = {},
  headers = {},
}) {
  const ts = String(Math.floor(Date.now() / 1000));
  const dataId = String(paymentId);
  const idNorm = /^[a-f0-9]+$/i.test(dataId) ? dataId.toLowerCase() : dataId;
  const manifest = `id:${idNorm};request-id:${requestId};ts:${ts};`;
  const v1 = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  return {
    query,
    body,
    headers: {
      "x-signature": `ts=${ts},v1=${v1}`,
      "x-request-id": requestId,
      ...headers,
    },
  };
}

describe("extractMercadoPagoWebhookDataId", () => {
  it("prioriza query data.id sobre body", () => {
    const req = {
      query: { "data.id": "111" },
      body: { data: { id: "222" } },
    };
    assert.equal(extractMercadoPagoWebhookDataId(req), "111");
  });

  it("aceita query.id (legado id/topic)", () => {
    const req = { query: { id: "160781684883", topic: "payment" }, body: {} };
    assert.equal(extractMercadoPagoWebhookDataId(req), "160781684883");
  });

  it("aceita query.data.id aninhado", () => {
    const req = { query: { data: { id: "555444" } }, body: {} };
    assert.equal(extractMercadoPagoWebhookDataId(req), "555444");
  });

  it("prioriza query data.id sobre query.id", () => {
    const req = {
      query: { "data.id": "111", id: "222", type: "payment" },
      body: {},
    };
    assert.equal(extractMercadoPagoWebhookDataId(req), "111");
  });

  it("usa body.data.id quando query vazia", () => {
    const req = { query: {}, body: { data: { id: "999888" } } };
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

describe("detectMercadoPagoWebhookNotificationFormat", () => {
  it("identifica query_data_id_type", () => {
    const fmt = detectMercadoPagoWebhookNotificationFormat({
      query: { "data.id": "1", type: "payment" },
      body: {},
    });
    assert.equal(fmt, "query_data_id_type");
  });

  it("identifica query_id_topic", () => {
    const fmt = detectMercadoPagoWebhookNotificationFormat({
      query: { id: "1", topic: "payment" },
      body: {},
    });
    assert.equal(fmt, "query_id_topic");
  });

  it("identifica body_data_id e body_id", () => {
    assert.equal(
      detectMercadoPagoWebhookNotificationFormat({ query: {}, body: { data: { id: "9" } } }),
      "body_data_id",
    );
    assert.equal(
      detectMercadoPagoWebhookNotificationFormat({ query: {}, body: { id: "8" } }),
      "body_id",
    );
  });
});

describe("buildMercadoPagoWebhookSignatureLogContext", () => {
  it("não expõe secret nem assinatura completa", () => {
    const req = buildSignedReq({
      paymentId: "123",
      query: { id: "123", topic: "payment" },
    });
    const ctx = buildMercadoPagoWebhookSignatureLogContext(req);
    const serialized = JSON.stringify(ctx);
    assert.equal(ctx.notificationFormat, "query_id_topic");
    assert.equal(ctx.hasXSignature, true);
    assert.equal(ctx.extractedDataIdLen, 3);
    assert.equal(serialized.includes(TEST_SECRET), false);
    assert.equal(serialized.includes(req.headers["x-signature"]), false);
    assert.equal(Object.hasOwn(ctx, "webhookSecret"), false);
  });
});

describe("validateMercadoPagoWebhookSignature / HMAC", () => {
  it("valida HMAC com query data.id", () => {
    const paymentId = "161205115342";
    const req = buildSignedReq({
      paymentId,
      query: { "data.id": paymentId, type: "payment" },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, paymentId);
  });

  it("valida HMAC com query.id (legado)", () => {
    const paymentId = "160781684883";
    const req = buildSignedReq({
      paymentId,
      query: { id: paymentId, topic: "payment" },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, paymentId);
  });

  it("valida HMAC com query.data.id aninhado", () => {
    const paymentId = "99887766";
    const req = buildSignedReq({
      paymentId,
      query: { data: { id: paymentId } },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, paymentId);
  });

  it("valida HMAC com body.data.id", () => {
    const paymentId = "12345678";
    const req = buildSignedReq({
      paymentId,
      query: {},
      body: { data: { id: paymentId } },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, paymentId);
  });

  it("valida HMAC com body.id", () => {
    const paymentId = "55443322";
    const req = buildSignedReq({
      paymentId,
      query: {},
      body: { id: paymentId },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, paymentId);
  });

  it("rejeita hmac_mismatch", () => {
    const req = buildSignedReq({
      paymentId: "pay1",
      query: { "data.id": "pay1", type: "payment" },
    });
    req.headers["x-signature"] = req.headers["x-signature"].replace(
      /v1=[0-9a-f]{64}/i,
      `v1=${"a".repeat(64)}`,
    );
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "hmac_mismatch");
  });

  it("rejeita header ausente", () => {
    const req = { query: { "data.id": "x" }, body: {}, headers: {} };
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: TEST_SECRET });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "header_missing");
  });

  it("rejeita secret ausente", () => {
    const req = buildSignedReq({
      paymentId: "p2",
      query: { "data.id": "p2", type: "payment" },
    });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: "   " });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "secret_missing");
  });
});
