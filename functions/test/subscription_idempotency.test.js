/**
 * node --test test/subscription_idempotency.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { tryProcessPlanOrderWebhook } from "../src/planOrdersWebhook.js";
import { buildAuditActionIdentity } from "../src/masterPlanAdmin.js";

const NOW = { seconds: 1_700_000_000, nanoseconds: 0 };

describe("subscription idempotency", () => {
  it("webhook duplicado não chama activatePlanForUser duas vezes", async () => {
    let activations = 0;
    const processed = {};
    const orders = { po_idem: { userId: "uid_i", canonicalPlanId: "pro_monthly" } };
    const db = {
      collection(name) {
        if (name === "plan_orders") {
          return {
            doc(id) {
              return {
                async get() {
                  return { exists: true, data: () => orders[id] };
                },
                async set(patch) {
                  Object.assign(orders[id], patch);
                },
              };
            },
          };
        }
        if (name === "processed_plan_payments") {
          return {
            doc(id) {
              return {
                async get() {
                  return { exists: processed[id] != null, data: () => processed[id] };
                },
                async set(patch) {
                  processed[id] = { ...(processed[id] || {}), ...patch };
                },
              };
            },
          };
        }
        throw new Error(name);
      },
      async runTransaction(fn) {
        const tx = {
          get: (ref) => ref.get(),
          set: (ref, data) => ref.set(data),
        };
        return fn(tx);
      },
    };

    const args = {
      db,
      payment: { status: "approved", external_reference: "po_idem" },
      paymentId: "pay_idem",
      nowTs: NOW,
      normalizePlanId: (p) => p,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async () => {
        activations++;
      },
    };

    await tryProcessPlanOrderWebhook(args);
    await tryProcessPlanOrderWebhook(args);
    assert.equal(activations, 1);
  });

  it("cortesia requestId gera actionId determinístico", () => {
    const a = buildAuditActionIdentity("actor", "target", "grant_courtesy", "req12345678901234");
    const b = buildAuditActionIdentity("actor", "target", "grant_courtesy", "req12345678901234");
    assert.equal(a.actionId, b.actionId);
  });
});
