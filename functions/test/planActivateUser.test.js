/**
 * node --test test/planActivateUser.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Timestamp } from "firebase-admin/firestore";

import { activatePlanForUser } from "../src/planActivateUser.js";
import { tryProcessPlanOrderWebhook } from "../src/planOrdersWebhook.js";
import { createMemoryFirestore } from "./_memoryFirestore.js";

const NOW = { _tag: "serverTimestamp" };
const normalizePlanId = (p) => String(p || "").trim().toLowerCase();

const __dirname = dirname(fileURLToPath(import.meta.url));

describe("planActivateUser — ESM Timestamp", () => {
  it("fonte não usa admin.firestore.Timestamp em código executável", () => {
    const src = readFileSync(join(__dirname, "../src/planActivateUser.js"), "utf8");
    const withoutComments = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    assert.equal(withoutComments.includes("admin.firestore.Timestamp"), false);
    assert.match(withoutComments, /Timestamp\.fromDate\(/);
  });

  it("index.js não usa admin.firestore.Timestamp em activatePlanForUser", () => {
    const src = readFileSync(join(__dirname, "../index.js"), "utf8");
    assert.equal(src.includes("admin.firestore.Timestamp"), false);
  });

  it("intermediate_monthly approved grava currentPlanId e Timestamp válido", async () => {
    const db = createMemoryFirestore({
      "users/uid_a": { currentPlanId: "free_limited", status: "active" },
      "plan_orders/po_test": { userId: "uid_a", canonicalPlanId: "intermediate_monthly" },
    });

    const before = Date.now();
    const payload = await activatePlanForUser({
      db,
      uid: "uid_a",
      plan: "intermediate_monthly",
      paymentId: "pay_test_1",
      amount: 49.99,
      planOrderId: "po_test",
      normalizePlanId,
      nowTs: NOW,
    });

    assert.equal(payload.currentPlanId, "intermediate_monthly");
    assert.ok(payload.currentPeriodEnd instanceof Timestamp);

    const user = db._docs.get("users/uid_a");
    assert.equal(user.currentPlanId, "intermediate_monthly");
    assert.ok(user.currentPeriodEnd instanceof Timestamp);
    assert.equal(user.planLastPaymentId, "pay_test_1");

    const endMs = user.currentPeriodEnd.toMillis();
    const monthMs = 30 * 24 * 60 * 60 * 1000;
    assert.ok(endMs > before);
    assert.ok(endMs < before + monthMs + 5 * 24 * 60 * 60 * 1000);

    const sub = db._docs.get("users/uid_a/subscriptions/pay_test_1");
    assert.equal(sub.planId, "intermediate_monthly");
    assert.equal(sub.kind, "paid");
    assert.ok(sub.currentPeriodEnd instanceof Timestamp);

    const order = db._docs.get("plan_orders/po_test");
    assert.equal(order.activatedPlanId, "intermediate_monthly");
    assert.ok(order.expiresAt instanceof Timestamp);
  });
});

describe("planActivateUser — webhook integrado", () => {
  it("tryProcessPlanOrderWebhook + activatePlanForUser conclui ATIVO", async () => {
    const db = createMemoryFirestore({
      "users/uid_b": { currentPlanId: "free_limited" },
      "plan_orders/po_int": { userId: "uid_b", canonicalPlanId: "intermediate_monthly" },
    });

    const handled = await tryProcessPlanOrderWebhook({
      db,
      payment: {
        status: "approved",
        external_reference: "po_int",
        transaction_amount: 49.99,
      },
      paymentId: "pay_int_1",
      nowTs: NOW,
      normalizePlanId,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: (args) =>
        activatePlanForUser({ db, normalizePlanId, nowTs: NOW, ...args }),
    });

    assert.equal(handled, true);
    assert.equal(db._docs.get("plan_orders/po_int").orderStatus, "ATIVO");
    assert.equal(db._docs.get("processed_plan_payments/pay_int_1").status, "approved");
    assert.equal(db._docs.get("users/uid_b").currentPlanId, "intermediate_monthly");
  });

  it("falha em activatePlanForUser deixa processing e permite observar erro", async () => {
    const db = createMemoryFirestore({
      "users/uid_fail": { currentPlanId: "free_limited" },
      "plan_orders/po_fail": { userId: "uid_fail", canonicalPlanId: "intermediate_monthly" },
    });

    await assert.rejects(
      () =>
        tryProcessPlanOrderWebhook({
          db,
          payment: { status: "approved", external_reference: "po_fail" },
          paymentId: "pay_fail_1",
          nowTs: NOW,
          normalizePlanId,
          mapCheckoutStatus: (s) => s,
          activatePlanForUser: async () => {
            throw new TypeError("simulated activation failure");
          },
        }),
      /simulated activation failure/,
    );

    assert.equal(db._docs.get("processed_plan_payments/pay_fail_1").status, "processing");
    assert.equal(db._docs.get("plan_orders/po_fail").mpPaymentStatus, "approved");
    assert.notEqual(db._docs.get("plan_orders/po_fail").orderStatus, "ATIVO");
    assert.equal(db._docs.get("users/uid_fail").currentPlanId, "free_limited");
  });

  it("paymentId já approved não reativa (idempotência duplicata)", async () => {
    let activations = 0;
    const db = createMemoryFirestore({
      "users/uid_dup": { currentPlanId: "free_limited" },
      "plan_orders/po_dup": { userId: "uid_dup", canonicalPlanId: "intermediate_monthly" },
      "processed_plan_payments/pay_dup_1": { status: "approved", uid: "uid_dup" },
    });

    await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "approved", external_reference: "po_dup" },
      paymentId: "pay_dup_1",
      nowTs: NOW,
      normalizePlanId,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async () => {
        activations++;
        return activatePlanForUser({
          db,
          uid: "uid_dup",
          plan: "intermediate_monthly",
          paymentId: "pay_dup_1",
          normalizePlanId,
          nowTs: NOW,
        });
      },
    });

    assert.equal(activations, 0);
    assert.equal(db._docs.get("users/uid_dup").currentPlanId, "free_limited");
  });

  it("paymentId preso em processing reprocessaria (gap de idempotência)", async () => {
    let activations = 0;
    const db = createMemoryFirestore({
      "users/uid_stuck": { currentPlanId: "free_limited" },
      "plan_orders/po_stuck": { userId: "uid_stuck", canonicalPlanId: "intermediate_monthly" },
      "processed_plan_payments/pay_stuck_1": { status: "processing", uid: "uid_stuck" },
    });

    await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "approved", external_reference: "po_stuck" },
      paymentId: "pay_stuck_1",
      nowTs: NOW,
      normalizePlanId,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async () => {
        activations++;
        return activatePlanForUser({
          db,
          uid: "uid_stuck",
          plan: "intermediate_monthly",
          paymentId: "pay_stuck_1",
          planOrderId: "po_stuck",
          normalizePlanId,
          nowTs: NOW,
        });
      },
    });

    assert.equal(activations, 1);
    assert.equal(db._docs.get("users/uid_stuck").currentPlanId, "intermediate_monthly");
  });
});
