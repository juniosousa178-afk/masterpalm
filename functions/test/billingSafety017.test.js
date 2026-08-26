/**
 * Release A — create/change safety (P1A/P1B/P1D). Provider 100% fake.
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { HttpsError } from "firebase-functions/v2/https";

import {
  evaluateBillingPreflight,
  parseExternalReferenceMpRecurring,
  runCreatePlanSubscription,
  shouldBlockCreateRecurringSubscription,
} from "../src/mpPlanRecurring.js";
import { runCreatePlanChangeSubscription } from "../src/mpPlanChange.js";
import { createMemoryFirestore } from "./_memoryFirestore.js";

const ENV_KEY = "USE_RECURRING_PLAN_BILLING";
let savedEnv;

beforeEach(() => {
  savedEnv = process.env[ENV_KEY];
  process.env[ENV_KEY] = "true";
});
afterEach(() => {
  if (savedEnv === undefined) delete process.env[ENV_KEY];
  else process.env[ENV_KEY] = savedEnv;
});

const prices = {
  PRICE_BASIC_MONTHLY: 19.99,
  PRICE_INTERMEDIATE_MONTHLY: 29.99,
  PRICE_PRO_MONTHLY: 39.99,
  PRICE_PRO_YEARLY: 399.99,
};
const norm = (x) => String(x || "").trim().toLowerCase();
const futureEnd = { toMillis: () => Date.now() + 86_400_000 };

function requestFor(uid, plan) {
  return {
    auth: { uid, token: { email: "a@test.com" } },
    data: { plan, returnUrl: "https://evil.example/hijack" },
  };
}

describe("parseExternalReferenceMpRecurring 4 partes", () => {
  it("mprec|uid|create|plan", () => {
    const r = parseExternalReferenceMpRecurring("mprec|abc|create|pro_monthly");
    assert.equal(r.uid, "abc");
    assert.equal(r.canonicalPlanId, "pro_monthly");
  });
});

describe("P1D evaluateBillingPreflight / shouldBlock wired", () => {
  it("same plan activo → NO_OP", () => {
    const r = evaluateBillingPreflight({
      operation: "create",
      canonicalRequested: "pro_monthly",
      userData: {
        currentPlanId: "pro_monthly",
        planStatus: "active",
        status: "active",
        billingMode: "recurring",
        providerSubscriptionId: "pre_1",
        currentPeriodEnd: futureEnd,
      },
      normalizePlanId: norm,
    });
    assert.equal(r.result, "NO_OP");
    const b = shouldBlockCreateRecurringSubscription({
      canonicalRequested: "pro_monthly",
      userData: {
        currentPlanId: "pro_monthly",
        planStatus: "active",
        status: "active",
        billingMode: "recurring",
        providerSubscriptionId: "pre_1",
        currentPeriodEnd: futureEnd,
      },
      normalizePlanId: norm,
    });
    assert.equal(b.blocked, false);
    assert.equal(b.result, "NO_OP");
  });

  it("duplicate activo outro plano → FAIL_CLOSED / blocked", () => {
    const r = shouldBlockCreateRecurringSubscription({
      canonicalRequested: "intermediate_monthly",
      userData: {
        currentPlanId: "basic_monthly",
        planStatus: "active",
        status: "active",
        billingMode: "recurring",
        providerSubscriptionId: "pre_1",
        currentPeriodEnd: futureEnd,
      },
      normalizePlanId: norm,
    });
    assert.equal(r.blocked, true);
    assert.equal(r.result, "FAIL_CLOSED");
  });

  it("failed order legado não bloqueia Free→Pro", () => {
    const r = evaluateBillingPreflight({
      operation: "create",
      canonicalRequested: "pro_monthly",
      userData: {
        currentPlanId: "free_limited",
        status: "active",
        lastPlanOrderStatus: "FALHA",
      },
      normalizePlanId: norm,
    });
    assert.equal(r.result, "ALLOW");
  });

  it("estado ambíguo FAIL_CLOSED", () => {
    const r = evaluateBillingPreflight({
      operation: "create",
      canonicalRequested: "pro_monthly",
      userData: {
        currentPlanId: "pro_monthly",
        billingMode: "recurring",
        status: "active",
        planStatus: "active",
      },
      normalizePlanId: norm,
    });
    assert.equal(r.result, "FAIL_CLOSED");
    assert.equal(r.reason, "paid_recurring_missing_provider_id");
  });

  it("CREATING fresco → BLOCK_VISIBLE", () => {
    const r = evaluateBillingPreflight({
      operation: "create",
      canonicalRequested: "pro_monthly",
      userData: { currentPlanId: "free_limited", status: "active" },
      normalizePlanId: norm,
      idempotencyRecord: { state: "CREATING", updatedAtMs: Date.now() },
    });
    assert.equal(r.result, "BLOCK_VISIBLE");
  });
});

describe("P1A/P1B runCreatePlanSubscription", () => {
  it("double click: um POST MP e replay devolve o mesmo initPoint", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    let posts = 0;
    const createPreapproval = async () => {
      posts += 1;
      return {
        id: "pre_once",
        init_point: "https://www.mercadopago.com.br/checkout/v1/redirect?preapproval_id=pre_once",
        status: "pending",
      };
    };
    const args = {
      db,
      request: requestFor("u1", "pro_monthly"),
      token: "fake",
      webBase: "https://app.mastepalm.com.br",
      prices,
      planTitleForMp: () => "Pro",
      normalizePlanId: norm,
      createPreapproval,
      searchPreapprovalByExternalReference: async () => null,
    };
    const a = await runCreatePlanSubscription(args);
    const b = await runCreatePlanSubscription(args);
    assert.equal(posts, 1);
    assert.equal(a.initPoint, b.initPoint);
    assert.equal(b.reused, true);
    const u = db._docs.get("users/u1");
    assert.equal(u.providerSubscriptionId, undefined);
    assert.equal(u.pendingSubscriptionId, "pre_once");
    assert.equal(u.currentPlanId, "free_limited");
    assert.equal(u.status, "active");
    assert.ok(!String(a.externalReference).includes(String(Date.now()).slice(0, 8)));
    assert.equal(a.externalReference, "mprec|u1|create|pro_monthly");
    assert.ok(!String(args.request.data.returnUrl).includes("evil") || a.ok);
  });

  it("mesmo plano activo: 0 POST MP (NO_OP)", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        planStatus: "active",
        currentPlanId: "pro_monthly",
        billingMode: "recurring",
        providerSubscriptionId: "pre_live",
        currentPeriodEnd: futureEnd,
      },
    });
    let posts = 0;
    const r = await runCreatePlanSubscription({
      db,
      request: requestFor("u1", "pro_monthly"),
      token: "fake",
      webBase: "https://app.example",
      prices,
      planTitleForMp: () => "Pro",
      normalizePlanId: norm,
      createPreapproval: async () => {
        posts += 1;
        throw new Error("should not POST");
      },
    });
    assert.equal(r.alreadyActive, true);
    assert.equal(posts, 0);
  });

  it("ignora returnUrl do cliente", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    let body;
    await runCreatePlanSubscription({
      db,
      request: requestFor("u1", "pro_monthly"),
      token: "fake",
      webBase: "https://app.mastepalm.com.br",
      prices,
      planTitleForMp: () => "Pro",
      normalizePlanId: norm,
      createPreapproval: async (_t, b) => {
        body = b;
        return { id: "pre_x", init_point: "https://www.mercadopago.com.br/x", status: "pending" };
      },
      searchPreapprovalByExternalReference: async () => null,
    });
    assert.equal(body.back_url, "https://app.mastepalm.com.br/planos/retorno");
    assert.equal(String(body.back_url).includes("evil"), false);
  });

  it("provider ok + persistência local: replay não faz 2º POST (response loss)", async () => {
    const db = createMemoryFirestore({
      "users/u1": { status: "active", currentPlanId: "free_limited" },
    });
    let posts = 0;
    const createPreapproval = async () => {
      posts += 1;
      return { id: "pre_z", init_point: "https://www.mercadopago.com.br/z", status: "pending" };
    };
    const args = {
      db,
      request: requestFor("u1", "basic_monthly"),
      token: "t",
      webBase: "https://app.example",
      prices,
      planTitleForMp: () => "Basic",
      normalizePlanId: norm,
      createPreapproval,
      searchPreapprovalByExternalReference: async () => null,
    };
    await runCreatePlanSubscription(args);
    await runCreatePlanSubscription(args);
    assert.equal(posts, 1);
  });

  it("shouldBlock é invocado: pago activo outro plano não cria", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        planStatus: "active",
        currentPlanId: "basic_monthly",
        billingMode: "recurring",
        providerSubscriptionId: "pre_live",
        currentPeriodEnd: futureEnd,
      },
    });
    let posts = 0;
    await assert.rejects(
      () =>
        runCreatePlanSubscription({
          db,
          request: requestFor("u1", "pro_monthly"),
          token: "t",
          webBase: "https://app.example",
          prices,
          planTitleForMp: () => "Pro",
          normalizePlanId: norm,
          createPreapproval: async () => {
            posts += 1;
            return { id: "x", init_point: "https://www.mercadopago.com.br/x" };
          },
        }),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.match(String(err.message), /troca de plano/i);
        return true;
      },
    );
    assert.equal(posts, 0);
    assert.equal(db._docs.get("users/u1").providerSubscriptionId, "pre_live");
  });
});

describe("P1B runCreatePlanChangeSubscription", () => {
  it("pending não sobrescreve providerSubscriptionId activo", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        planStatus: "active",
        currentPlanId: "basic_monthly",
        billingMode: "recurring",
        providerSubscriptionId: "pre_old",
        currentPeriodEnd: futureEnd,
      },
      "users/u1/subscriptions/pre_old": {
        status: "active",
        paymentStatus: "approved",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: futureEnd,
      },
    });
    const r = await runCreatePlanChangeSubscription({
      db,
      request: {
        auth: { uid: "u1", token: { email: "a@test.com" } },
        data: { requestedPlanId: "pro_monthly" },
      },
      token: "t",
      webBase: "https://app.example",
      prices,
      planTitleForMp: () => "Pro",
      normalizePlanId: norm,
      createPreapproval: async () => ({
        id: "pre_new",
        init_point: "https://www.mercadopago.com.br/new",
        status: "pending",
      }),
    });
    assert.equal(r.ok, true);
    assert.equal(r.newPreapprovalId, "pre_new");
    const u = db._docs.get("users/u1");
    assert.equal(u.providerSubscriptionId, "pre_old");
    assert.equal(u.pendingPlanChangePreapprovalId, "pre_new");
    assert.equal(u.currentPlanId, "basic_monthly");
  });

  it("replay idempotente: 1 POST", async () => {
    const db = createMemoryFirestore({
      "users/u1": {
        status: "active",
        planStatus: "active",
        currentPlanId: "basic_monthly",
        billingMode: "recurring",
        providerSubscriptionId: "pre_old",
        currentPeriodEnd: futureEnd,
      },
      "users/u1/subscriptions/pre_old": {
        status: "active",
        paymentStatus: "approved",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: futureEnd,
      },
    });
    let posts = 0;
    const args = {
      db,
      request: {
        auth: { uid: "u1", token: { email: "a@test.com" } },
        data: { requestedPlanId: "pro_monthly" },
      },
      token: "t",
      webBase: "https://app.example",
      prices,
      planTitleForMp: () => "Pro",
      normalizePlanId: norm,
      createPreapproval: async () => {
        posts += 1;
        return {
          id: "pre_new",
          init_point: "https://www.mercadopago.com.br/new",
          status: "pending",
        };
      },
    };
    const a = await runCreatePlanChangeSubscription(args);
    const b = await runCreatePlanChangeSubscription(args);
    assert.equal(posts, 1);
    assert.equal(a.initPoint, b.initPoint);
    assert.equal(db._docs.get("users/u1").providerSubscriptionId, "pre_old");
  });
});
