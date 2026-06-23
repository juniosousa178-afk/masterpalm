/**
 * Helpers de assinatura recorrente (sem emulator).
 * node --test test/mpPlanRecurring.test.js
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

import { HttpsError } from "firebase-functions/v2/https";

import {
  inferPeriodEndFromPreapproval,
  isRecurringPlanBillingEnabled,
  maskProviderSubscriptionIdForLog,
  mergePendingPreapprovalPatch,
  parseExternalReferenceMpRecurring,
  runCancelPlanSubscription,
  runCreatePlanSubscription,
} from "../src/mpPlanRecurring.js";

const ENV_KEY = "USE_RECURRING_PLAN_BILLING";
let savedEnv;

beforeEach(() => {
  savedEnv = process.env[ENV_KEY];
});

afterEach(() => {
  if (savedEnv === undefined) delete process.env[ENV_KEY];
  else process.env[ENV_KEY] = savedEnv;
  if (global.fetch?.__mpPlanRecurringMock) {
    delete global.fetch;
  }
});

function mockMpPutFetch() {
  global.fetch = async () => ({
    ok: true,
    text: async () => "{}",
  });
  global.fetch.__mpPlanRecurringMock = true;
}

function mockUserDb(uid, userData) {
  const setCalls = [];
  const db = {
    collection(col) {
      assert.equal(col, "users");
      return {
        doc(id) {
          assert.equal(id, uid);
          return {
            async get() {
              return { exists: true, data: () => ({ ...userData }) };
            },
            async set(patch, opts) {
              setCalls.push({ patch, opts });
              Object.assign(userData, patch);
            },
          };
        },
      };
    },
  };
  return { db, setCalls, userData };
}

describe("maskProviderSubscriptionIdForLog", () => {
  it("mascara id longo", () => {
    assert.equal(
      maskProviderSubscriptionIdForLog("2548a2747031404f86a1339ca1e4e3d6"),
      "2548…e3d6",
    );
  });
});

describe("runCancelPlanSubscription — billing desabilitado", () => {
  it("permite cancelamento de assinatura existente", async () => {
    process.env[ENV_KEY] = "false";
    assert.equal(isRecurringPlanBillingEnabled(), false);
    mockMpPutFetch();
    const uid = "user_cancel_1";
    const userData = {
      providerSubscriptionId: "pre_test_active_1",
      currentPlanId: "basic_monthly",
      billingVersion: 2,
      cancelAtPeriodEnd: false,
    };
    const { db, setCalls } = mockUserDb(uid, userData);

    const result = await runCancelPlanSubscription({
      db,
      request: { auth: { uid } },
      token: "fake_token",
    });

    assert.equal(result.ok, true);
    assert.equal(result.cancelAtPeriodEnd, true);
    assert.equal(setCalls.length, 1);
    assert.equal(setCalls[0].patch.cancelAtPeriodEnd, true);
    assert.equal(userData.currentPlanId, "basic_monthly");
    assert.equal(setCalls[0].patch.currentPlanId, undefined);
  });

  it("idempotente quando já cancelada", async () => {
    process.env[ENV_KEY] = "";
    mockMpPutFetch();
    const uid = "user_cancel_2";
    const userData = {
      providerSubscriptionId: "pre_already_cancelled",
      cancelAtPeriodEnd: true,
      currentPlanId: "basic_monthly",
    };
    const { db, setCalls } = mockUserDb(uid, userData);

    const result = await runCancelPlanSubscription({
      db,
      request: { auth: { uid } },
      token: "fake_token",
    });

    assert.equal(result.ok, true);
    assert.equal(result.alreadyCancelled, true);
    assert.equal(setCalls.length, 0);
  });

  it("sem assinatura retorna ASSINATURA_RECORRENTE_NAO_ENCONTRADA", async () => {
    process.env[ENV_KEY] = "false";
    const uid = "user_no_sub";
    const { db } = mockUserDb(uid, { currentPlanId: "basic_monthly" });

    await assert.rejects(
      () =>
        runCancelPlanSubscription({
          db,
          request: { auth: { uid } },
          token: "fake_token",
        }),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.message, "ASSINATURA_RECORRENTE_NAO_ENCONTRADA");
        return true;
      },
    );
  });

  it("exige autenticação (assinatura pertence ao uid autenticado)", async () => {
    const { db } = mockUserDb("other", {
      providerSubscriptionId: "pre_x",
    });

    await assert.rejects(
      () =>
        runCancelPlanSubscription({
          db,
          request: { auth: null },
          token: "fake_token",
        }),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, "unauthenticated");
        return true;
      },
    );
  });
});

describe("runCreatePlanSubscription — billing desabilitado bloqueia nova assinatura", () => {
  it("lança RECURRING_PLAN_BILLING_DISABLED", async () => {
    process.env[ENV_KEY] = "0";
    await assert.rejects(
      () =>
        runCreatePlanSubscription({
          db: {},
          request: { auth: { uid: "u1", token: { email: "a@test.com" } }, data: { plan: "basic_monthly" } },
          token: "t",
          webBase: "https://example.com",
          prices: {},
          planTitleForMp: () => "Plano",
          normalizePlanId: (x) => String(x).trim().toLowerCase(),
        }),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.message, "RECURRING_PLAN_BILLING_DISABLED");
        return true;
      },
    );
  });
});

describe("parseExternalReferenceMpRecurring", () => {
  it("parseia mprec|uid|plan", () => {
    const r = parseExternalReferenceMpRecurring("mprec|abc123|pro_monthly");
    assert.equal(r.uid, "abc123");
    assert.equal(r.canonicalPlanId, "pro_monthly");
  });

  it("retorna null fora do formato", () => {
    assert.equal(parseExternalReferenceMpRecurring("uid|plan"), null);
    assert.equal(parseExternalReferenceMpRecurring(""), null);
  });
});

describe("mergePendingPreapprovalPatch", () => {
  it("sem email não define chave email (não apaga campo existente no merge)", () => {
    const p = mergePendingPreapprovalPatch({
      billingPatch: { provider: "mercado_pago", billingVersion: 2 },
      email: "",
      nowTs: "ts",
    });
    assert.equal(p.email, undefined);
    assert.equal(p.billingSource, "mp_preapproval_pending");
  });

  it("com email define lowercase", () => {
    const p = mergePendingPreapprovalPatch({
      billingPatch: { provider: "mercado_pago" },
      email: " A@Test.COM ",
      nowTs: "ts",
    });
    assert.equal(p.email, "a@test.com");
  });
});

describe("inferPeriodEndFromPreapproval", () => {
  it("usa next_payment_date quando presente", () => {
    const d = new Date("2030-06-15T12:00:00.000Z");
    const end = inferPeriodEndFromPreapproval(
      { next_payment_date: d.toISOString() },
      new Date("2025-01-01"),
    );
    assert.equal(end.toISOString(), d.toISOString());
  });

  it("aproxima por frequency mensal quando não há data", () => {
    const now = new Date("2025-03-10T12:00:00.000Z");
    const end = inferPeriodEndFromPreapproval(
      {
        auto_recurring: { frequency: 1, frequency_type: "months" },
      },
      now,
    );
    assert.equal(end.getMonth(), 3); // abril 0-based -> 3? March +1 = April -> month 3 in 0-index is April
    assert.equal(end.getFullYear(), 2025);
  });
});
