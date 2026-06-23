/**
 * node --test test/masterPlanAdmin.test.js
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

import { HttpsError } from "firebase-functions/v2/https";

import {
  assertMasterPlanAdmin,
  MASTER_PLAN_ADMIN_EMAIL,
  runMasterGetPlanAccessSummary,
  runMasterGetUserPlanDetails,
  runMasterListUsersPlanAccess,
} from "../src/masterPlanAdmin.js";

function authRequest(email, uid = "caller_uid") {
  return {
    auth: {
      uid,
      token: { email },
    },
    data: {},
  };
}

function makeMockDb({ users = {}, subscriptions = {} } = {}) {
  const writes = [];

  function docRef(path) {
    const parts = path.split("/");
    const isSub = parts.length === 4;
    const uid = parts[1];
    const subId = isSub ? parts[3] : null;

    return {
      path,
      async get() {
        if (isSub) {
          const sub = subscriptions[uid]?.[subId];
          return { exists: !!sub, data: () => sub, id: subId };
        }
        const u = users[uid];
        return { exists: !!u, data: () => u, id: uid };
      },
      async set(data, opts) {
        writes.push({ op: "set", path, data, opts });
      },
      collection(name) {
        assert.equal(name, "subscriptions");
        const subMap = subscriptions[uid] || {};
        const docs = Object.entries(subMap).map(([id, data]) => ({
          id,
          data: () => data,
        }));
        return {
          orderBy(field, dir) {
            return {
              limit(n) {
                return {
                  async get() {
                    return { docs: docs.slice(0, n) };
                  },
                };
              },
            };
          },
          limit(n) {
            return {
              async get() {
                return { docs: docs.slice(0, n) };
              },
            };
          },
        };
      },
    };
  }

  const db = {
    writes,
    collection(name) {
      assert.equal(name, "users");
      const ids = Object.keys(users).sort();
      const colApi = {
        doc(id) {
          return docRef(`users/${id}`);
        },
        count() {
          return {
            async get() {
              return { data: () => ({ count: ids.length }) };
            },
          };
        },
        orderBy(field) {
          assert.equal(field, "__name__");
          return {
            limit(n) {
              return {
                startAfter(token) {
                  const startIdx = ids.indexOf(token);
                  const slice = startIdx >= 0 ? ids.slice(startIdx + 1) : ids;
                  return {
                    async get() {
                      const picked = slice.slice(0, n);
                      return {
                        docs: picked.map((id) => ({
                          id,
                          data: () => users[id],
                        })),
                      };
                    },
                  };
                },
                async get() {
                  const picked = ids.slice(0, n);
                  return {
                    docs: picked.map((id) => ({
                      id,
                      data: () => users[id],
                    })),
                  };
                },
              };
            },
          };
        },
        where(field, op, value) {
          const filtered = ids.filter((id) => {
            const u = users[id];
            if (field === "cancelAtPeriodEnd") return u.cancelAtPeriodEnd === value;
            if (field === "currentPlanId") return u.currentPlanId === value;
            if (field === "manualOverride.enabled") {
              return u.manualOverride?.enabled === value;
            }
            return false;
          });
          return {
            count() {
              return {
                async get() {
                  return { data: () => ({ count: filtered.length }) };
                },
              };
            },
          };
        },
      };
      return colApi;
    },
  };

  return db;
}

describe("assertMasterPlanAdmin", () => {
  it("1. sem autenticação → unauthenticated", () => {
    assert.throws(
      () => assertMasterPlanAdmin({ auth: null }),
      (e) => e instanceof HttpsError && e.code === "unauthenticated",
    );
  });

  it("2. usuário comum → permission-denied", () => {
    assert.throws(
      () => assertMasterPlanAdmin(authRequest("cliente@loja.com")),
      (e) => e instanceof HttpsError && e.code === "permission-denied",
    );
  });

  it("3. masterpalm@gmail.com → permission-denied", () => {
    assert.throws(
      () => assertMasterPlanAdmin(authRequest("masterpalm@gmail.com")),
      (e) => e instanceof HttpsError && e.code === "permission-denied",
    );
  });

  it("4. admin@masterpalm.com → permission-denied", () => {
    assert.throws(
      () => assertMasterPlanAdmin(authRequest("admin@masterpalm.com")),
      (e) => e instanceof HttpsError && e.code === "permission-denied",
    );
  });

  it("5. masterpalm26@gmail.com + root → permitido", () => {
    const r = assertMasterPlanAdmin(authRequest(MASTER_PLAN_ADMIN_EMAIL));
    assert.equal(r.email, MASTER_PLAN_ADMIN_EMAIL);
    assert.equal(r.uid, "caller_uid");
  });
});

describe("runMasterListUsersPlanAccess", () => {
  it("18. lista usa paginação estável", async () => {
    const db = makeMockDb({
      users: {
        a_uid: {
          email: "a@test.com",
          currentPlanId: "basic_monthly",
          currentPeriodEnd: new Date(Date.now() + 86400000),
        },
        b_uid: {
          email: "b@test.com",
          currentPlanId: "free_limited",
        },
        c_uid: {
          email: "c@test.com",
          currentPlanId: "pro_monthly",
          currentPeriodEnd: new Date(Date.now() + 86400000),
        },
      },
    });

    const page1 = await runMasterListUsersPlanAccess({
      db,
      request: {
        ...authRequest(MASTER_PLAN_ADMIN_EMAIL),
        data: { pageSize: 2 },
      },
    });
    assert.equal(page1.users.length, 2);
    assert.equal(page1.hasMore, true);
    assert.equal(page1.nextPageToken, "b_uid");

    const page2 = await runMasterListUsersPlanAccess({
      db,
      request: {
        ...authRequest(MASTER_PLAN_ADMIN_EMAIL),
        data: { pageSize: 2, pageToken: page1.nextPageToken },
      },
    });
    assert.equal(page2.users.length, 1);
    assert.equal(page2.hasMore, false);
    assert.equal(db.writes.length, 0);
  });

  it("19. pageSize acima de 50 é limitado a 50", async () => {
    const users = {};
    for (let i = 0; i < 55; i++) {
      users[`u${i}`] = { email: `u${i}@test.com`, currentPlanId: "free_limited" };
    }
    const db = makeMockDb({ users });
    const r = await runMasterListUsersPlanAccess({
      db,
      request: {
        ...authRequest(MASTER_PLAN_ADMIN_EMAIL),
        data: { pageSize: 200 },
      },
    });
    assert.equal(r.pageSize, 50);
    assert.equal(r.users.length, 50);
  });

  it("22. lista retorna e-mail mascarado", async () => {
    const db = makeMockDb({
      users: {
        x_uid: {
          email: "cliente@exemplo.com",
          currentPlanId: "free_limited",
        },
      },
    });
    const r = await runMasterListUsersPlanAccess({
      db,
      request: authRequest(MASTER_PLAN_ADMIN_EMAIL),
    });
    assert.ok(r.users[0].emailMasked.includes("***"));
    assert.ok(!r.users[0].emailMasked.includes("cliente@exemplo.com"));
  });
});

describe("runMasterGetUserPlanDetails", () => {
  it("20. usuário inexistente → not-found", async () => {
    const db = makeMockDb({ users: {} });
    await assert.rejects(
      () =>
        runMasterGetUserPlanDetails({
          db,
          request: {
            ...authRequest(MASTER_PLAN_ADMIN_EMAIL),
            data: { targetUid: "missing" },
          },
        }),
      (e) => e instanceof HttpsError && e.code === "not-found",
    );
  });

  it("21. detalhe não retorna providerSubscriptionId completo", async () => {
    const longId = "2548a2747031404f86a1339ca1e4e3d6";
    const db = makeMockDb({
      users: {
        t_uid: {
          email: "target@test.com",
          currentPlanId: "basic_monthly",
          currentPeriodEnd: new Date(Date.now() + 86400000),
          providerSubscriptionId: longId,
          billingSource: "mp_subscription",
        },
      },
      subscriptions: {
        t_uid: {
          sub1: {
            planId: "basic_monthly",
            status: "active",
            preapprovalId: longId,
            createdAt: new Date(),
          },
        },
      },
    });

    const r = await runMasterGetUserPlanDetails({
      db,
      request: {
        ...authRequest(MASTER_PLAN_ADMIN_EMAIL),
        data: { targetUid: "t_uid" },
      },
    });

    assert.equal(r.user.email, "target@test.com");
    assert.notEqual(r.planAccess.subscription.maskedProviderSubscriptionId, longId);
    assert.ok(
      r.subscriptions.every(
        (s) => !s.maskedProviderSubscriptionId || !s.maskedProviderSubscriptionId.includes(longId),
      ),
    );
    const serialized = JSON.stringify(r);
    assert.ok(!serialized.includes(longId));
    assert.equal(db.writes.length, 0);
  });
});

describe("runMasterGetPlanAccessSummary", () => {
  it("24. métrica manual_grant retorna pendingImplementation", async () => {
    const db = makeMockDb({
      users: {
        u1: { currentPlanId: "basic_monthly", cancelAtPeriodEnd: true },
        u2: { currentPlanId: "free_limited", manualOverride: { enabled: true } },
      },
    });
    const r = await runMasterGetPlanAccessSummary({
      db,
      request: authRequest(MASTER_PLAN_ADMIN_EMAIL),
    });
    assert.equal(r.ok, true);
    assert.equal(r.totalCanonicalUsers, 2);
    assert.equal(r.totalRenewalCancelled, 1);
    assert.equal(r.totalWithManualGrantLegacy.pendingImplementation, true);
    assert.equal(db.writes.length, 0);
  });
});

describe("callables — sem escrita", () => {
  it("23. nenhuma Callable cria, atualiza ou remove documento", async () => {
    const db = makeMockDb({
      users: {
        z_uid: {
          email: "z@test.com",
          currentPlanId: "basic_monthly",
          currentPeriodEnd: new Date(Date.now() + 86400000),
        },
      },
    });
    const req = authRequest(MASTER_PLAN_ADMIN_EMAIL);

    await runMasterListUsersPlanAccess({ db, request: req });
    await runMasterGetUserPlanDetails({
      db,
      request: { ...req, data: { targetUid: "z_uid" } },
    });
    await runMasterGetPlanAccessSummary({ db, request: req });

    assert.equal(db.writes.length, 0);
  });
});
