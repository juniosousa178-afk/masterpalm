/**
 * P1C + webhook ordering (sintético)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  applyLegacyNonApprovedBillingWrite,
  billingPatchContainsAccountStatus,
  billingPatchForNonApprovedPayment,
} from "../src/billingWebhookStatus.js";
import { syncFirestoreFromPreapproval } from "../src/mpPlanRecurring.js";
import { createMemoryFirestore } from "./_memoryFirestore.js";

describe("P1C billingPatchForNonApprovedPayment", () => {
  it("pending não inclui users.status", () => {
    const p = billingPatchForNonApprovedPayment("pending", "ts");
    assert.equal(p.billingStatus, "checkout_pending");
    assert.equal(billingPatchContainsAccountStatus(p), false);
    assert.equal(p.status, undefined);
  });

  it("rejected/failed não inclui users.status", () => {
    const p = billingPatchForNonApprovedPayment("rejected", "ts");
    assert.equal(p.billingStatus, "failed");
    assert.equal(billingPatchContainsAccountStatus(p), false);
  });
});

describe("P1C applyLegacyNonApprovedBillingWrite", () => {
  it("checkout pending não desactiva conta", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    const r = await applyLegacyNonApprovedBillingWrite(db, {
      uid: "u1",
      checkoutStatus: "pending",
      nowTs: "ts",
    });
    assert.equal(r.skipped, false);
    const u = db._docs.get("users/u1");
    assert.equal(u.status, "active");
    assert.equal(u.billingStatus, "checkout_pending");
  });

  it("pagamento falho não desactiva conta", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    await applyLegacyNonApprovedBillingWrite(db, {
      uid: "u1",
      checkoutStatus: "rejected",
      nowTs: "ts",
    });
    const u = db._docs.get("users/u1");
    assert.equal(u.status, "active");
    assert.equal(u.billingStatus, "failed");
  });

  it("já active pago: pending posterior não despromove", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        billingStatus: "active",
        currentPlanId: "pro_monthly",
        providerSubscriptionId: "pre_a",
      },
    });
    const r = await applyLegacyNonApprovedBillingWrite(db, {
      uid: "u1",
      checkoutStatus: "pending",
      nowTs: "ts",
    });
    assert.equal(r.skipped, true);
    const u = db._docs.get("users/u1");
    assert.equal(u.billingStatus, "active");
    assert.equal(u.status, "active");
    assert.equal(u.currentPlanId, "pro_monthly");
  });
});

describe("webhook ordering / P1B pending sync", () => {
  it("pending após approved (mesmo provider) não despromove", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        billingStatus: "active",
        currentPlanId: "pro_monthly",
        providerSubscriptionId: "pre_a",
      },
    });
    const r = await syncFirestoreFromPreapproval({
      db,
      uid: "u1",
      email: "a@test.com",
      canonicalPlanId: "pro_monthly",
      preapproval: { id: "pre_a", status: "pending", external_reference: "mprec|u1|create|pro_monthly" },
      nowTs: "ts",
    });
    assert.equal(r.phase, "ignored_downgrade");
    const u = db._docs.get("users/u1");
    assert.equal(u.currentPlanId, "pro_monthly");
    assert.equal(u.providerSubscriptionId, "pre_a");
    assert.equal(u.status, "active");
  });

  it("create pending não escreve providerSubscriptionId", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    await syncFirestoreFromPreapproval({
      db,
      uid: "u1",
      email: "a@test.com",
      canonicalPlanId: "pro_monthly",
      preapproval: { id: "pre_new", status: "pending", external_reference: "mprec|u1|create|pro_monthly" },
      nowTs: "ts",
    });
    const u = db._docs.get("users/u1");
    assert.equal(u.providerSubscriptionId, undefined);
    assert.equal(u.pendingSubscriptionId, "pre_new");
    assert.equal(u.status, "active");
    assert.equal(u.billingStatus, "checkout_pending");
    assert.equal(u.currentPlanId, "free_limited");
  });

  it("pending de troca não sobrescreve provider activo", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        billingStatus: "active",
        currentPlanId: "basic_monthly",
        providerSubscriptionId: "pre_old",
      },
    });
    await syncFirestoreFromPreapproval({
      db,
      uid: "u1",
      email: "a@test.com",
      canonicalPlanId: "pro_monthly",
      preapproval: { id: "pre_new", status: "pending" },
      nowTs: "ts",
    });
    const u = db._docs.get("users/u1");
    assert.equal(u.providerSubscriptionId, "pre_old");
    assert.equal(u.pendingSubscriptionId, "pre_new");
  });
});
