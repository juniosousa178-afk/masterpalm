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
  isSchedulerRootCandidate,
  resolveSchedulerRootAuthority,
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

  it("e-mail root só no perfil não protege: process", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        email: ROOT_EMAIL,
      },
      ROOT_EMAIL,
      new Date(),
    );
    assert.equal(d, "process");
  });

  it("isRoot no perfil não protege: process", () => {
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        isRoot: true,
      },
      "any@test.com",
      new Date(),
    );
    assert.equal(d, "process");
  });

  it("skip_protected: root confirmado pelo Auth (verifiedRoot)", () => {
    assert.equal(isRootAccountEmail("masterpalm26@gmail.com"), true);
    const d = classifyExpiredPaidSchedulerDoc(
      {
        currentPlanId: "pro_monthly",
        currentPeriodEnd: ts(PAST),
        email: "masterpalm26@gmail.com",
      },
      "masterpalm26@gmail.com",
      new Date(),
      { verifiedRoot: true },
    );
    assert.equal(d, "skip_protected");
  });

  it("verifiedRoot não altera planos não pagos nem períodos válidos", () => {
    const now = new Date();
    assert.equal(
      classifyExpiredPaidSchedulerDoc({ currentPlanId: "free_limited", currentPeriodEnd: ts(PAST) }, ROOT_EMAIL, now, { verifiedRoot: true }),
      "skip_not_paid",
    );
    assert.equal(
      classifyExpiredPaidSchedulerDoc({ currentPlanId: "pro_monthly", currentPeriodEnd: ts(FUTURE) }, ROOT_EMAIL, now, { verifiedRoot: true }),
      "skip_invalid_period",
    );
  });

  it("admin@masterpalm.com e masterpalm@gmail.com não são root", () => {
    assert.equal(isRootAccountEmail("admin@masterpalm.com"), false);
    assert.equal(isRootAccountEmail("masterpalm@gmail.com"), false);
  });

  it("candidato root: isRoot ou e-mail root no perfil; demais não", () => {
    assert.equal(isSchedulerRootCandidate({ isRoot: true }, "x@test.com"), true);
    assert.equal(isSchedulerRootCandidate({}, ROOT_EMAIL), true);
    assert.equal(isSchedulerRootCandidate({}, " MasterPalm26@Gmail.com "), true);
    assert.equal(isSchedulerRootCandidate({ isRoot: "true" }, "x@test.com"), false);
    assert.equal(isSchedulerRootCandidate({}, "masterpalm@gmail.com"), false);
    assert.equal(isSchedulerRootCandidate({}, ""), false);
  });
});

describe("resolveSchedulerRootAuthority (fail closed)", () => {
  const authOf = (rec) => async () => rec;
  const cases = [
    ["root verificado e ativo", { email: ROOT_EMAIL, emailVerified: true, disabled: false }, true, "auth_verified_root"],
    ["e-mail não verificado", { email: ROOT_EMAIL, emailVerified: false, disabled: false }, false, "auth_email_unverified"],
    ["conta desativada", { email: ROOT_EMAIL, emailVerified: true, disabled: true }, false, "auth_account_disabled"],
    ["disabled ausente", { email: ROOT_EMAIL, emailVerified: true }, false, "auth_account_disabled"],
    ["e-mail diferente", { email: "user@example.com", emailVerified: true, disabled: false }, false, "auth_email_not_root"],
    ["ex-root", { email: "masterpalm@gmail.com", emailVerified: true, disabled: false }, false, "auth_email_not_root"],
    ["sem e-mail", { emailVerified: true, disabled: false }, false, "auth_email_missing"],
    ["registro nulo", null, false, "auth_email_missing"],
  ];
  for (const [name, rec, root, reason] of cases) {
    it(name, async () => {
      const r = await resolveSchedulerRootAuthority({ uid: "u", getAuthUser: authOf(rec) });
      assert.deepEqual(r, { root, reason });
    });
  }

  it("user-not-found → não root", async () => {
    const r = await resolveSchedulerRootAuthority({
      uid: "u",
      getAuthUser: async () => {
        throw Object.assign(new Error("no user"), { code: "auth/user-not-found" });
      },
    });
    assert.deepEqual(r, { root: false, reason: "auth_user_not_found" });
  });

  it("falha transitória do Auth → não root", async () => {
    const r = await resolveSchedulerRootAuthority({
      uid: "u",
      getAuthUser: async () => {
        throw Object.assign(new Error("unavailable"), { code: "auth/internal-error" });
      },
    });
    assert.deepEqual(r, { root: false, reason: "auth_lookup_failed" });
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

describe("runScheduledReconcileBatch — autoridade root via Firebase Auth", () => {
  const NOW = new Date("2025-01-01T00:00:00.000Z");
  const expiredPaid = (extra = {}) => ({
    currentPlanId: "pro_monthly",
    currentPeriodEnd: ts(PAST),
    ...extra,
  });
  const AUTH = {
    root: { email: ROOT_EMAIL, emailVerified: true, disabled: false },
    rootUnverified: { email: ROOT_EMAIL, emailVerified: false, disabled: false },
    rootDisabled: { email: ROOT_EMAIL, emailVerified: true, disabled: true },
    ordinary: { email: "user@example.com", emailVerified: true, disabled: false },
    formerRoot: { email: "masterpalm@gmail.com", emailVerified: false, disabled: false },
  };

  async function run(profiles, authByUid) {
    const store = Object.fromEntries(Object.entries(profiles).map(([k, v]) => [k, { ...v }]));
    const lookups = [];
    const computed = [];
    const stats = await runScheduledReconcileBatch({
      db: createMockDb(store),
      now: NOW,
      snap: makeSnap(Object.entries(profiles).map(([uid, d]) => makeDoc(uid, { ...d }))),
      getAuthUser: async (uid) => {
        lookups.push(uid);
        const rec = authByUid[uid];
        if (rec instanceof Error) throw rec;
        if (rec === undefined) {
          throw Object.assign(new Error("no user"), { code: "auth/user-not-found" });
        }
        return rec;
      },
      computePlanStateImpl: async ({ uid }) => {
        computed.push(uid);
        store[uid] = { ...store[uid], currentPlanId: "free_limited", currentPeriodEnd: null };
      },
    });
    return { stats, store, lookups, computed };
  }

  it("spoof: Auth comum + e-mail root no perfil → expira normalmente", async () => {
    const r = await run({ spoof: expiredPaid({ email: ROOT_EMAIL }) }, { spoof: AUTH.ordinary });
    assert.deepEqual(r.lookups, ["spoof"]);
    assert.deepEqual(r.computed, ["spoof"]);
    assert.equal(r.store.spoof.currentPlanId, "free_limited");
    assert.equal(r.stats.skippedProtected, 0);
    assert.equal(r.stats.rootCandidatesRejected, 1);
    assert.equal(r.stats.downgradedToFreeLimited, 1);
  });

  it("root canônico com e-mail não verificado → não isento", async () => {
    const r = await run({ u: expiredPaid({ email: ROOT_EMAIL }) }, { u: AUTH.rootUnverified });
    assert.deepEqual(r.computed, ["u"]);
    assert.equal(r.stats.skippedProtected, 0);
  });

  it("root canônico desativado → não isento", async () => {
    const r = await run({ u: expiredPaid({ email: ROOT_EMAIL }) }, { u: AUTH.rootDisabled });
    assert.deepEqual(r.computed, ["u"]);
    assert.equal(r.stats.skippedProtected, 0);
  });

  it("root canônico verificado e ativo → isenção preservada", async () => {
    const r = await run({ root: expiredPaid({ email: ROOT_EMAIL }) }, { root: AUTH.root });
    assert.deepEqual(r.lookups, ["root"]);
    assert.deepEqual(r.computed, []);
    assert.equal(r.stats.skippedProtected, 1);
    assert.equal(r.store.root.currentPlanId, "pro_monthly");
  });

  it("isRoot desatualizado (ex-root) → não isento", async () => {
    const r = await run(
      { former: expiredPaid({ email: "masterpalm@gmail.com", isRoot: true }) },
      { former: AUTH.formerRoot },
    );
    assert.deepEqual(r.lookups, ["former"]);
    assert.deepEqual(r.computed, ["former"]);
  });

  it("isRoot no perfil com Auth root verificado → isento (Auth é a autoridade)", async () => {
    const r = await run({ u: expiredPaid({ isRoot: true }) }, { u: AUTH.root });
    assert.equal(r.stats.skippedProtected, 1);
    assert.deepEqual(r.computed, []);
  });

  it("candidato sem usuário no Auth → expira normalmente", async () => {
    const r = await run({ ghost: expiredPaid({ email: ROOT_EMAIL }) }, {});
    assert.deepEqual(r.computed, ["ghost"]);
    assert.equal(r.stats.rootCandidatesRejected, 1);
  });

  it("falha do Auth em um candidato não aborta o lote e não mantém plano vencido", async () => {
    const r = await run(
      {
        flaky: expiredPaid({ email: ROOT_EMAIL }),
        normal: expiredPaid({ email: "n@test.com" }),
        root: expiredPaid({ email: ROOT_EMAIL }),
      },
      { flaky: new Error("auth unavailable"), root: AUTH.root },
    );
    assert.deepEqual(r.computed, ["flaky", "normal"]);
    assert.equal(r.store.flaky.currentPlanId, "free_limited");
    assert.equal(r.store.normal.currentPlanId, "free_limited");
    assert.equal(r.store.root.currentPlanId, "pro_monthly");
    assert.equal(r.stats.failed, 0);
    assert.equal(r.stats.evaluated, 3);
  });

  it("lote de usuários normais: zero consultas ao Auth, comportamento inalterado", async () => {
    const r = await run(
      {
        expired: expiredPaid({ email: "a@test.com" }),
        active: { currentPlanId: "pro_monthly", currentPeriodEnd: ts(FUTURE), email: "b@test.com" },
        free: { currentPlanId: "free_limited", currentPeriodEnd: ts(PAST), email: "c@test.com" },
        lifetime: { currentPlanId: "lifetime", currentPeriodEnd: ts(PAST), email: "d@test.com" },
        granted: expiredPaid({ email: "e@test.com", manual_grant: { type: "lifetime" } }),
        override: expiredPaid({ email: "f@test.com", manualOverride: { enabled: true, planId: "pro_monthly" } }),
        cancelled: expiredPaid({ email: "g@test.com", cancelAtPeriodEnd: true }),
        recentPayment: { currentPlanId: "pro_monthly", currentPeriodEnd: ts(FUTURE), planLastPaymentId: "p1", email: "h@test.com" },
        missingProfile: {},
      },
      {},
    );
    assert.deepEqual(r.lookups, []);
    assert.deepEqual(r.computed.sort(), ["cancelled", "expired"]);
    assert.equal(r.stats.skippedProtected, 2);
    assert.equal(r.stats.skippedNotPaidPlan, 5);
    assert.equal(r.stats.rootAuthLookups, 0);
    assert.equal(r.store.granted.currentPlanId, "pro_monthly");
    assert.equal(r.store.override.currentPlanId, "pro_monthly");
    assert.equal(r.store.active.currentPlanId, "pro_monthly");
  });

  it("candidato já protegido por grant/override ou fora do período: sem consulta ao Auth", async () => {
    const r = await run(
      {
        grantRootEmail: expiredPaid({ email: ROOT_EMAIL, manual_grant: { type: "lifetime" } }),
        activeRootEmail: { currentPlanId: "pro_monthly", currentPeriodEnd: ts(FUTURE), email: ROOT_EMAIL },
        freeRootFlag: { currentPlanId: "free_limited", currentPeriodEnd: ts(PAST), isRoot: true },
      },
      {},
    );
    assert.deepEqual(r.lookups, []);
    assert.deepEqual(r.computed, []);
  });

  it("uma consulta ao Auth por candidato root", async () => {
    const r = await run(
      {
        c1: expiredPaid({ email: ROOT_EMAIL }),
        c2: expiredPaid({ isRoot: true }),
        n1: expiredPaid({ email: "x@test.com" }),
        n2: expiredPaid({ email: "y@test.com" }),
      },
      { c1: AUTH.ordinary, c2: AUTH.root },
    );
    assert.deepEqual(r.lookups, ["c1", "c2"]);
    assert.equal(r.stats.rootAuthLookups, 2);
  });
});
