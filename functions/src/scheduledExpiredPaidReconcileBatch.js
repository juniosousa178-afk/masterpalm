/**
 * Núcleo testável do job scheduledReconcileExpiredPaidPlans (sem registrar Cloud Function).
 * Regra de skip alinhada ao loop original — única fonte para classificação + iteração.
 */

import {
  computePlanState,
  normalizeCanonicalPlanId,
  PAID_PLANS_WITH_RENEWAL,
  ROOT_EMAIL,
} from "../ensureUserPlan.js";

function normalizeEmail(s) {
  return String(s || "").trim().toLowerCase();
}

/**
 * @typedef {'skip_not_paid' | 'skip_invalid_period' | 'skip_protected' | 'process'} SchedulerDocDecision
 */

/**
 * Classifica o documento users/{uid} para o scheduler (mesma ordem de checagens do job).
 * @param {Record<string, unknown>} data
 * @param {string} email
 * @param {Date} now
 * @returns {SchedulerDocDecision}
 */
export function classifyExpiredPaidSchedulerDoc(data, email, now) {
  const canonical = normalizeCanonicalPlanId(
    String(data?.currentPlanId || data?.plan || ""),
  );
  if (!PAID_PLANS_WITH_RENEWAL.includes(canonical)) {
    return "skip_not_paid";
  }

  const renewAt = data?.currentPeriodEnd?.toDate
    ? data.currentPeriodEnd.toDate()
    : null;
  if (!renewAt || renewAt >= now) {
    return "skip_invalid_period";
  }

  if (data?.isRoot === true) return "skip_protected";
  if (normalizeEmail(email) === normalizeEmail(ROOT_EMAIL)) {
    return "skip_protected";
  }
  if (data?.manual_grant?.type === "lifetime") return "skip_protected";
  if (data?.manualOverride && data.manualOverride.enabled === true) {
    return "skip_protected";
  }

  return "process";
}

/**
 * Executa uma passagem do job a partir de um QuerySnapshot já obtido (testável / injetável).
 *
 * @param {object} opts
 * @param {import('firebase-admin/firestore').Firestore} opts.db
 * @param {Date} opts.now
 * @param {import('firebase-admin/firestore').QuerySnapshot} opts.snap
 * @param {typeof computePlanState} [opts.computePlanStateImpl]
 * @returns {Promise<Record<string, unknown>>}
 */
export async function runScheduledReconcileBatch({
  db,
  now,
  snap,
  computePlanStateImpl = computePlanState,
}) {
  const stats = {
    evt: "scheduled_expired_paid_plan_reconcile",
    at: now.toISOString(),
    queryBatchSize: snap.size,
    evaluated: 0,
    skippedNotPaidPlan: 0,
    skippedProtected: 0,
    reconcileRuns: 0,
    downgradedToFreeLimited: 0,
    failed: 0,
  };

  for (const doc of snap.docs) {
    const uid = doc.id;
    const data = doc.data() || {};
    const email = String(data.email || "").trim();

    try {
      stats.evaluated++;

      const decision = classifyExpiredPaidSchedulerDoc(data, email, now);
      if (decision === "skip_not_paid") {
        stats.skippedNotPaidPlan++;
        continue;
      }
      if (decision === "skip_invalid_period") {
        stats.skippedNotPaidPlan++;
        continue;
      }
      if (decision === "skip_protected") {
        stats.skippedProtected++;
        continue;
      }

      const beforePlan = normalizeCanonicalPlanId(
        data.currentPlanId || data.plan || "",
      );

      await computePlanStateImpl({ db, uid, email });
      stats.reconcileRuns++;

      const afterSnap = await db.collection("users").doc(uid).get();
      const afterData = afterSnap.data() || {};
      const afterPlan = normalizeCanonicalPlanId(
        afterData.currentPlanId || afterData.plan || "",
      );

      if (afterPlan === "free_limited" && beforePlan !== "free_limited") {
        stats.downgradedToFreeLimited++;
      }
    } catch (err) {
      stats.failed++;
      console.error(
        JSON.stringify({
          evt: "scheduled_expired_paid_plan_uid_error",
          uid,
          err: String(err?.message || err),
        }),
      );
    }
  }

  return stats;
}
