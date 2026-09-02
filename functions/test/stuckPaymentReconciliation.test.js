/**
 * node --test test/stuckPaymentReconciliation.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { Timestamp } from "firebase-admin/firestore";
import { normalizePlanId } from "../src/planEffectiveAccessResolver.js";
import { computePlanPeriodEnd } from "../src/planPeriod.js";
import {
  classifyStuckPayment,
  scanProcessingPayments,
  executeIdempotentReconciliation,
  planReconciliation,
  Classification,
  ReasonCode,
  ReconciliationOutcome,
  DEFAULT_MONITOR_OPTIONS,
} from "../src/stuckPaymentReconciliation/index.js";
import { createMemoryFirestore } from "./_memoryFirestore.js";

const norm = (p) => normalizePlanId(p);

function futureApproved(daysFromNow = 30) {
  const d = new Date();
  d.setDate(d.getDate() - 10);
  return d.toISOString();
}

function expiredApproved() {
  return "2026-04-20T15:20:07.000Z";
}

function baseFixtures(overrides = {}) {
  const paymentId = overrides.paymentId || "pay_safe_1";
  const uid = overrides.uid || "uid_a";
  const planOrderId = overrides.planOrderId || "po_safe_1";
  const approvedAt = overrides.approvedAt || "2026-08-15T12:00:00.000Z";
  const updatedAt =
    overrides.updatedAt || overrides.processed?.updatedAt || "2026-08-15T12:05:00.000Z";
  const amount = overrides.amount ?? 29.99;
  const periodEnd = computePlanPeriodEnd("intermediate_monthly", approvedAt, norm);

  return {
    paymentId,
    uid,
    planOrderId,
    approvedAt,
    processed: {
      paymentId,
      status: "processing",
      uid,
      planOrderId,
      createdAt: approvedAt,
      updatedAt,
      ...overrides.processed,
    },
    provider: {
      id: paymentId,
      status: "approved",
      transaction_amount: amount,
      date_approved: approvedAt,
      external_reference: planOrderId,
      metadata: {
        uid,
        plan_order_id: planOrderId,
        normalized_plan_id: "intermediate_monthly",
      },
      refunds: overrides.refunds || [],
      ...overrides.provider,
    },
    order: {
      planOrderId,
      userId: uid,
      canonicalPlanId: "intermediate_monthly",
      orderStatus: "PENDENTE",
      mpPaymentStatus: "approved",
      ...overrides.order,
    },
    user: {
      currentPlanId: "free_limited",
      status: "active",
      ...overrides.user,
    },
    subscription: overrides.subscription ?? null,
    periodEnd,
  };
}

describe("stuckPaymentReconciliation — classifier", () => {
  it("approved never granted + period active → SAFE_REPAIR_CANDIDATE", () => {
    const f = baseFixtures();
    const now = new Date("2026-09-01T12:00:00Z");
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      user: f.user,
      subscription: f.subscription,
      normalizePlanId: norm,
      now,
      staleThresholdMs: 60_000,
    });
    assert.equal(r.classification, Classification.SAFE_REPAIR_CANDIDATE);
    assert.equal(r.outcome, ReconciliationOutcome.SAFE_REPAIR_CANDIDATE);
    assert.equal(r.reasonCode, ReasonCode.APPROVED_NOT_GRANTED);
    assert.equal(r.autoRepair, false);
  });

  it("already granted → ALREADY_GRANTED", () => {
    const f = baseFixtures({
      order: { orderStatus: "ATIVO", paymentConfirmation: "PAGO_CONFIRMADO" },
    });
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      user: { currentPlanId: "intermediate_monthly", planLastPaymentId: f.paymentId },
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.classification, Classification.ALREADY_GRANTED);
  });

  it("processing recente → IN_FLIGHT", () => {
    const f = baseFixtures({
      processed: { updatedAt: new Date().toISOString() },
    });
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      user: f.user,
      normalizePlanId: norm,
      staleThresholdMs: 60_000,
    });
    assert.equal(r.classification, Classification.IN_FLIGHT);
    assert.equal(r.reasonCode, ReasonCode.PROCESSING_NOT_STALE);
  });

  it("mapping ambíguo → MANUAL_REVIEW / MAPPING_FAILURE", () => {
    const f = baseFixtures();
    const r = classifyStuckPayment({
      processed: { ...f.processed, uid: "uid_a", planOrderId: "po_x" },
      providerPayment: { ...f.provider, metadata: { uid: "uid_b", plan_order_id: "po_y" } },
      order: null,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.classification, Classification.MAPPING_FAILURE);
  });

  it("missing order → bloqueado", () => {
    const f = baseFixtures();
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: null,
      user: f.user,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.outcome, ReconciliationOutcome.MAPPING_FAILURE);
  });

  it("refund → bloqueado", () => {
    const f = baseFixtures({ refunds: [{ id: 1 }] });
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.reasonCode, ReasonCode.PAYMENT_REFUNDED);
  });

  it("chargeback → bloqueado", () => {
    const f = baseFixtures({ provider: { status: "charged_back" } });
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.reasonCode, ReasonCode.PAYMENT_CHARGEDBACK);
  });

  it("payment R$ 0 → UNRELATED / ZERO_AMOUNT", () => {
    const r = classifyStuckPayment({
      processed: {
        paymentId: "pay_zero",
        status: "processing",
        updatedAt: new Date(Date.now() - 86400000).toISOString(),
      },
      providerPayment: {
        status: "approved",
        transaction_amount: 0,
        metadata: {},
      },
      order: null,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.classification, Classification.UNRELATED_PAYMENT);
    assert.equal(r.reasonCode, ReasonCode.ZERO_AMOUNT);
  });

  it("período original expirado → BUSINESS_DECISION_REQUIRED (CASE-001 sintético)", () => {
    const approvedAt = expiredApproved();
    const f = baseFixtures({
      paymentId: "pay_case001",
      approvedAt,
      updatedAt: "2026-05-26T21:36:40.145Z",
      user: { currentPlanId: "free_trial_90d", status: "trialing" },
    });
    const r = classifyStuckPayment({
      processed: f.processed,
      providerPayment: f.provider,
      order: f.order,
      user: f.user,
      normalizePlanId: norm,
      now: new Date("2026-09-02T12:00:00Z"),
      staleThresholdMs: 0,
    });
    assert.equal(r.classification, Classification.BUSINESS_DECISION_REQUIRED);
    assert.equal(r.reasonCode, ReasonCode.PERIOD_EXPIRED);
    assert.equal(r.autoRepair, false);
    const plan = planReconciliation(r);
    assert.equal(plan.action, "NOOP");
  });

  it("CASE-002 sintético → UNRELATED / MANUAL", () => {
    const r = classifyStuckPayment({
      processed: {
        paymentId: "pay_case002",
        status: "processing",
        rawStatus: "approved",
        updatedAt: new Date(Date.now() - 86400000).toISOString(),
      },
      providerPayment: {
        status: "approved",
        transaction_amount: 0,
        external_reference: null,
        metadata: {},
      },
      order: null,
      normalizePlanId: norm,
      staleThresholdMs: 0,
    });
    assert.equal(r.classification, Classification.UNRELATED_PAYMENT);
    assert.equal(r.autoRepair, false);
  });
});

describe("stuckPaymentReconciliation — monitor", () => {
  it("DEFAULT_MONITOR_OPTIONS dryRun=true autoExecuteRepair=false", () => {
    assert.equal(DEFAULT_MONITOR_OPTIONS.dryRun, true);
    assert.equal(DEFAULT_MONITOR_OPTIONS.autoExecuteRepair, false);
  });

  it("scan produz resumo sem PII", async () => {
    const f = baseFixtures();
    const scan = await scanProcessingPayments([f.processed], {
      fetchProviderPayment: async () => f.provider,
      fetchOrder: async () => f.order,
      fetchUser: async () => f.user,
      fetchSubscription: async () => null,
      normalizePlanId: norm,
    });
    assert.equal(scan.dryRun, true);
    assert.equal(scan.autoExecuteRepair, false);
    assert.equal(scan.summary.totalProcessing, 1);
    assert.ok(scan.cases[0].log.maskedPaymentId.includes("*"));
    assert.equal(scan.cases[0].log.maskedPaymentId.includes("@"), false);
  });
});

describe("stuckPaymentReconciliation — executor idempotente", () => {
  it("dryRun não escreve", async () => {
    const f = baseFixtures();
    const db = createMemoryFirestore({
      [`processed_plan_payments/${f.paymentId}`]: f.processed,
      [`plan_orders/${f.planOrderId}`]: f.order,
      [`users/${f.uid}`]: f.user,
    });
    const now = new Date("2026-09-01T12:00:00Z");
    const r = await executeIdempotentReconciliation({
      db,
      paymentId: f.paymentId,
      providerPayment: f.provider,
      normalizePlanId: norm,
      dryRun: true,
      now,
    });
    assert.equal(r.applied, false);
    assert.equal(r.outcome, ReconciliationOutcome.REPAIR_SKIPPED_DRY_RUN);
    assert.equal(db._docs.get(`users/${f.uid}`).currentPlanId, "free_limited");
  });

  it("repair aplica no máximo uma vez; segunda execução NOOP", async () => {
    const f = baseFixtures();
    const db = createMemoryFirestore({
      [`processed_plan_payments/${f.paymentId}`]: f.processed,
      [`plan_orders/${f.planOrderId}`]: f.order,
      [`users/${f.uid}`]: f.user,
    });
    const now = new Date("2026-09-01T12:00:00Z");
    const first = await executeIdempotentReconciliation({
      db,
      paymentId: f.paymentId,
      providerPayment: f.provider,
      normalizePlanId: norm,
      dryRun: false,
      nowTs: Timestamp.now(),
      now,
    });
    assert.equal(first.applied, true);
    assert.equal(first.outcome, ReconciliationOutcome.REPAIR_APPLIED);
    assert.equal(db._docs.get(`processed_plan_payments/${f.paymentId}`).status, "approved");
    assert.equal(db._docs.get(`users/${f.uid}`).currentPlanId, "intermediate_monthly");

    const second = await executeIdempotentReconciliation({
      db,
      paymentId: f.paymentId,
      providerPayment: f.provider,
      normalizePlanId: norm,
      dryRun: false,
      now,
    });
    assert.equal(second.applied, false);
    assert.ok(
      second.outcome === ReconciliationOutcome.ALREADY_RECONCILED ||
        second.outcome === ReconciliationOutcome.ALREADY_GRANTED,
    );
  });

  it("não usa blind webhook replay", async () => {
    const f = baseFixtures();
    const r = await executeIdempotentReconciliation({
      db: createMemoryFirestore({}),
      paymentId: f.paymentId,
      providerPayment: f.provider,
      normalizePlanId: norm,
      dryRun: true,
    });
    assert.equal(r.blindWebhookReplay, false);
  });
});

describe("planPeriod", () => {
  it("intermediate_monthly +1 mês igual activatePlanForUser semantics", () => {
    const start = new Date("2026-04-20T15:20:07Z");
    const end = computePlanPeriodEnd("intermediate_monthly", start, norm);
    assert.equal(end.toISOString(), "2026-05-20T15:20:07.000Z");
  });
});
