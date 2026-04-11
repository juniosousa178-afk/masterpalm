/**
 * Testes do núcleo do scheduler scheduledReconcileExpiredPaidPlans (sem emulator).
 * node --test (Node 20+)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { ROOT_EMAIL } from "../ensureUserPlan.js";
import { isRootAccountEmail } from "../src/rootAccounts.js";
import {
  classifyExpiredPaidSchedulerDoc,
  runScheduledReconcileBatch,
} from "../src/scheduledExpiredPaidReconcileBatch.js";

const PAST = new Date("2020-01-01T12:00:00.000Z");
const FUTURE = new Date("2038-01-01T12:00:00.000Z");

function ts(d) {
  return { toDate: () => d };
}

function makeDoc(uid, data) {
  return {
    id: uid,
    data: () => data,
  };
}

function makeSnap(docs) {
  return { size: docs.length, docs };
}

function createMockDb(store) {
  return {
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(uid) {
          return {
            async get() {
              const d = store[uid];
              return {
                exists: d != null,
                data: () => (d == null ? {} : { ...d }),
              };
            },
          };
        },
      };
    },
  };
}

describe("classifyExpiredPaidSchedulerDoc", () => {
  it("process: pago canônico vencível", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        email: "u@test.com",
      },
      "u@test.com",
      new Date("2025-06-01T00:00:00.000Z"),
    );
    assert.equal(d, "process");
  });

  it("skip_not_paid: free_limited", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "free_limited",
        currentPeriodEnd: ts(PAST),
      },
      "x@test.com",
      new Date(),
    );
    assert.equal(d, "skip_not_paid");
  });

  it("skip_not_paid: plano legado fora dos pagos canônicos", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "plano_desconhecido_xyz",
        currentPeriodEnd: ts(PAST),
      },
      "x@test.com",
      new Date(),
    );
    assert.equal(d, "skip_not_paid");
  });

  it("skip_invalid_period: sem currentPeriodEnd", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      { currentPlanId: "pro_monthly", email: "a@b.com" },
      "a@b.com",
      new Date(),
    );
    assert.equal(d, "skip_invalid_period");
  });

  it("skip_invalid_period: currentPeriodEnd no futuro", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(FUTURE),
      },
      "a@b.com",
      new Date(),
    );
    assert.equal(d, "skip_invalid_period");
  });

  it("skip_protected: manualOverride.enabled", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        manualOverride: { enabled: true, planId: "pro_monthly" },
      },
      "a@b.com",
      new Date(),
    );
    assert.equal(d, "skip_protected");
  });

  it("skip_protected: manual_grant lifetime", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        manual_grant: { type: "lifetime" },
      },
      "a@b.com",
      new Date(),
    );
    assert.equal(d, "skip_protected");
  });

  it("skip_protected: root email backend", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        email: ROOT_EMAIL,
      },
      ROOT_EMAIL,
      new Date(),
    );
    assert.equal(d, "skip_protected");
  });

  it("skip_protected: qualquer email em ROOT_ACCOUNT_EMAILS", () => {
    assert.equal(isRootAccountEmail("admin@masterpalm.com"), true);
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        email: "admin@masterpalm.com",
      },
      "admin@masterpalm.com",
      new Date(),
    );
    assert.equal(d, "skip_protected");
  });

  it("skip_protected: isRoot flag", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        isRoot: true,
      },
      "any@test.com",
      new Date(),
    );
    assert.equal(d, "skip_protected");
  });
});

describe("runScheduledReconcileBatch", () => {
  it("downgrade: mock compute aplica free_limited e contadores", async () => {
    const store = {
      u1: {
        email: "p@test.com",
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
      },
    };
    const db = createMockDb(store);

    const stats = await runScheduledReconcileBatch({
      db,
      now: new Date("2025-01-01T00:00:00.000Z"),
      snap: makeSnap([makeDoc("u1", { ...store.u1 })]),
      computePlanStateImpl: async ({ uid }) => {
        store[uid] = {
          ...store[uid],
          currentPlanId: "free_limited",
          currentPeriodEnd: null,
          cancelAtPeriodEnd: false,
        };
      },
    });

    assert.equal(stats.evaluated, 1);
    assert.equal(stats.reconcileRuns, 1);
    assert.equal(stats.downgradedToFreeLimited, 1);
    assert.equal(stats.skippedNotPaidPlan, 0);
    assert.equal(stats.skippedProtected, 0);
    assert.equal(stats.failed, 0);
    assert.equal(stats.evt, "scheduled_expired_paid_plan_reconcile");
    assert.equal(store.u1.currentPlanId, "free_limited");
    assert.equal(store.u1.cancelAtPeriodEnd, false);
  });

  it("manualOverride: não chama computePlanState", async () => {
    let calls = 0;
    const store = {
      u1: {
        email: "p@test.com",
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        manualOverride: { enabled: true, planId: "pro_monthly" },
      },
    };
    const stats = await runScheduledReconcileBatch({
      db: createMockDb(store),
      now: new Date(),
      snap: makeSnap([makeDoc("u1", { ...store.u1 })]),
      computePlanStateImpl: async () => {
        calls++;
      },
    });
    assert.equal(calls, 0);
    assert.equal(stats.skippedProtected, 1);
    assert.equal(stats.reconcileRuns, 0);
    assert.equal(stats.downgradedToFreeLimited, 0);
  });

  it("idempotência: segundo passe com doc já free_limited não downgrada", async () => {
    const store = {
      u1: {
        email: "p@test.com",
        currentPlanId: "free_limited",
        currentPeriodEnd: null,
      },
    };
    let calls = 0;
    const stats = await runScheduledReconcileBatch({
      db: createMockDb(store),
      now: new Date(),
      snap: makeSnap([makeDoc("u1", { ...store.u1 })]),
      computePlanStateImpl: async () => {
        calls++;
      },
    });
    assert.equal(calls, 0);
    assert.equal(stats.skippedNotPaidPlan, 1);
    assert.equal(stats.downgradedToFreeLimited, 0);
  });

  it("idempotência: duas passagens — segunda com estado já migrado", async () => {
    const store = {
      u1: {
        email: "p@test.com",
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
      },
    };
    const db = createMockDb(store);
    const now = new Date("2025-01-01T00:00:00.000Z");
    const impl = async ({ uid }) => {
      store[uid] = {
        ...store[uid],
        currentPlanId: "free_limited",
        currentPeriodEnd: null,
        cancelAtPeriodEnd: false,
      };
    };

    const s1 = await runScheduledReconcileBatch({
      db,
      now,
      snap: makeSnap([
        makeDoc("u1", {
          email: "p@test.com",
          currentPlanId: "pro_monthly",
          currentPeriodEnd: ts(PAST),
        }),
      ]),
      computePlanStateImpl: impl,
    });
    assert.equal(s1.downgradedToFreeLimited, 1);

    const s2 = await runScheduledReconcileBatch({
      db,
      now,
      snap: makeSnap([
        makeDoc("u1", {
          email: "p@test.com",
          currentPlanId: "free_limited",
          currentPeriodEnd: null,
        }),
      ]),
      computePlanStateImpl: impl,
    });
    assert.equal(s2.downgradedToFreeLimited, 0);
    assert.equal(s2.skippedNotPaidPlan, 1);
  });

  it("documento inválido em um lote não aborta os demais", async () => {
    const store = {
      u1: {
        email: "ok@test.com",
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
      },
    };
    const db = createMockDb(store);
    const stats = await runScheduledReconcileBatch({
      db,
      now: new Date(),
      snap: makeSnap([
        makeDoc("bad", { currentPlanId: "pro_monthly", currentPeriodEnd: ts(PAST) }),
        makeDoc("u1", { ...store.u1 }),
      ]),
      computePlanStateImpl: async ({ uid }) => {
        if (uid === "bad") throw new Error("simulated_failure");
        store[uid] = {
          ...store[uid],
          currentPlanId: "free_limited",
          cancelAtPeriodEnd: false,
        };
      },
    });
    assert.equal(stats.failed, 1);
    assert.equal(stats.downgradedToFreeLimited, 1);
    assert.equal(store.u1.currentPlanId, "free_limited");
  });
});
