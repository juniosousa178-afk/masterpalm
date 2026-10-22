/**
 * Borda mpWebhook catálogo: HMAC exclusivo com MP_WEBHOOK_CATALOG_SECRET (sem fallback de plataforma).
 * node --test test/mpWebhookCatalogSecret.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  verifyMpCatalogWebhookNotificationCatalogSecret,
  pickMpCatalogWebhookSecret,
  MP_WEBHOOK_CATALOG_PLATFORM_SECRET_FALLBACK_ALLOWED,
  MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS,
} from "../src/mpWebhookCatalogEdge.js";
import {
  validateMercadoPagoWebhookSignature,
  extractMercadoPagoWebhookDataId,
  extractMercadoPagoCatalogWebhookDataId,
  buildMercadoPagoWebhookSignatureLogContext,
} from "../src/mercadoPagoWebhookSignature.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const CATALOG_SECRET = "unit-catalog-secret";
const PLATFORM_SECRET = "unit-platform-secret";

function signedReq({ secret, paymentId = "1330000001", requestId = "rid-1", query, body } = {}) {
  const ts = String(Math.floor(Date.now() / 1000));
  const manifest = `id:${paymentId};request-id:${requestId};ts:${ts};`;
  const v1 = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  return {
    query: query ?? { "data.id": paymentId, type: "payment" },
    body: body ?? {},
    headers: { "x-signature": `ts=${ts},v1=${v1}`, "x-request-id": requestId },
  };
}

describe("mpWebhook catálogo — secret exclusivo", () => {
  it("fallback de plataforma desabilitado por contrato", () => {
    assert.equal(MP_WEBHOOK_CATALOG_PLATFORM_SECRET_FALLBACK_ALLOWED, false);
    assert.equal(pickMpCatalogWebhookSecret({ catalogSecret: "", platformSecret: PLATFORM_SECRET }).secretSlot, "none");
  });

  it("assinatura com secret de catálogo: aceita, dataId = id do manifest", () => {
    const r = verifyMpCatalogWebhookNotificationCatalogSecret(signedReq({ secret: CATALOG_SECRET }), {
      catalogSecret: CATALOG_SECRET,
    });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, "1330000001");
    assert.equal(r.secretSlot, "catalog_secret");
  });

  it("assinatura com secret de plataforma: rejeitada (hmac_mismatch)", () => {
    const r = verifyMpCatalogWebhookNotificationCatalogSecret(signedReq({ secret: PLATFORM_SECRET }), {
      catalogSecret: CATALOG_SECRET,
    });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "hmac_mismatch");
  });

  it("secret de catálogo ausente: fail closed mesmo com assinatura de plataforma válida", () => {
    const r = verifyMpCatalogWebhookNotificationCatalogSecret(signedReq({ secret: PLATFORM_SECRET }), {
      catalogSecret: "",
    });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "secret_missing");
    assert.equal(r.secretSlot, "none");
  });

  it("assinatura inválida / ausente / malformada / ts antigo → não ok", () => {
    const bad = signedReq({ secret: CATALOG_SECRET });
    bad.headers["x-signature"] = bad.headers["x-signature"].replace(/v1=[0-9a-f]{64}/, `v1=${"0".repeat(64)}`);
    assert.equal(verifyMpCatalogWebhookNotificationCatalogSecret(bad, { catalogSecret: CATALOG_SECRET }).reason, "hmac_mismatch");

    const missing = { query: { "data.id": "1" }, body: {}, headers: {} };
    assert.equal(verifyMpCatalogWebhookNotificationCatalogSecret(missing, { catalogSecret: CATALOG_SECRET }).reason, "header_missing");

    const malformed = { query: { "data.id": "1" }, body: {}, headers: { "x-signature": "garbage" } };
    assert.equal(verifyMpCatalogWebhookNotificationCatalogSecret(malformed, { catalogSecret: CATALOG_SECRET }).reason, "header_malformed");

    const notHex = { query: { "data.id": "1" }, body: {}, headers: { "x-signature": `ts=${Math.floor(Date.now() / 1000)},v1=zz` } };
    assert.equal(verifyMpCatalogWebhookNotificationCatalogSecret(notHex, { catalogSecret: CATALOG_SECRET }).reason, "v1_not_hex");

    const old = { query: { "data.id": "1" }, body: {}, headers: { "x-signature": `ts=1000,v1=${"a".repeat(64)}` } };
    assert.equal(verifyMpCatalogWebhookNotificationCatalogSecret(old, { catalogSecret: CATALOG_SECRET }).reason, "ts_out_of_range");
  });

  it("formato legado ?id=&topic=payment: id do manifest extraído da query", () => {
    const req = signedReq({ secret: CATALOG_SECRET, query: { id: "1330000001", topic: "payment" } });
    const r = verifyMpCatalogWebhookNotificationCatalogSecret(req, { catalogSecret: CATALOG_SECRET });
    assert.equal(r.ok, true);
    assert.equal(r.dataId, "1330000001");
    assert.equal(buildMercadoPagoWebhookSignatureLogContext(req).notificationFormat, "query_id_topic");
  });

  it("log de assinatura não contém secret nem assinatura", () => {
    const req = signedReq({ secret: CATALOG_SECRET });
    const ctx = JSON.stringify(buildMercadoPagoWebhookSignatureLogContext(req));
    assert.doesNotMatch(ctx, new RegExp(CATALOG_SECRET));
    assert.doesNotMatch(ctx, /v1=/);
  });
});

describe("planWebhook — extração padrão inalterada", () => {
  it("default ignora query.id (contrato anterior); catálogo aceita", () => {
    const req = { query: { id: "77", topic: "payment" }, body: {} };
    assert.equal(extractMercadoPagoWebhookDataId(req), "");
    assert.equal(extractMercadoPagoCatalogWebhookDataId(req), "77");
  });

  it("validateMercadoPagoWebhookSignature sem extractor usa a extração padrão", () => {
    const req = signedReq({ secret: PLATFORM_SECRET, query: { id: "1330000001", topic: "payment" } });
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: PLATFORM_SECRET });
    assert.equal(r.ok, false);
  });
});

describe("index.js — binding e ordem na borda mpWebhook", () => {
  const src = readFileSync(join(HERE, "../index.js"), "utf8");
  const start = src.indexOf("export const mpWebhook = onRequest(");
  const block = src.slice(start, src.indexOf("\n);\n", start));

  it("mpWebhook vincula MP_WEBHOOK_CATALOG_SECRET e não MP_WEBHOOK_SECRET", () => {
    assert.match(src, /S_MP_WEBHOOK_CATALOG_SECRET = defineSecret\("MP_WEBHOOK_CATALOG_SECRET"\)/);
    assert.match(block, /secrets: \[[^\]]*S_MP_WEBHOOK_CATALOG_SECRET[^\]]*\]/);
    assert.doesNotMatch(block, /S_MP_WEBHOOK_SECRET\b/);
    assert.doesNotMatch(block, /process\.env\.MP_WEBHOOK_SECRET/);
  });

  it("401 antes de processMpWebhook; handler recebe o dataId assinado", () => {
    const iSig = block.indexOf("verifyMpCatalogWebhookNotificationCatalogSecret(");
    const i401 = block.indexOf("MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS");
    const iProc = block.indexOf("processMpWebhook(");
    assert.ok(iSig > 0 && i401 > iSig && iProc > i401);
    assert.match(block, /processMpWebhook\(sig\.dataId,/);
    assert.equal(MP_WEBHOOK_CATALOG_SIGNATURE_HTTP_STATUS, 401);
  });

  it("planWebhook continua com MP_WEBHOOK_SECRET", () => {
    const p = src.indexOf("export const planWebhook");
    assert.ok(p > 0);
    assert.match(src.slice(p, p + 600), /S_MP_WEBHOOK_SECRET/);
  });
});
