/**
 * P1A — idempotency (node --test)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  BILLING_OP_CREATE,
  BILLING_OP_STATE,
  CREATING_LOCK_MS,
  billingOperationDocId,
  claimOrReuseBillingOperation,
  completeBillingOperationCreated,
  deterministicCreateExternalReference,
  idempotencyKeyContainsEpochMs,
} from "../src/billingOperations.js";
import { createMemoryFirestore } from "./_memoryFirestore.js";

describe("P1A idempotency key", () => {
  it("chave canónica uid+op+plan sem epoch ms", () => {
    const id = billingOperationDocId(BILLING_OP_CREATE, "u1", "pro_monthly");
    assert.equal(id, "create:u1:pro_monthly");
    assert.equal(idempotencyKeyContainsEpochMs(id), false);
    const ext = deterministicCreateExternalReference("u1", "pro_monthly");
    assert.equal(ext, "mprec|u1|create|pro_monthly");
    assert.equal(idempotencyKeyContainsEpochMs(ext), false);
    assert.equal(ext.includes(String(Date.now())), false);
  });
});

describe("P1A claimOrReuseBillingOperation", () => {
  it("mesmo pedido após CREATED reutiliza initPoint sem segundo create", async () => {
    const db = createMemoryFirestore();
    const first = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u1",
      canonicalPlanId: "pro_monthly",
      nowMs: 1_000,
    });
    assert.equal(first.action, "CREATE");
    await completeBillingOperationCreated(db, {
      op: BILLING_OP_CREATE,
      uid: "u1",
      canonicalPlanId: "pro_monthly",
      pendingProviderSubscriptionId: "pre_1",
      initPoint: "https://www.mercadopago.com.br/x",
      externalReference: "mprec|u1|create|pro_monthly",
      nowMs: 1_001,
    });
    const second = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u1",
      canonicalPlanId: "pro_monthly",
      nowMs: 2_000,
    });
    assert.equal(second.action, "REUSE");
    assert.equal(second.record.initPoint, "https://www.mercadopago.com.br/x");
    assert.equal(second.record.state, BILLING_OP_STATE.CREATED);
  });

  it("CREATING fresco bloqueia segundo pedido (double click / concurrent)", async () => {
    const db = createMemoryFirestore();
    const a = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u2",
      canonicalPlanId: "pro_monthly",
      nowMs: 10_000,
    });
    assert.equal(a.action, "CREATE");
    const b = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u2",
      canonicalPlanId: "pro_monthly",
      nowMs: 10_000 + 1_000,
    });
    assert.equal(b.action, "IN_PROGRESS");
  });

  it("CREATING stale (>120s) sem provider id → RECONCILE", async () => {
    const db = createMemoryFirestore();
    await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u3",
      canonicalPlanId: "pro_monthly",
      nowMs: 1,
    });
    const stale = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u3",
      canonicalPlanId: "pro_monthly",
      nowMs: 1 + CREATING_LOCK_MS + 1,
    });
    assert.equal(stale.action, "RECONCILE");
  });

  it("provider id já gravado em CREATING → FINALIZE_LOCAL (não segundo POST)", async () => {
    const db = createMemoryFirestore({
      "billing_operations/create:u4:pro_monthly": {
        state: BILLING_OP_STATE.CREATING,
        pendingProviderSubscriptionId: "pre_existing",
        updatedAtMs: Date.now(),
      },
    });
    const d = await claimOrReuseBillingOperation(db, {
      op: BILLING_OP_CREATE,
      uid: "u4",
      canonicalPlanId: "pro_monthly",
      nowMs: Date.now(),
    });
    assert.equal(d.action, "FINALIZE_LOCAL");
    assert.equal(d.record.pendingProviderSubscriptionId, "pre_existing");
  });
});
