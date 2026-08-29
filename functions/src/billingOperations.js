/**
 * Idempotência de CREATE / PLAN_CHANGE (PLAN_UPGRADE_017 P1A).
 * Chave canónica: op + uid + plan — nunca timestamp.
 * Provider MP não entra na transacção Firestore.
 */

import { FieldValue } from "firebase-admin/firestore";

export const BILLING_OPERATIONS_COL = "billing_operations";
export const BILLING_OP_CREATE = "create";
export const BILLING_OP_PLAN_CHANGE = "planChange";

export const BILLING_OP_STATE = {
  CREATING: "CREATING",
  CREATED: "CREATED",
  FAILED_RETRYABLE: "FAILED_RETRYABLE",
  FAILED_FINAL: "FAILED_FINAL",
};

/** Lock técnico de CREATING (016). Não é TTL comercial. */
export const CREATING_LOCK_MS = 120_000;

export function billingOperationDocId(op, uid, canonicalPlanId) {
  return `${op}:${uid}:${canonicalPlanId}`;
}

export function deterministicCreateExternalReference(uid, canonicalPlanId) {
  return `mprec|${uid}|create|${canonicalPlanId}`;
}

export function deterministicPlanChangeExternalReference(uid, canonicalPlanId, changeId) {
  return `mpchg|${uid}|${changeId}|${canonicalPlanId}`;
}

export function deterministicPlanChangeId(uid, canonicalPlanId) {
  return `planChange_${uid}_${canonicalPlanId}`;
}

/** Test helper: a chave não pode ser só Date.now() / epoch. */
export function idempotencyKeyContainsEpochMs(key) {
  return /(?:^|[^0-9])\d{13}(?:[^0-9]|$)/.test(String(key || ""));
}

function opRef(db, op, uid, canonicalPlanId) {
  return db.collection(BILLING_OPERATIONS_COL).doc(
    billingOperationDocId(op, uid, canonicalPlanId),
  );
}

/**
 * @returns {Promise<{
 *   action: "REUSE"|"IN_PROGRESS"|"RECONCILE"|"FINALIZE_LOCAL"|"CREATE"|"FAILED_FINAL"|"FAILED_RETRYABLE",
 *   record: object,
 *   id: string,
 * }>}
 */
export async function claimOrReuseBillingOperation(db, {
  op,
  uid,
  canonicalPlanId,
  nowMs = Date.now(),
}) {
  const id = billingOperationDocId(op, uid, canonicalPlanId);
  const ref = opRef(db, op, uid, canonicalPlanId);
  let decision = {
    action: "CREATE",
    record: {},
    id,
  };

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const state = String(data.state || "");
    const initPoint = String(data.initPoint || "").trim();
    const pendingId = String(data.pendingProviderSubscriptionId || "").trim();

    if (state === BILLING_OP_STATE.CREATED && initPoint) {
      decision = { action: "REUSE", record: data, id };
      return;
    }

    if (state === BILLING_OP_STATE.FAILED_FINAL) {
      decision = { action: "FAILED_FINAL", record: data, id };
      return;
    }

    if (pendingId && (state === BILLING_OP_STATE.CREATING || state === BILLING_OP_STATE.CREATED)) {
      decision = { action: "FINALIZE_LOCAL", record: data, id };
      return;
    }

    if (state === BILLING_OP_STATE.CREATING) {
      const updated = Number(data.updatedAtMs || 0);
      const age = nowMs - updated;
      if (updated && age >= 0 && age < CREATING_LOCK_MS) {
        decision = { action: "IN_PROGRESS", record: data, id };
        return;
      }
      tx.set(
        ref,
        {
          updatedAtMs: nowMs,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      decision = { action: "RECONCILE", record: data, id };
      return;
    }

    if (state === BILLING_OP_STATE.FAILED_RETRYABLE) {
      const updated = Number(data.updatedAtMs || 0);
      const age = nowMs - updated;
      if (updated && age >= 0 && age < CREATING_LOCK_MS) {
        decision = { action: "IN_PROGRESS", record: data, id };
        return;
      }
      decision = { action: "FAILED_RETRYABLE", record: data, id };
      return;
    }

    tx.set(
      ref,
      {
        op,
        uid,
        canonicalPlanId,
        state: BILLING_OP_STATE.CREATING,
        createdAtMs: data.createdAtMs || nowMs,
        updatedAtMs: nowMs,
        createdAt: data.createdAt || FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    decision = {
      action: "CREATE",
      record: { ...data, state: BILLING_OP_STATE.CREATING },
      id,
    };
  });

  return decision;
}

export async function completeBillingOperationCreated(db, {
  op,
  uid,
  canonicalPlanId,
  pendingProviderSubscriptionId,
  initPoint,
  externalReference,
  nowMs = Date.now(),
}) {
  const ref = opRef(db, op, uid, canonicalPlanId);
  await ref.set(
    {
      state: BILLING_OP_STATE.CREATED,
      pendingProviderSubscriptionId,
      initPoint,
      externalReference,
      updatedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export async function recordProviderIdOnCreatingOp(db, {
  op,
  uid,
  canonicalPlanId,
  pendingProviderSubscriptionId,
  nowMs = Date.now(),
}) {
  const ref = opRef(db, op, uid, canonicalPlanId);
  await ref.set(
    {
      pendingProviderSubscriptionId,
      updatedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export async function markBillingOperationFailed(db, {
  op,
  uid,
  canonicalPlanId,
  final = false,
  lastError,
  nowMs = Date.now(),
}) {
  const ref = opRef(db, op, uid, canonicalPlanId);
  await ref.set(
    {
      state: final ? BILLING_OP_STATE.FAILED_FINAL : BILLING_OP_STATE.FAILED_RETRYABLE,
      lastError: String(lastError || "").slice(0, 400),
      updatedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
