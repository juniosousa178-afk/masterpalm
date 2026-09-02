/**
 * node --test test/subscription_webhook.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  tryProcessPlanOrderWebhook,
  revokeIfLastPayment,
  PLAN_ORDERS_COL,
} from "../src/planOrdersWebhook.js";

const NOW = { seconds: 1_700_000_000, nanoseconds: 0 };

function makeDb({ orders = {}, users = {}, processed = {} } = {}) {
  const state = { orders: { ...orders }, users: { ...users }, processed: { ...processed } };
  const db = {
    state,
    collection(name) {
      if (name === PLAN_ORDERS_COL) {
        return {
          doc(id) {
            return {
              async get() {
                const d = state.orders[id];
                return { exists: d != null, data: () => d };
              },
              async set(patch) {
                state.orders[id] = { ...(state.orders[id] || {}), ...patch };
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
                const d = state.processed[id];
                return { exists: d != null, data: () => d };
              },
              async set(patch) {
                state.processed[id] = { ...(state.processed[id] || {}), ...patch };
              },
            };
          },
        };
      }
      if (name === "users") {
        return {
          doc(uid) {
            return {
              async get() {
                const d = state.users[uid];
                return { exists: d != null, data: () => d };
              },
              async set(patch) {
                state.users[uid] = { ...(state.users[uid] || {}), ...patch };
              },
              collection() {
                return {
                  doc() {
                    return { async set() {} };
                  },
                };
              },
            };
          },
        };
      }
      throw new Error(`unexpected collection ${name}`);
    },
    async runTransaction(fn) {
      const tx = {
        async get(ref) {
          return ref.get();
        },
        set(ref, data, opts) {
          return ref.set(data, opts);
        },
      };
      return fn(tx);
    },
  };
  return db;
}

describe("tryProcessPlanOrderWebhook", () => {
  it("pagamento approved ativa plano correto", async () => {
    const activations = [];
    const db = makeDb({
      orders: {
        po_abc: {
          userId: "uid_a",
          canonicalPlanId: "intermediate_monthly",
        },
      },
      users: { uid_a: { currentPlanId: "free_limited" } },
    });
    const handled = await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "approved", external_reference: "po_abc", transaction_amount: 29.99 },
      paymentId: "pay_1",
      nowTs: NOW,
      normalizePlanId: (p) => String(p || "").trim().toLowerCase(),
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async (args) => {
        activations.push(args);
      },
    });
    assert.equal(handled, true);
    assert.equal(activations.length, 1);
    assert.equal(activations[0].plan, "intermediate_monthly");
    assert.equal(activations[0].uid, "uid_a");
    assert.equal(db.state.orders.po_abc.orderStatus, "ATIVO");
  });

  it("pagamento pending não ativa", async () => {
    const activations = [];
    const db = makeDb({
      orders: { po_pend: { userId: "uid_p", canonicalPlanId: "pro_monthly" } },
    });
    await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "pending", external_reference: "po_pend" },
      paymentId: "pay_p",
      nowTs: NOW,
      normalizePlanId: (p) => p,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async (a) => activations.push(a),
    });
    assert.equal(activations.length, 0);
    assert.equal(db.state.orders.po_pend.orderStatus, "PENDENTE");
  });

  it("pagamento rejected não ativa", async () => {
    const activations = [];
    const db = makeDb({
      orders: { po_rej: { userId: "uid_r", canonicalPlanId: "pro_monthly" } },
    });
    await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "rejected", external_reference: "po_rej" },
      paymentId: "pay_r",
      nowTs: NOW,
      normalizePlanId: (p) => p,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async (a) => activations.push(a),
    });
    assert.equal(activations.length, 0);
    assert.equal(db.state.orders.po_rej.orderStatus, "FALHA");
  });

  it("evento duplicado approved é idempotente", async () => {
    let activations = 0;
    const db = makeDb({
      orders: { po_dup: { userId: "uid_d", canonicalPlanId: "basic_monthly" } },
      processed: { pay_dup: { status: "approved" } },
    });
    await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "approved", external_reference: "po_dup" },
      paymentId: "pay_dup",
      nowTs: NOW,
      normalizePlanId: (p) => p,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async () => {
        activations++;
      },
    });
    assert.equal(activations, 0);
  });

  it("ordem sem userId não ativa outro uid", async () => {
    const activations = [];
    const db = makeDb({
      orders: { po_no_uid: { canonicalPlanId: "pro_monthly" } },
    });
    const handled = await tryProcessPlanOrderWebhook({
      db,
      payment: { status: "approved", external_reference: "po_no_uid" },
      paymentId: "pay_x",
      nowTs: NOW,
      normalizePlanId: (p) => p,
      mapCheckoutStatus: (s) => s,
      activatePlanForUser: async (a) => activations.push(a),
    });
    assert.equal(handled, true);
    assert.equal(activations.length, 0);
  });

  it("refunded revoga se último pagamento", async () => {
    const db = makeDb({
      users: {
        uid_ref: {
          currentPlanId: "pro_monthly",
          planLastPaymentId: "pay_ref",
        },
      },
    });
    await revokeIfLastPayment({
      db,
      uid: "uid_ref",
      paymentId: "pay_ref",
      nowTs: NOW,
    });
    assert.equal(db.state.users.uid_ref.currentPlanId, "free_limited");
  });
});
