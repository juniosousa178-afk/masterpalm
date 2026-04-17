/**
 * Borda mpWebhook (catálogo): HMAC x-signature + códigos HTTP exportados.
 * Não exercita processMpWebhook (lógica interna intocada).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";

import {
  verifyMpCatalogWebhookNotification,
  MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS,
  MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS,
} from "../src/mpWebhookCatalogEdge.js";

function buildValidCatalogWebhookReq({ paymentId, secret, requestId = "req-catalog-1" }) {
  const ts = String(Math.floor(Date.now() / 1000));
  const dataId = String(paymentId);
  const idNorm = /^[a-f0-9]+$/i.test(dataId) ? dataId.toLowerCase() : dataId;
  const manifest = `id:${idNorm};request-id:${requestId};ts:${ts};`;
  const v1 = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  const xSignature = `ts=${ts},v1=${v1}`;
  return {
    query: { "data.id": dataId },
    body: {},
    headers: {
      "x-signature": xSignature,
      "x-request-id": requestId,
    },
  };
}

describe("mpWebhookCatalogEdge / verifyMpCatalogWebhookNotification", () => {
  it("assinatura válida permite seguir (ok: true)", () => {
    const secret = "unit-test-mp-webhook-catalog-secret";
    const req = buildValidCatalogWebhookReq({ paymentId: "pay_catalog_99", secret });
    const r = verifyMpCatalogWebhookNotification(req, secret);
    assert.equal(r.ok, true);
  });

  it("assinatura inválida bloqueia (hmac_mismatch)", () => {
    const secret = "unit-test-mp-webhook-catalog-secret";
    const req = buildValidCatalogWebhookReq({ paymentId: "pay1", secret });
    req.headers["x-signature"] = req.headers["x-signature"].replace(
      /v1=[0-9a-f]{64}/i,
      `v1=${"a".repeat(64)}`,
    );
    const r = verifyMpCatalogWebhookNotification(req, secret);
    assert.equal(r.ok, false);
    assert.equal(r.reason, "hmac_mismatch");
  });

  it("sem x-signature: header_missing", () => {
    const req = { query: { "data.id": "x" }, body: {}, headers: {} };
    const r = verifyMpCatalogWebhookNotification(req, "any-secret");
    assert.equal(r.ok, false);
    assert.equal(r.reason, "header_missing");
  });

  it("secret vazio: secret_missing", () => {
    const req = buildValidCatalogWebhookReq({ paymentId: "p2", secret: "s" });
    const r = verifyMpCatalogWebhookNotification(req, "   ");
    assert.equal(r.ok, false);
    assert.equal(r.reason, "secret_missing");
  });

  it("POST body data.id alinhado ao manifest", () => {
    const secret = "sec-body";
    const paymentId = "12345678";
    const ts = String(Math.floor(Date.now() / 1000));
    const requestId = "rid-2";
    const manifest = `id:${paymentId};request-id:${requestId};ts:${ts};`;
    const v1 = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
    const req = {
      query: {},
      body: { data: { id: paymentId } },
      headers: {
        "x-signature": `ts=${ts},v1=${v1}`,
        "x-request-id": requestId,
      },
    };
    const r = verifyMpCatalogWebhookNotification(req, secret);
    assert.equal(r.ok, true);
  });
});

describe("mpWebhookCatalogEdge / constantes HTTP da borda", () => {
  it("401 assinatura; 500 falha transitória documentada", () => {
    assert.equal(MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS, 401);
    assert.equal(MP_WEBHOOK_CATALOG_PROCESSING_ERROR_HTTP_STATUS, 500);
  });
});
