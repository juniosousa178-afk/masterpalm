/**
 * Integração leve: runGetPlanBillingSnapshotForSupport + mocks + captura de audit via console.log.
 * Sem emulator; valida que os ramos continuam emitindo os mesmos payloads dos builders.
 */
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

import { HttpsError } from "firebase-functions/v2/https";

import { ROOT_ACCOUNT_EMAILS } from "../src/rootAccounts.js";
import {
  runGetPlanBillingSnapshotForSupport,
  buildAuditDeniedUnauthenticated,
  buildAuditDeniedNotRoot,
  buildAuditInvalid,
  buildAuditNotFoundEmail,
  buildAuditRead,
  buildAuditError,
  maskEmailForAudit,
} from "../src/planSupportRead.js";

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

function assertAuditPayloadSafe(obj) {
  for (const k of FORBIDDEN_AUDIT_KEYS) {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(obj, k),
      `auditoria não deve conter ${k}`,
    );
  }
}

/** @type {typeof console.log} */
let origLog;

/** @type {object[]} */
let auditPayloads;

beforeEach(() => {
  origLog = console.log;
  auditPayloads = [];
  console.log = (...args) => {
    origLog.apply(console, args);
    if (args.length === 1 && typeof args[0] === "string") {
      try {
        const o = JSON.parse(args[0]);
        if (
          o &&
          typeof o.evt === "string" &&
          o.evt.startsWith("plan_support_snapshot_")
        ) {
          auditPayloads.push(o);
        }
      } catch {
        /* não é JSON de auditoria */
      }
    }
  };
});

afterEach(() => {
  console.log = origLog;
});

const ROOT = ROOT_ACCOUNT_EMAILS[0];

function normalizePlanIdMinimal(raw) {
  const s = String(raw || "").trim();
  return s || "free_limited";
}

function makeFirestoreWithUserDoc(uid, data) {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({
          exists: true,
          data: () => ({ email: "alvo@exemplo.com", currentPlanId: "free_limited", ...data }),
        }),
      }),
    }),
  };
}

describe("runGetPlanBillingSnapshotForSupport — integração de auditoria", () => {
  it("read bem-sucedido (uid): último log = buildAuditRead", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    const targetUid = "targetUidabcdefghijklmn12";
    const adminMod = {
      auth: () => ({
        getUser: async (u) => ({
          uid: u,
          email: "alvo@exemplo.com",
        }),
        getUserByEmail: async () => {
          throw new Error("não usado");
        },
      }),
    };
    const db = makeFirestoreWithUserDoc(targetUid, {});

    const out = await runGetPlanBillingSnapshotForSupport({
      db,
      admin: adminMod,
      request: {
        auth: { uid: callerUid, token: { email: ROOT } },
        data: { targetUid },
      },
      normalizePlanId: normalizePlanIdMinimal,
    });

    assert.equal(out.ok, true);
    assert.equal(out.found, true);
    assert.equal(auditPayloads.length, 1);
    const expected = buildAuditRead({
      callerUid,
      callerEmail: ROOT,
      lookupMode: "uid",
      targetUid,
      targetEmailMasked: maskEmailForAudit("alvo@exemplo.com"),
      usersDocExists: true,
      found: true,
    });
    assert.deepEqual(auditPayloads[0], expected);
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("denied not_root: audit = buildAuditDeniedNotRoot", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    await assert.rejects(
      () =>
        runGetPlanBillingSnapshotForSupport({
          db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
          admin: { auth: () => ({}) },
          request: {
            auth: { uid: callerUid, token: { email: "nao.root@exemplo.com" } },
            data: { targetUid: "x".repeat(28) },
          },
          normalizePlanId: normalizePlanIdMinimal,
        }),
      (e) => e instanceof HttpsError && e.code === "permission-denied",
    );
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(
      auditPayloads[0],
      buildAuditDeniedNotRoot({
        callerUid,
        callerEmail: "nao.root@exemplo.com",
      }),
    );
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("not_found (email): audit = buildAuditNotFoundEmail", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    const targetEmail = "fantasma@dominio.com";
    const adminMod = {
      auth: () => ({
        getUserByEmail: async () => {
          const e = new Error("not found");
          e.code = "auth/user-not-found";
          throw e;
        },
      }),
    };
    const out = await runGetPlanBillingSnapshotForSupport({
      db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
      admin: adminMod,
      request: {
        auth: { uid: callerUid, token: { email: ROOT } },
        data: { targetEmail },
      },
      normalizePlanId: normalizePlanIdMinimal,
    });
    assert.deepEqual(out, {
      ok: true,
      found: false,
      reason: "auth_user_not_found",
      snapshot: null,
    });
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(
      auditPayloads[0],
      buildAuditNotFoundEmail({
        callerUid,
        callerEmail: ROOT,
        targetEmailMasked: maskEmailForAudit(targetEmail),
      }),
    );
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("invalid missing_target: audit = buildAuditInvalid", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    await assert.rejects(
      () =>
        runGetPlanBillingSnapshotForSupport({
          db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
          admin: { auth: () => ({}) },
          request: {
            auth: { uid: callerUid, token: { email: ROOT } },
            data: {},
          },
          normalizePlanId: normalizePlanIdMinimal,
        }),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(
      auditPayloads[0],
      buildAuditInvalid({
        callerUid,
        callerEmail: ROOT,
        deniedReason: "missing_target",
      }),
    );
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("invalid both_target_uid_and_email: audit = buildAuditInvalid", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    await assert.rejects(
      () =>
        runGetPlanBillingSnapshotForSupport({
          db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
          admin: { auth: () => ({}) },
          request: {
            auth: { uid: callerUid, token: { email: ROOT } },
            data: { targetUid: "uid012345678901234567890", targetEmail: "a@b.com" },
          },
          normalizePlanId: normalizePlanIdMinimal,
        }),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(
      auditPayloads[0],
      buildAuditInvalid({
        callerUid,
        callerEmail: ROOT,
        deniedReason: "both_target_uid_and_email",
      }),
    );
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("unauthenticated: audit = buildAuditDeniedUnauthenticated", async () => {
    await assert.rejects(
      () =>
        runGetPlanBillingSnapshotForSupport({
          db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
          admin: { auth: () => ({}) },
          request: { data: { targetUid: "x".repeat(28) } },
          normalizePlanId: normalizePlanIdMinimal,
        }),
      (e) => e instanceof HttpsError && e.code === "unauthenticated",
    );
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(auditPayloads[0], buildAuditDeniedUnauthenticated());
    assertAuditPayloadSafe(auditPayloads[0]);
  });

  it("erro inesperado no Auth (email): audit = buildAuditError", async () => {
    const callerUid = "callerUidabcdefghijklmn12";
    const adminMod = {
      auth: () => ({
        getUserByEmail: async () => {
          const e = new Error("network");
          e.code = "auth/network-request-failed";
          throw e;
        },
      }),
    };
    await assert.rejects(
      () =>
        runGetPlanBillingSnapshotForSupport({
          db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
          admin: adminMod,
          request: {
            auth: { uid: callerUid, token: { email: ROOT } },
            data: { targetEmail: "qualquer@x.com" },
          },
          normalizePlanId: normalizePlanIdMinimal,
        }),
      (e) => e instanceof HttpsError && e.code === "internal",
    );
    assert.equal(auditPayloads.length, 1);
    assert.deepEqual(
      auditPayloads[0],
      buildAuditError({
        callerUid,
        callerEmail: ROOT,
        lookupMode: "email",
        err: "auth/network-request-failed",
      }),
    );
    assertAuditPayloadSafe(auditPayloads[0]);
  });
});
