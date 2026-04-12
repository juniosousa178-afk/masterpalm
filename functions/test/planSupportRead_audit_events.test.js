/**
 * Contrato de formato dos eventos de auditoria (helpers puros; sem emulator).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  PLAN_SUPPORT_AUDIT_EVT,
  buildAuditDeniedUnauthenticated,
  buildAuditDeniedNotRoot,
  buildAuditInvalid,
  buildAuditNotFoundEmail,
  buildAuditNotFoundUid,
  buildAuditError,
  buildAuditRead,
  maskEmailForAudit,
  maskUidForAudit,
} from "../src/planSupportRead.js";

/** Chaves que nunca devem aparecer em payload de auditoria (evita vazamento de snapshot/dados sensíveis). */
const FORBIDDEN_AUDIT_KEYS = [
  "snapshot",
  "providerSubscriptionId",
  "currentPlanId",
  "billingSource",
  "billingVersion",
  "currentPeriodEnd",
  "interpretationLabels",
  "manualOverride",
  "manual_grant",
  "manualGrant",
  "usesMercadoRecurringPlanBilling",
];

function assertNoForbiddenKeys(obj, label = "payload") {
  for (const k of FORBIDDEN_AUDIT_KEYS) {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(obj, k),
      `${label} não deve conter chave proibida: ${k}`,
    );
  }
}

describe("PLAN_SUPPORT_AUDIT_EVT — nomes estáveis", () => {
  it("mantém strings literais do contrato", () => {
    assert.equal(PLAN_SUPPORT_AUDIT_EVT.READ, "plan_support_snapshot_read");
    assert.equal(PLAN_SUPPORT_AUDIT_EVT.DENIED, "plan_support_snapshot_denied");
    assert.equal(
      PLAN_SUPPORT_AUDIT_EVT.NOT_FOUND,
      "plan_support_snapshot_not_found",
    );
    assert.equal(
      PLAN_SUPPORT_AUDIT_EVT.INVALID,
      "plan_support_snapshot_invalid",
    );
    assert.equal(PLAN_SUPPORT_AUDIT_EVT.ERROR, "plan_support_snapshot_error");
  });
});

describe("buildAuditDeniedUnauthenticated", () => {
  it("evt e deniedReason mínimos; sem payload excessivo", () => {
    const p = buildAuditDeniedUnauthenticated();
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.DENIED);
    assert.equal(p.deniedReason, "unauthenticated");
    assert.deepEqual(Object.keys(p).sort(), ["deniedReason", "evt"]);
    assertNoForbiddenKeys(p);
  });
});

describe("buildAuditDeniedNotRoot", () => {
  it("evt, deniedReason, callerUid, callerEmail", () => {
    const p = buildAuditDeniedNotRoot({
      callerUid: "abc123",
      callerEmail: "root@x.com",
    });
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.DENIED);
    assert.equal(p.deniedReason, "not_root");
    assert.equal(p.callerUid, "abc123");
    assert.equal(p.callerEmail, "root@x.com");
    assertNoForbiddenKeys(p);
  });
});

describe("buildAuditInvalid", () => {
  it("missing_target", () => {
    const p = buildAuditInvalid({
      callerUid: "u1",
      callerEmail: "a@b.com",
      deniedReason: "missing_target",
    });
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.INVALID);
    assert.equal(p.deniedReason, "missing_target");
    assert.equal(p.callerUid, "u1");
    assert.equal(p.callerEmail, "a@b.com");
    assertNoForbiddenKeys(p);
  });

  it("both_target_uid_and_email", () => {
    const p = buildAuditInvalid({
      callerUid: "u1",
      callerEmail: "a@b.com",
      deniedReason: "both_target_uid_and_email",
    });
    assert.equal(p.deniedReason, "both_target_uid_and_email");
    assertNoForbiddenKeys(p);
  });
});

describe("buildAuditNotFoundEmail", () => {
  it("lookupMode email, email mascarado, authLookup", () => {
    const em = "joao@dominio.com";
    const masked = maskEmailForAudit(em);
    const p = buildAuditNotFoundEmail({
      callerUid: "caller1",
      callerEmail: "root@x.com",
      targetEmailMasked: masked,
    });
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.NOT_FOUND);
    assert.equal(p.lookupMode, "email");
    assert.equal(p.targetEmailMasked, "j***@dominio.com");
    assert.equal(p.authLookup, "user_not_found");
    assert.equal(p.callerUid, "caller1");
    assert.ok(!String(p.targetEmailMasked || "").includes("joao@"));
    assertNoForbiddenKeys(p);
  });
});

describe("buildAuditNotFoundUid", () => {
  it("lookupMode uid, uid mascarado", () => {
    const uid = "abcdefghijklmnopqrstuvwxyz12";
    const p = buildAuditNotFoundUid({
      callerUid: "caller1",
      callerEmail: "r@x.com",
      targetUidMasked: maskUidForAudit(uid),
    });
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.NOT_FOUND);
    assert.equal(p.lookupMode, "uid");
    assert.ok(String(p.targetUidMasked).includes("…"));
    assert.equal(p.authLookup, "user_not_found");
    assertNoForbiddenKeys(p);
  });
});

describe("buildAuditError", () => {
  it("email e uid lookupMode; err como passado pelo caller (truncado na origem)", () => {
    const long = "x".repeat(200);
    const truncated = long.slice(0, 120);
    const pe = buildAuditError({
      callerUid: "c",
      callerEmail: "e@x.com",
      lookupMode: "email",
      err: truncated,
    });
    assert.equal(pe.evt, PLAN_SUPPORT_AUDIT_EVT.ERROR);
    assert.equal(pe.lookupMode, "email");
    assert.equal(pe.err.length, 120);
    assertNoForbiddenKeys(pe);

    const pu = buildAuditError({
      callerUid: "c",
      callerEmail: "e@x.com",
      lookupMode: "uid",
      err: "internal",
    });
    assert.equal(pu.lookupMode, "uid");
    assertNoForbiddenKeys(pu);
  });
});

describe("buildAuditRead", () => {
  it("campos-chave estáveis; sem dados de billing no log", () => {
    const p = buildAuditRead({
      callerUid: "rootUid",
      callerEmail: "root@x.com",
      lookupMode: "email",
      targetUid: "targetUidResolved",
      targetEmailMasked: maskEmailForAudit("alvo@z.com"),
      usersDocExists: true,
      found: true,
    });
    assert.equal(p.evt, PLAN_SUPPORT_AUDIT_EVT.READ);
    assert.equal(p.lookupMode, "email");
    assert.equal(p.targetUid, "targetUidResolved");
    assert.equal(p.usersDocExists, true);
    assert.equal(p.found, true);
    assert.ok(p.targetEmailMasked);
    assertNoForbiddenKeys(p);
    const keys = Object.keys(p).sort();
    assert.deepEqual(keys, [
      "callerEmail",
      "callerUid",
      "evt",
      "found",
      "lookupMode",
      "targetEmailMasked",
      "targetUid",
      "usersDocExists",
    ]);
  });
});
