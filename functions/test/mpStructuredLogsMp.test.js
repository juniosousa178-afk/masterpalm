/**
 * Observabilidade MP — formato JSON e ausência de campos sensíveis óbvios.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  emitCatalogPaymentLog,
  emitWebhookLog,
  catalogPaymentCorrelationId,
  truncateProviderErrorText,
} from "../src/mpStructuredLogsMp.js";

function captureConsole(fn) {
  const lines = { log: [], warn: [], error: [] };
  const origLog = console.log;
  const origWarn = console.warn;
  const origErr = console.error;
  console.log = (...a) => lines.log.push(a.join(" "));
  console.warn = (...a) => lines.warn.push(a.join(" "));
  console.error = (...a) => lines.error.push(a.join(" "));
  try {
    fn();
  } finally {
    console.log = origLog;
    console.warn = origWarn;
    console.error = origErr;
  }
  return lines;
}

function parseFirst(lines) {
  const raw = lines.error[0] || lines.warn[0] || lines.log[0];
  assert.ok(raw, "expected one log line");
  return JSON.parse(raw);
}

const SENSITIVE_KEYS = new Set([
  "access_token",
  "refresh_token",
  "authorization",
  "password",
  "cpf",
  "email",
  "token",
]);

function assertNoSensitiveKeys(obj, path = "") {
  if (obj == null || typeof obj !== "object") return;
  for (const k of Object.keys(obj)) {
    const p = path ? `${path}.${k}` : k;
    assert.ok(!SENSITIVE_KEYS.has(k.toLowerCase()), `unexpected key: ${p}`);
    assertNoSensitiveKeys(obj[k], p);
  }
}

describe("catalogPaymentCorrelationId", () => {
  it("correlação estável por lojaId/orderId/type", () => {
    const a = catalogPaymentCorrelationId("L", "O1", "pix");
    const b = catalogPaymentCorrelationId("L", "O1", "pix");
    assert.equal(a, b);
    assert.equal(a.length, 12);
  });
});

describe("truncateProviderErrorText", () => {
  it("trunca respostas longas do provedor", () => {
    const long = "x".repeat(400);
    assert.ok(truncateProviderErrorText(long).length < long.length);
  });
});

describe("emitCatalogPaymentLog — eventos críticos", () => {
  it("payload mínimo mpCatalogPayment_provider_success", () => {
    const lines = captureConsole(() =>
      emitCatalogPaymentLog({
        event: "mpCatalogPayment_provider_success",
        severity: "info",
        outcome: "success",
        lojaId: "loja1",
        orderId: "ped1",
        type: "pix",
        externalReference: "ped1",
        correlationId: "abc123def456",
        providerPaymentId: "12345",
      }),
    );
    const o = parseFirst(lines);
    assert.equal(o.service, "mpCatalogPayment");
    assert.equal(o.provider, "mercadopago");
    assert.equal(o.event, "mpCatalogPayment_provider_success");
    assert.equal(o.lojaId, "loja1");
    assert.equal(o.orderId, "ped1");
    assertNoSensitiveKeys(o);
  });

  it("payload mínimo mpCatalogPayment_persist_error", () => {
    const lines = captureConsole(() =>
      emitCatalogPaymentLog({
        event: "mpCatalogPayment_persist_error",
        severity: "error",
        outcome: "persist_fail",
        lojaId: "loja1",
        orderId: "ped1",
        type: "pix",
        err: "Firestore timeout",
      }),
    );
    const o = parseFirst(lines);
    assert.equal(o.event, "mpCatalogPayment_persist_error");
    assert.equal(lines.error.length, 1);
    assertNoSensitiveKeys(o);
  });
});

describe("emitWebhookLog — eventos críticos", () => {
  it("payload mínimo mpWebhook_received", () => {
    const lines = captureConsole(() =>
      emitWebhookLog({
        event: "mpWebhook_received",
        severity: "info",
        paymentId: "pay1",
        paymentStatus: "approved",
        externalReference: "ord1",
      }),
    );
    const o = parseFirst(lines);
    assert.equal(o.service, "mpWebhook");
    assert.equal(o.provider, "mercadopago");
    assert.equal(o.event, "mpWebhook_received");
    assert.equal(o.paymentId, "pay1");
    assertNoSensitiveKeys(o);
  });

  it("payload mínimo mpWebhook_payment_validation_failed com centavos", () => {
    const lines = captureConsole(() =>
      emitWebhookLog({
        event: "mpWebhook_payment_validation_failed",
        severity: "error",
        reason: "amount_mismatch",
        paymentId: "p1",
        orderId: "o1",
        lojaId: "l1",
        amountExpectedCents: 1000,
        amountReceivedCents: 999,
      }),
    );
    const o = parseFirst(lines);
    assert.equal(o.event, "mpWebhook_payment_validation_failed");
    assert.equal(o.amountExpectedCents, 1000);
    assert.equal(lines.error.length, 1);
    assertNoSensitiveKeys(o);
  });
});
