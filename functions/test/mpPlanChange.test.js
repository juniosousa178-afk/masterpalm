/**
 * node --test test/mpPlanChange.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { FieldValue } from "firebase-admin/firestore";

import {
  findPlanChangeRoutingForPreapproval,
  handlePlanChangePreapprovalWebhook,
  isUserEligibleForPlanChange,
  parseExternalReferenceMpPlanChange,
  processPlanChangePaymentWebhook,
  resolveOldPreapprovalIdForPlanChange,
  subscriptionQualifiesAsActiveOldForPlanChange,
} from "../src/mpPlanChange.js";
import { shouldBlockCreateRecurringSubscription } from "../src/mpPlanRecurring.js";

function normPlanIdMinimal(x) {
  return String(x || "").trim().toLowerCase();
}

describe("parseExternalReferenceMpPlanChange", () => {
  it("parseia mpchg|uid|changeId|planId", () => {
    const r = parseExternalReferenceMpPlanChange(
      "mpchg|u1|chg123|intermediate_monthly",
    );
    assert.equal(r.uid, "u1");
    assert.equal(r.changeId, "chg123");
    assert.equal(r.requestedPlanId, "intermediate_monthly");
  });

  it("retorna null se inválido", () => {
    assert.equal(parseExternalReferenceMpPlanChange("mprec|a|b"), null);
    assert.equal(parseExternalReferenceMpPlanChange(""), null);
  });
});

describe("isUserEligibleForPlanChange", () => {
  it("true quando recorrente ativa com fim futuro", () => {
    const future = { toMillis: () => Date.now() + 86_400_000 };
    const ok = isUserEligibleForPlanChange({
      planStatus: "active",
      status: "active",
      billingMode: "recurring",
      providerSubscriptionId: "pre_x",
      currentPeriodEnd: future,
    });
    assert.equal(ok, true);
  });

  it("false sem recorrência ativa", () => {
    assert.equal(
      isUserEligibleForPlanChange({
        billingMode: "recurring",
        providerSubscriptionId: "",
      }),
      false,
    );
  });
});

describe("subscriptionQualifiesAsActiveOldForPlanChange", () => {
  const future = () => ({ toMillis: () => Date.now() + 86_400_000 });

  it("aceita active + approved + recurring + plano + período futuro", () => {
    const q = subscriptionQualifiesAsActiveOldForPlanChange(
      {
        status: "active",
        paymentStatus: "approved",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: future(),
      },
      "basic_monthly",
      normPlanIdMinimal,
      Date.now(),
    );
    assert.equal(q.ok, true);
  });

  it("rejeita abandoned em paymentStatus", () => {
    const q = subscriptionQualifiesAsActiveOldForPlanChange(
      {
        status: "active",
        paymentStatus: "abandoned",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: future(),
      },
      "basic_monthly",
      normPlanIdMinimal,
      Date.now(),
    );
    assert.equal(q.ok, false);
  });
});

function mockDbWithSubscriptions(uid, subDocs) {
  return {
    collection(col) {
      assert.equal(col, "users");
      return {
        doc(id) {
          assert.equal(id, uid);
          return {
            collection(subs) {
              assert.equal(subs, "subscriptions");
              return {
                get() {
                  return Promise.resolve({
                    docs: Object.entries(subDocs).map(([docId, data]) => ({
                      id: docId,
                      data: () => data,
                    })),
                  });
                },
              };
            },
          };
        },
      };
    },
  };
}

describe("resolveOldPreapprovalIdForPlanChange", () => {
  it("com provider contaminado (abandoned), resolve sub active correta no scan", async () => {
    const uid = "user_test_1";
    const idActive = "2548a2747031404f86a1339ca1e4e3d6";
    const idAbandoned = "f11becd1088944cf93c57408e5297d30";
    const future = { toMillis: () => Date.now() + 86_400_000 };
    const subActive = {
      status: "active",
      paymentStatus: "approved",
      billingMode: "recurring",
      planId: "basic_monthly",
      currentPeriodEnd: future,
    };
    const subAbandoned = {
      status: "abandoned",
      paymentStatus: "abandoned",
      billingMode: "recurring",
      planId: "intermediate_monthly",
      currentPeriodEnd: future,
    };
    const ud = {
      currentPlanId: "basic_monthly",
      planStatus: "active",
      status: "active",
      billingMode: "recurring",
      providerSubscriptionId: idAbandoned,
      mercadoPagoPreapprovalId: idAbandoned,
      subscriptionId: idAbandoned,
    };
    const db = mockDbWithSubscriptions(uid, {
      [idActive]: subActive,
      [idAbandoned]: subAbandoned,
    });
    const resolved = await resolveOldPreapprovalIdForPlanChange(
      db,
      uid,
      ud,
      normPlanIdMinimal,
      Date.now(),
    );
    assert.equal(resolved, idActive);
  });

  it("tenta candidatos na ordem e usa o primeiro válido", async () => {
    const uid = "user_test_2";
    const idActive = "aaa111";
    const idBad = "bbb222";
    const future = { toMillis: () => Date.now() + 86_400_000 };
    const db = mockDbWithSubscriptions(uid, {
      [idBad]: {
        status: "pending",
        paymentStatus: "pending",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: future,
      },
      [idActive]: {
        status: "active",
        paymentStatus: "approved",
        billingMode: "recurring",
        planId: "basic_monthly",
        currentPeriodEnd: future,
      },
    });
    const ud = {
      currentPlanId: "basic_monthly",
      providerSubscriptionId: idBad,
      mercadoPagoPreapprovalId: idActive,
    };
    const resolved = await resolveOldPreapprovalIdForPlanChange(
      db,
      uid,
      ud,
      normPlanIdMinimal,
      Date.now(),
    );
    assert.equal(resolved, idActive);
  });
});

function emptyCollectionGroup() {
  return {
    collectionGroup() {
      return {
        where() {
          return {
            limit() {
              return {
                get: async () => ({ docs: [] }),
              };
            },
          };
        },
      };
    },
  };
}

describe("findPlanChangeRoutingForPreapproval", () => {
  it("localiza por plan_change_intents.newPreapprovalId (pending)", async () => {
    const preId = "a93db54f9c144bd295761e5018ba35fc";
    const changeId = "6d7c3374204f47ac9af69a94e8b3e897";
    const uid = "H3be6ett8NZBjzh0nJa35tligDZ2";
    const db = {
      collection(name) {
        assert.equal(name, "plan_change_intents");
        return {
          where() {
            return {
              limit() {
                return {
                  get: async () => ({
                    empty: false,
                    docs: [
                      {
                        id: changeId,
                        data: () => ({
                          uid,
                          newPreapprovalId: preId,
                          status: "pending",
                        }),
                      },
                    ],
                  }),
                };
              },
            };
          },
        };
      },
      ...emptyCollectionGroup(),
    };
    const r = await findPlanChangeRoutingForPreapproval(db, preId);
    assert.equal(r.uid, uid);
    assert.equal(r.changeId, changeId);
    assert.equal(r.source, "plan_change_intents");
  });

  it("fallback users/.../subscriptions com isPlanChange quando intent vazio", async () => {
    const preId = "newpre_fallback_1";
    const uid = "u_sub_fallback";
    const changeId = "chg_fallback_1";
    const db = {
      collection(name) {
        assert.equal(name, "plan_change_intents");
        return {
          where() {
            return {
              limit() {
                return {
                  get: async () => ({ empty: true, docs: [] }),
                };
              },
            };
          },
        };
      },
      collectionGroup(name) {
        assert.equal(name, "subscriptions");
        return {
          where(_fp, _op, val) {
            assert.equal(val, preId);
            return {
              limit() {
                return {
                  get: async () => ({
                    docs: [
                      {
                        id: preId,
                        ref: { path: `users/${uid}/subscriptions/${preId}` },
                        data: () => ({
                          uid,
                          isPlanChange: true,
                          changeId,
                        }),
                      },
                    ],
                  }),
                };
              },
            };
          },
        };
      },
    };
    const r = await findPlanChangeRoutingForPreapproval(db, preId);
    assert.equal(r.uid, uid);
    assert.equal(r.changeId, changeId);
    assert.equal(r.source, "subscriptions_doc");
  });
});

describe("handlePlanChangePreapprovalWebhook", () => {
  it("preapproval cancelled sincroniza falha e limpa pendingPlanChange no user", async () => {
    const preId = "a93db54f9c144bd295761e5018ba35fc";
    const changeId = "6d7c3374204f47ac9af69a94e8b3e897";
    const uid = "u1";
    const extRef = `mpchg|${uid}|${changeId}|pro_monthly`;
    const batchCommits = [];
    const userPath = `users/${uid}`;

    const db = {
      collection(name) {
        if (name === "plan_change_intents") {
          return {
            where() {
              return {
                limit() {
                  return {
                    get: async () => ({
                      empty: false,
                      docs: [
                        {
                          id: changeId,
                          data: () => ({
                            uid,
                            newPreapprovalId: preId,
                            status: "pending",
                          }),
                        },
                      ],
                    }),
                  };
                },
              };
            },
            doc(id) {
              return { _path: `plan_change_intents/${id}` };
            },
          };
        }
        if (name === "users") {
          return {
            doc(id) {
              assert.equal(id, uid);
              return {
                _path: userPath,
                collection(subs) {
                  assert.equal(subs, "subscriptions");
                  return {
                    doc(pid) {
                      assert.equal(pid, preId);
                      return { _path: `${userPath}/subscriptions/${pid}` };
                    },
                  };
                },
              };
            },
          };
        }
        throw new Error(`unexpected collection ${name}`);
      },
      batch() {
        const ops = [];
        const b = {
          set(ref, data, opts) {
            ops.push({ path: ref._path, data, opts });
            return b;
          },
          commit: async () => {
            batchCommits.push(ops);
          },
        };
        return b;
      },
    };

    const r = await handlePlanChangePreapprovalWebhook({
      db,
      token: "tok",
      preapprovalId: preId,
      nowTs: "srvts",
      getPreapproval: async () => ({
        status: "cancelled",
        external_reference: extRef,
      }),
    });
    assert.equal(r.handled, true);
    assert.equal(batchCommits.length, 1);
    const ops = batchCommits[0];
    const userOp = ops.find((o) => o.path === userPath);
    assert.ok(userOp);
    assert.ok(
      userOp.data.pendingPlanChangeId instanceof FieldValue ||
        userOp.data.pendingPlanChangeId?._methodName === "deleteField",
    );
    const subOp = ops.find((o) => o.path === `${userPath}/subscriptions/${preId}`);
    assert.ok(subOp);
    assert.equal(subOp.data.status, "cancelled");
    assert.equal(subOp.data.paymentStatus, "cancelled");
  });

  it("sem rota de troca retorna handled false (mprec segue no planWebhook)", async () => {
    const db = {
      collection(name) {
        assert.equal(name, "plan_change_intents");
        return {
          where() {
            return {
              limit() {
                return {
                  get: async () => ({ empty: true, docs: [] }),
                };
              },
            };
          },
        };
      },
      ...emptyCollectionGroup(),
    };
    const r = await handlePlanChangePreapprovalWebhook({
      db,
      token: "t",
      preapprovalId: "qualquer_preapproval_comum",
      nowTs: "ts",
    });
    assert.equal(r.handled, false);
  });
});

describe("fluxo mpchg payment approved (inalterado no planWebhook)", () => {
  it("processPlanChangePaymentWebhook exportado para ramo payment mpchg", () => {
    assert.equal(typeof processPlanChangePaymentWebhook, "function");
  });
});

describe("createPlanSubscription ainda bloqueia com assinatura ativa", () => {
  it("basic ativo bloqueia intermediate em create comum", () => {
    const future = { toMillis: () => Date.now() + 86_400_000 };
    const r = shouldBlockCreateRecurringSubscription({
      canonicalRequested: "intermediate_monthly",
      userData: {
        currentPlanId: "basic_monthly",
        planStatus: "active",
        status: "active",
        billingMode: "recurring",
        providerSubscriptionId: "pre_1",
        currentPeriodEnd: future,
      },
      normalizePlanId: normPlanIdMinimal,
    });
    assert.equal(r.blocked, true);
  });
});
