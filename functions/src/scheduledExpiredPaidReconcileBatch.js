/**
 * Núcleo testável do job scheduledReconcileExpiredPaidPlans (sem registrar Cloud Function).
 * Regra de skip alinhada ao loop original — única fonte para classificação + iteração.
 */

import {
  computePlanState,
  normalizeCanonicalPlanId,
  PAID_PLANS_WITH_RENEWAL,
} from "../ensureUserPlan.js";
import { getAuth } from "firebase-admin/auth";
import { isPlatformAdminAuthUser, isRootAccountEmail } from "./rootAccounts.js";

/**
 * @typedef {'skip_not_paid' | 'skip_invalid_period' | 'skip_protected' | 'process'} SchedulerDocDecision
 */

/**
 * Classifica o documento users/{uid} para o scheduler (mesma ordem de checagens do job).
 * @param {Record<string, unknown>} data
 * @param {string} email
 * @param {Date} now
 * @param {{ verifiedRoot?: boolean }} [opts] verifiedRoot só a partir do Firebase Auth (Admin), nunca do perfil
 * @returns {SchedulerDocDecision}
 */
export function classifyExpiredPaidSchedulerDoc(data, email, now, { verifiedRoot = false } = {}) {
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

  if (verifiedRoot === true) return "skip_protected";
  if (data?.manual_grant?.type === "lifetime") return "skip_protected";
  if (data?.manualOverride && data.manualOverride.enabled === true) {
    return "skip_protected";
  }

  return "process";
}

/**
 * Perfil que alega root (`isRoot` ou e-mail root em users/{uid}). Campos do perfil são graváveis
 * pelo cliente ou podem estar desatualizados: só indicam quem consultar no Auth, nunca autorizam.
 */
export function isSchedulerRootCandidate(data, email) {
  return data?.isRoot === true || isRootAccountEmail(email);
}

/**
 * Root só se o registro do Firebase Auth do próprio uid confirmar. Qualquer falha → não root.
 * @returns {Promise<{ root: boolean, reason: string }>}
 */
export async function resolveSchedulerRootAuthority({ uid, getAuthUser }) {
  let user;
  try {
    user = await getAuthUser(uid);
  } catch (err) {
    return {
      root: false,
      reason: err?.code === "auth/user-not-found" ? "auth_user_not_found" : "auth_lookup_failed",
    };
  }
  if (isPlatformAdminAuthUser(user)) return { root: true, reason: "auth_verified_root" };
  if (!user?.email) return { root: false, reason: "auth_email_missing" };
  if (!isRootAccountEmail(user.email)) return { root: false, reason: "auth_email_not_root" };
  if (user.emailVerified !== true) return { root: false, reason: "auth_email_unverified" };
  return { root: false, reason: "auth_account_disabled" };
}

const defaultGetAuthUser = (uid) => getAuth().getUser(uid);

/**
 * Executa uma passagem do job a partir de um QuerySnapshot já obtido (testável / injetável).
 *
 * @param {object} opts
 * @param {import('firebase-admin/firestore').Firestore} opts.db
 * @param {Date} opts.now
 * @param {import('firebase-admin/firestore').QuerySnapshot} opts.snap
 * @param {typeof computePlanState} [opts.computePlanStateImpl]
 * @param {(uid: string) => Promise<import('firebase-admin/auth').UserRecord>} [opts.getAuthUser]
 * @returns {Promise<Record<string, unknown>>}
 */
export async function runScheduledReconcileBatch({
  db,
  now,
  snap,
  computePlanStateImpl = computePlanState,
  getAuthUser = defaultGetAuthUser,
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
    rootAuthLookups: 0,
    rootCandidatesRejected: 0,
  };

  for (const doc of snap.docs) {
    const uid = doc.id;
    const data = doc.data() || {};
    const email = String(data.email || "").trim();

    try {
      stats.evaluated++;

      let decision = classifyExpiredPaidSchedulerDoc(data, email, now);
      if (decision === "process" && isSchedulerRootCandidate(data, email)) {
        stats.rootAuthLookups++;
        const authority = await resolveSchedulerRootAuthority({ uid, getAuthUser });
        if (authority.root) {
          decision = classifyExpiredPaidSchedulerDoc(data, email, now, { verifiedRoot: true });
        } else {
          stats.rootCandidatesRejected++;
          console.warn(
            JSON.stringify({
              evt: "scheduled_expired_paid_plan_root_claim_rejected",
              uid,
              reason: authority.reason,
            }),
          );
        }
      }
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
