/**
 * node --test test/masterPlanCourtesy.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { HttpsError } from "firebase-functions/v2/https";

import {
  MASTER_PLAN_ADMIN_EMAIL,
  runMasterGrantCourtesyAccess,
  runMasterUpdateCourtesyAccess,
  runMasterRevokeCourtesyAccess,
  runMasterListPlanAuditActions,
  runGetMyPlanEffectiveAccess,
  validateRequestId,
  buildAuditActionIdentity,
} from "../src/masterPlanAdmin.js";
import { makeMasterPlanMockDb } from "./mockMasterPlanDb.js";

const REQ = "req12345678901234";

function serializeTransactions(db) {
  let chain = Promise.resolve();
  const orig = db.runTransaction.bind(db);
  db.runTransaction = (fn) => {
    const run = () => orig(fn);
    const next = chain.then(run, run);
    chain = next.catch(() => {});
    return next;
  };
  return db;
}

function masterReq(data = {}, uid = "master_uid") {
  return {
    auth: { uid, token: { email: MASTER_PLAN_ADMIN_EMAIL } },
    data,
  };
}

function targetUser() {
  return {
    email: "cliente@loja.com",
    currentPlanId: "free_limited",
    billingVersion: 1,
    billingSource: null,
    providerSubscriptionId: null,
    cancelAtPeriodEnd: false,
  };
}

describe("validateRequestId / buildAuditActionIdentity", () => {
  it("1. requestId válido é aceito", () => {
    assert.equal(validateRequestId(REQ), REQ);
  });

  it("2. requestId menor que 16 caracteres é rejeitado", () => {
    assert.throws(
      () => validateRequestId("short"),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
  });

  it("3. requestId maior que 128 caracteres é rejeitado", () => {
    assert.throws(
      () => validateRequestId(`a${"b".repeat(128)}`),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
  });

  it("4. requestId com caracteres inválidos é rejeitado", () => {
    for (const bad of [
      "req/with/slash1234",
      "req space12345678",
      "req.dot123456789",
      "req:colon1234567",
    ]) {
      assert.throws(
        () => validateRequestId(bad),
        (e) => e instanceof HttpsError && e.code === "invalid-argument",
        `expected reject for ${bad}`,
      );
    }
  });

  it("5. actionId não contém requestId bruto", () => {
    const { actionId } = buildAuditActionIdentity(
      "actor",
      "target",
      "grant_courtesy",
      REQ,
    );
    assert.ok(!actionId.includes(REQ));
    assert.match(actionId, /^master_plan_[a-f0-9]{64}$/);
  });

  it("6. actionId é determinístico para mesma ação", () => {
    const a = buildAuditActionIdentity("a", "t", "grant_courtesy", REQ);
    const b = buildAuditActionIdentity("a", "t", "grant_courtesy", REQ);
    assert.equal(a.actionId, b.actionId);
    assert.equal(a.requestFingerprint, b.requestFingerprint);
  });

  it("7. requestFingerprint é SHA-256 válido", () => {
    const { requestFingerprint } = buildAuditActionIdentity(
      "a",
      "t",
      "grant_courtesy",
      REQ,
    );
    assert.match(requestFingerprint, /^[a-f0-9]{64}$/);
  });
});

describe("masterGrantCourtesyAccess", () => {
  it("14. grant não altera currentPlanId nem billing", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    await runMasterGrantCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        planId: "intermediate_monthly",
        type: "temporary",
        expiresAt: expires,
        reason: "Cortesia teste",
        requestId: REQ,
      }),
    });
    const u = db.state.users.t1;
    assert.equal(u.currentPlanId, "free_limited");
    assert.equal(u.billingVersion, 1);
    assert.equal(u.billingSource, null);
    assert.equal(u.providerSubscriptionId, null);
    assert.equal(u.cancelAtPeriodEnd, false);
  });

  it("8. repetição sequencial com mesmo requestId não cria segunda auditoria", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    const payload = {
      targetUid: "t1",
      planId: "basic_monthly",
      type: "temporary",
      expiresAt: expires,
      reason: "Idempotência",
      requestId: REQ,
    };
    const r1 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    const writesAfterFirst = db.writes.length;
    const r2 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    assert.equal(db.writes.length, writesAfterFirst);
    assert.equal(Object.keys(db.state.auditActions).length, 1);
    assert.equal(r2.idempotentReplay, true);
    assert.equal(r1.planAccess.effectivePlanId, r2.planAccess.effectivePlanId);
  });

  it("9. duas chamadas concorrentes com mesmo requestId criam uma única auditoria", async () => {
    const db = serializeTransactions(
      makeMasterPlanMockDb({
        users: { t1: targetUser() },
      }),
    );
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    const payload = {
      targetUid: "t1",
      planId: "basic_monthly",
      type: "temporary",
      expiresAt: expires,
      reason: "Concorrência",
      requestId: "req999999999999999",
    };
    const [r1, r2] = await Promise.all([
      runMasterGrantCourtesyAccess({ db, request: masterReq(payload) }),
      runMasterGrantCourtesyAccess({ db, request: masterReq(payload) }),
    ]);
    assert.equal(Object.keys(db.state.auditActions).length, 1);
    assert.equal(r1.planAccess.effectivePlanId, r2.planAccess.effectivePlanId);
  });

  it("10. repetição retorna resultPayload original", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    const payload = {
      targetUid: "t1",
      planId: "intermediate_monthly",
      type: "temporary",
      expiresAt: expires,
      reason: "Replay",
      requestId: "req888888888888888",
    };
    const r1 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    const r2 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    assert.deepEqual(r2.planAccess, r1.planAccess);
    assert.equal(r2.idempotentReplay, true);
  });

  it("23. mesma requestId não duplica grant/auditoria", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    const payload = {
      targetUid: "t1",
      planId: "basic_monthly",
      type: "temporary",
      expiresAt: expires,
      reason: "Idempotência",
      requestId: REQ,
    };
    const r1 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    const writesAfterFirst = db.writes.length;
    const r2 = await runMasterGrantCourtesyAccess({ db, request: masterReq(payload) });
    assert.equal(db.writes.length, writesAfterFirst);
    assert.equal(Object.keys(db.state.auditActions).length, 1);
    assert.equal(r1.planAccess.effectivePlanId, r2.planAccess.effectivePlanId);
  });

  it("25. audit contém before/after sem providerSubscriptionId completo", async () => {
    const longId = "2548a2747031404f86a1339ca1e4e3d6";
    const db = makeMasterPlanMockDb({
      users: {
        t1: {
          ...targetUser(),
          providerSubscriptionId: longId,
          billingSource: "mp_subscription",
        },
      },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    await runMasterGrantCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        planId: "pro_monthly",
        type: "temporary",
        expiresAt: expires,
        reason: "Auditoria",
        requestId: REQ,
      }),
    });
    const audit = Object.values(db.state.auditActions)[0];
    assert.ok(audit.beforeSnapshot);
    assert.ok(audit.afterSnapshot);
    assert.ok(audit.requestFingerprint);
    assert.equal(audit.requestId, undefined);
    const serialized = JSON.stringify(audit);
    assert.ok(!serialized.includes(REQ));
    assert.ok(!serialized.includes(longId));
  });

  it("11. resultPayload não contém providerSubscriptionId completo", async () => {
    const longId = "2548a2747031404f86a1339ca1e4e3d6";
    const db = makeMasterPlanMockDb({
      users: {
        t1: {
          ...targetUser(),
          providerSubscriptionId: longId,
        },
      },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    const r = await runMasterGrantCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        planId: "pro_monthly",
        type: "temporary",
        expiresAt: expires,
        reason: "Payload",
        requestId: "req777777777777777",
      }),
    });
    assert.ok(!JSON.stringify(r.planAccess).includes(longId));
  });

  it("12. audit não contém token ou dados sensíveis", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
    });
    const expires = new Date(Date.now() + 7 * 86400000).toISOString();
    await runMasterGrantCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        planId: "basic_monthly",
        type: "temporary",
        expiresAt: expires,
        reason: "Seguro",
        requestId: "req666666666666666",
      }),
    });
    const audit = Object.values(db.state.auditActions)[0];
    const serialized = JSON.stringify(audit).toLowerCase();
    for (const forbidden of ["cvv", "token", "card", "secret", "requestid"]) {
      assert.ok(!serialized.includes(forbidden), `found ${forbidden}`);
    }
  });
});

describe("masterUpdateCourtesyAccess", () => {
  it("19. update só estende cortesia temporária", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
      courtesy: {
        t1: {
          active: true,
          type: "temporary",
          planId: "intermediate_monthly",
          expiresAt: new Date(Date.now() + 3 * 86400000),
        },
      },
    });
    const newEnd = new Date(Date.now() + 10 * 86400000);
    await runMasterUpdateCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        expiresAt: newEnd.toISOString(),
        reason: "Estender",
        requestId: REQ,
      }),
    });
    assert.ok(db.state.courtesy.t1.expiresAt >= newEnd);
  });

  it("20. update não reduz validade", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
      courtesy: {
        t1: {
          active: true,
          type: "temporary",
          planId: "basic_monthly",
          expiresAt: new Date(Date.now() + 10 * 86400000),
        },
      },
    });
    await assert.rejects(
      () =>
        runMasterUpdateCourtesyAccess({
          db,
          request: masterReq({
            targetUid: "t1",
            expiresAt: new Date(Date.now() + 2 * 86400000).toISOString(),
            reason: "Tentativa reduzir",
            requestId: REQ,
          }),
        }),
      (e) => e instanceof HttpsError,
    );
  });
});

describe("masterRevokeCourtesyAccess", () => {
  it("21. revoke faz soft revoke", async () => {
    const db = makeMasterPlanMockDb({
      users: { t1: targetUser() },
      courtesy: {
        t1: {
          active: true,
          type: "temporary",
          planId: "pro_monthly",
          expiresAt: new Date(Date.now() + 5 * 86400000),
        },
      },
    });
    const r = await runMasterRevokeCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        reason: "Revogar teste",
        requestId: REQ,
      }),
    });
    assert.equal(db.state.courtesy.t1.active, false);
    assert.ok(db.state.courtesy.t1.revokedAt);
    assert.equal(r.planAccess.accessSource, "free_limited");
  });

  it("22. revoke retorna ao plano contratado real", async () => {
    const db = makeMasterPlanMockDb({
      users: {
        t1: {
          ...targetUser(),
          currentPlanId: "basic_monthly",
          currentPeriodEnd: new Date(Date.now() + 20 * 86400000),
        },
      },
      courtesy: {
        t1: {
          active: true,
          type: "temporary",
          planId: "pro_monthly",
          expiresAt: new Date(Date.now() + 5 * 86400000),
        },
      },
    });
    const r = await runMasterRevokeCourtesyAccess({
      db,
      request: masterReq({
        targetUid: "t1",
        reason: "Voltar contratado",
        requestId: "req223456789012345",
      }),
    });
    assert.equal(r.planAccess.contractedPlanId, "basic_monthly");
    assert.equal(r.planAccess.effectivePlanId, "basic_monthly");
    assert.equal(r.planAccess.accessSource, "paid_subscription");
  });
});

describe("runGetMyPlanEffectiveAccess", () => {
  it("6. retorna somente o próprio UID", async () => {
    const db = makeMasterPlanMockDb({
      users: {
        self_uid: { email: "self@test.com", currentPlanId: "free_limited" },
      },
      courtesy: {
        self_uid: {
          active: true,
          type: "temporary",
          planId: "intermediate_monthly",
          startsAt: new Date(Date.now() - 1000),
          expiresAt: new Date(Date.now() + 86400000),
          reason: "teste",
        },
      },
    });
    const r = await runGetMyPlanEffectiveAccess({
      db,
      request: { auth: { uid: "self_uid", token: { email: "self@test.com" } }, data: {} },
    });
    assert.equal(r.uid, "self_uid");
    assert.equal(r.planAccess.effectivePlanId, "intermediate_monthly");
    assert.equal(db.writes.length, 0);
  });

  it("19. ignora targetUid malicioso no payload", async () => {
    const db = makeMasterPlanMockDb({
      users: {
        self_uid: { email: "self@test.com", currentPlanId: "free_limited" },
        victim_uid: {
          email: "victim@test.com",
          currentPlanId: "pro_monthly",
          currentPeriodEnd: new Date(Date.now() + 86400000),
        },
      },
      courtesy: {
        victim_uid: {
          active: true,
          type: "temporary",
          planId: "pro_monthly",
          expiresAt: new Date(Date.now() + 86400000),
        },
      },
    });
    const r = await runGetMyPlanEffectiveAccess({
      db,
      request: {
        auth: { uid: "self_uid", token: { email: "self@test.com" } },
        data: { targetUid: "victim_uid" },
      },
    });
    assert.equal(r.planAccess.effectivePlanId, "free_limited");
  });

  it("20. não retorna reason ou grantedBy na cortesia", async () => {
    const db = makeMasterPlanMockDb({
      users: {
        self_uid: { email: "self@test.com", currentPlanId: "free_limited" },
      },
      courtesy: {
        self_uid: {
          active: true,
          type: "temporary",
          planId: "intermediate_monthly",
          startsAt: new Date(Date.now() - 1000),
          expiresAt: new Date(Date.now() + 86400000),
          reason: "segredo",
          grantedByUid: "admin",
          grantedByEmail: "admin@test.com",
        },
      },
    });
    const r = await runGetMyPlanEffectiveAccess({
      db,
      request: { auth: { uid: "self_uid", token: { email: "self@test.com" } }, data: {} },
    });
    const serialized = JSON.stringify(r.planAccess);
    assert.ok(!serialized.includes("segredo"));
    assert.ok(!serialized.includes("grantedBy"));
    assert.equal(r.planAccess.courtesy.active, true);
    assert.equal(r.planAccess.courtesy.planId, "intermediate_monthly");
    assert.equal(r.planAccess.courtesy.type, "temporary");
    assert.ok(r.planAccess.courtesy.startsAt);
  });
});

describe("masterListPlanAuditActions", () => {
  it("29. pagina ações por targetUid", async () => {
    const db = makeMasterPlanMockDb({
      auditActions: {
        a1: {
          actionType: "grant_courtesy",
          targetUid: "t1",
          createdAt: new Date("2026-06-01"),
          reason: "r1",
        },
        a2: {
          actionType: "revoke_courtesy",
          targetUid: "t1",
          createdAt: new Date("2026-06-02"),
          reason: "r2",
        },
      },
    });
    const r = await runMasterListPlanAuditActions({
      db,
      request: masterReq({ targetUid: "t1", pageSize: 10 }),
    });
    assert.equal(r.actions.length, 2);
    assert.equal(db.writes.length, 0);
  });
});
