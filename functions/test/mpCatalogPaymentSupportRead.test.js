/**
 * Forense suporte catálogo MP — helpers puros (sem Firestore).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  buildMpCatalogIdempotencyDocId,
  sanitizePaymentsAuditDoc,
  sanitizeWebhookValidationRejectDoc,
  buildSupportTimeline,
  deriveSupportIndicators,
} from "../src/mpCatalogPaymentSupportRead.js";

describe("buildMpCatalogIdempotencyDocId", () => {
  it("mesmo lojaId+orderId+type gera mesmo doc id", () => {
    const a = buildMpCatalogIdempotencyDocId("L1", "O1", "pix");
    const b = buildMpCatalogIdempotencyDocId("L1", "O1", "pix");
    assert.equal(a, b);
    assert.ok(a.startsWith("mpCatalogPayment:"));
  });

  it("pix vs preference diferem", () => {
    assert.notEqual(
      buildMpCatalogIdempotencyDocId("L", "O", "pix"),
      buildMpCatalogIdempotencyDocId("L", "O", "preference"),
    );
  });
});

describe("sanitizePaymentsAuditDoc", () => {
  it("remove raw do MP", () => {
    const o = sanitizePaymentsAuditDoc({
      kind: "payment",
      status: "approved",
      raw: { secret: "x", payer: { email: "a@b.com" } },
    });
    assert.equal(o.kind, "payment");
    assert.equal(o.raw, undefined);
    assert.equal(o.status, "approved");
  });
});

describe("buildSupportTimeline", () => {
  it("ordena por atMs crescente", () => {
    const t = buildSupportTimeline([
      { event: "b", atMs: 200 },
      { event: "a", atMs: 100 },
      { event: "c", atMs: 150 },
    ]);
    assert.deepEqual(t.map((x) => x.event), ["a", "c", "b"]);
  });

  it("ignora entradas sem atMs", () => {
    const t = buildSupportTimeline([{ event: "a", atMs: null }, { event: "b", atMs: 50 }]);
    assert.equal(t.length, 1);
    assert.equal(t[0].event, "b");
  });
});

describe("deriveSupportIndicators", () => {
  const mockSnap = (data) => ({
    exists: true,
    data: () => data,
  });
  const emptySnap = { exists: false, data: () => null };

  it("hasProviderSuccess quando há result em idempotência", () => {
    const ind = deriveSupportIndicators({
      idemPixSnap: mockSnap({
        result: { id: "123" },
        createdAt: { toMillis: () => 1 },
      }),
      idemPrefSnap: emptySnap,
      webhookProcSnap: emptySnap,
      validationRejectSnap: emptySnap,
      order: {},
      paymentsAuditSanitized: null,
    });
    assert.equal(ind.hasProviderSuccess, true);
    assert.equal(ind.hasPersistSuccess, true);
  });

  it("hasWebhookProcessed quando doc existe", () => {
    const ind = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: mockSnap({ status: "done", processedAt: {} }),
      validationRejectSnap: emptySnap,
      order: {},
      paymentsAuditSanitized: { status: "approved" },
    });
    assert.equal(ind.hasWebhookProcessed, true);
    assert.equal(ind.hasWebhookApproved, true);
    assert.equal(ind.hasMaterialNewEffect, true);
    assert.equal(ind.webhookProcessedOutcome, "done");
  });

  it("hasValidationFailure quando há rejeição e webhook ainda não concluiu", () => {
    const ind = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: emptySnap,
      validationRejectSnap: mockSnap({ validationReason: "amount_mismatch" }),
      order: {},
      paymentsAuditSanitized: null,
    });
    assert.equal(ind.hasValidationFailure, true);
    assert.equal(ind.validationFailureReason, "amount_mismatch");
    assert.equal(ind.validationRejectSuperseded, false);
  });

  it("rejeição fica superseded quando _mp_webhook_processed já concluiu", () => {
    const ind = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: mockSnap({ status: "done", effectiveOutcome: "applied_order_paid_new_effect" }),
      validationRejectSnap: mockSnap({ validationReason: "amount_mismatch" }),
      order: { paidAt: {} },
      paymentsAuditSanitized: { status: "approved" },
    });
    assert.equal(ind.hasValidationFailure, false);
    assert.equal(ind.validationRejectSuperseded, true);
  });

  it("noop já pago vs efeito novo", () => {
    const noop = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: mockSnap({
        status: "already_paid",
        effectiveOutcome: "noop_order_already_paid",
      }),
      validationRejectSnap: emptySnap,
      order: { paidAt: {} },
      paymentsAuditSanitized: null,
    });
    assert.equal(noop.hasNoopAlreadyPaid, true);
    assert.equal(noop.hasMaterialNewEffect, false);

    const applied = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: mockSnap({
        status: "done",
        effectiveOutcome: "applied_order_paid_new_effect",
      }),
      validationRejectSnap: emptySnap,
      order: {},
      paymentsAuditSanitized: null,
    });
    assert.equal(applied.hasMaterialNewEffect, true);
    assert.equal(applied.hasNoopAlreadyPaid, false);
    assert.equal(applied.webhookProcessedOutcome, "applied_order_paid_new_effect");
  });

  it("reenvio de webhook após processado", () => {
    const ind = deriveSupportIndicators({
      idemPixSnap: emptySnap,
      idemPrefSnap: emptySnap,
      webhookProcSnap: mockSnap({
        status: "done",
        lastDuplicateWebhookAt: { toMillis: () => 999 },
      }),
      validationRejectSnap: emptySnap,
      order: {},
      paymentsAuditSanitized: null,
    });
    assert.equal(ind.hasWebhookRedeliveryIgnored, true);
    assert.equal(ind.hasDuplicateIgnored, true);
  });
});

describe("sanitizeWebhookValidationRejectDoc", () => {
  it("remove campos fora da lista permitida", () => {
    const o = sanitizeWebhookValidationRejectDoc({
      validationReason: "x",
      raw: { a: 1 },
      payerEmail: "secret@x.com",
    });
    assert.equal(o.validationReason, "x");
    assert.equal(o.raw, undefined);
    assert.equal(o.payerEmail, undefined);
  });
});
