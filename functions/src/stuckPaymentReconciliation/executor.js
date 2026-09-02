/**
 * Executor de reconciliation idempotente — transação compare-and-set.
 * NÃO usa webhook replay. dryRun=true por padrão.
 */

import { Timestamp } from "firebase-admin/firestore";
import { computePlanPeriodEnd } from "../planPeriod.js";
import { PLAN_ORDERS_COL } from "../planOrdersWebhook.js";
import { classifyStuckPayment } from "./classifier.js";
import { detectPriorGrant, resolvePaymentMapping } from "./mapping.js";
import { ReasonCode, ReconciliationOutcome } from "./reasonCodes.js";

export const DEFAULT_EXECUTOR_OPTIONS = Object.freeze({
  dryRun: true,
  autoExecuteRepair: false,
});

/**
 * Planeja repair a partir de classificação (não executa se não SAFE).
 */
export function planReconciliation(classification) {
  if (classification.outcome === ReconciliationOutcome.SAFE_REPAIR_CANDIDATE) {
    return {
      action: "APPLY_REPAIR",
      paymentId: classification.paymentId,
      uid: classification.uid,
      planOrderId: classification.planOrderId,
      purchasedPlan: classification.purchasedPlan,
      periodStart: classification.periodStart,
      periodEnd: classification.periodEnd,
    };
  }
  return { action: "NOOP", reason: classification.reasonCode || classification.outcome };
}

/**
 * Executa reconciliation transacional (somente ambiente local/teste com db injetado).
 * @param {object} params
 * @param {import("firebase-admin/firestore").Firestore} params.db
 * @param {string} params.paymentId
 * @param {object} params.providerPayment
 * @param {function(string): string} params.normalizePlanId
 * @param {object} [params.nowTs]
 * @param {boolean} [params.dryRun]
 * @param {Date} [params.now]
 */
export async function executeIdempotentReconciliation({
  db,
  paymentId,
  providerPayment,
  normalizePlanId,
  nowTs = Timestamp.now(),
  dryRun = true,
  now = new Date(),
}) {
  const pid = String(paymentId);
  const processedRef = db.collection("processed_plan_payments").doc(pid);
  const processedSnap = await processedRef.get();
  const processed = processedSnap.exists ? { id: pid, ...processedSnap.data() } : null;

  if (!processed) {
    return freeze({
      outcome: ReconciliationOutcome.PROVIDER_NOT_ELIGIBLE,
      reasonCode: ReasonCode.PAYMENT_NOT_FOUND,
      applied: false,
      dryRun,
    });
  }

  const planOrderId =
    processed.planOrderId || providerPayment?.external_reference || null;
  const orderRef = planOrderId ? db.collection(PLAN_ORDERS_COL).doc(String(planOrderId)) : null;
  const orderSnap = orderRef ? await orderRef.get() : null;
  const order = orderSnap?.exists ? { id: planOrderId, ...orderSnap.data() } : null;

  const mapping = resolvePaymentMapping({ processed, order, providerPayment });
  const uid = mapping.uid;
  const userRef = uid ? db.collection("users").doc(uid) : null;
  const userSnap = userRef ? await userRef.get() : null;
  const user = userSnap?.exists ? userSnap.data() : null;
  const subRef = uid ? userRef.collection("subscriptions").doc(pid) : null;
  const subSnap = subRef ? await subRef.get() : null;
  const subscription = subSnap?.exists ? subSnap.data() : null;

  const classification = classifyStuckPayment({
    processed,
    providerPayment,
    order,
    user,
    subscription,
    normalizePlanId,
    now,
    staleThresholdMs: 0,
  });

  if (classification.outcome !== ReconciliationOutcome.SAFE_REPAIR_CANDIDATE) {
    return freeze({
      outcome: classification.outcome,
      reasonCode: classification.reasonCode,
      applied: false,
      dryRun,
      classification: classification.classification,
    });
  }

  if (dryRun) {
    return freeze({
      outcome: ReconciliationOutcome.REPAIR_SKIPPED_DRY_RUN,
      reasonCode: ReasonCode.APPROVED_NOT_GRANTED,
      applied: false,
      dryRun: true,
      plan: classification.purchasedPlan,
      periodEnd: classification.periodEnd,
    });
  }

  const approvedAt = new Date(classification.periodStart);
  const periodEnd = computePlanPeriodEnd(classification.purchasedPlan, approvedAt, normalizePlanId);
  const periodEndTs = Timestamp.fromDate(periodEnd);
  const paidAtTs = Timestamp.fromDate(approvedAt);
  const canonical = normalizePlanId(classification.purchasedPlan);

  let applied = false;
  let outcome = ReconciliationOutcome.ALREADY_RECONCILED;

  await db.runTransaction(async (tx) => {
    const pr = await tx.get(processedRef);
    const pd = pr.exists ? pr.data() || {} : {};
    if (pd.status === "approved") {
      outcome = ReconciliationOutcome.ALREADY_RECONCILED;
      return;
    }
    if (String(pd.status || "") !== "processing") {
      throw new Error(ReasonCode.GRANT_RACE_LOST);
    }

    const or = orderRef ? await tx.get(orderRef) : null;
    const od = or?.exists ? or.data() || {} : {};
    if (String(od.orderStatus || "") !== "PENDENTE") {
      throw new Error(ReasonCode.GRANT_RACE_LOST);
    }

    const ur = userRef ? await tx.get(userRef) : null;
    const ud = ur?.exists ? ur.data() || {} : {};
    const sr = subRef ? await tx.get(subRef) : null;
    const sd = sr?.exists ? sr.data() || {} : {};

    const prior = detectPriorGrant({
      user: ud,
      subscription: sd,
      order: od,
      paymentId: pid,
      purchasedPlan: canonical,
      normalizePlanId,
    });
    if (prior.granted) {
      outcome = ReconciliationOutcome.ALREADY_GRANTED;
      throw new Error(ReasonCode.ALREADY_GRANTED);
    }

    tx.set(
      userRef,
      {
        currentPlanId: canonical,
        status: "active",
        billingStatus: "active",
        currentPeriodEnd: periodEndTs,
        trialing: false,
        trialUsed: true,
        cancelAtPeriodEnd: false,
        planLastPaymentId: pid,
        updatedAt: nowTs,
      },
      { merge: true },
    );

    tx.set(
      subRef,
      {
        planId: canonical,
        status: "active",
        trialing: false,
        currentPeriodEnd: periodEndTs,
        kind: "paid",
        paymentId: pid,
        planOrderId: classification.planOrderId,
        amount: providerPayment.transaction_amount ?? null,
        createdAt: paidAtTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );

    tx.set(
      orderRef,
      {
        userId: uid,
        activatedPlanId: canonical,
        expiresAt: periodEndTs,
        orderStatus: "ATIVO",
        paymentConfirmation: "PAGO_CONFIRMADO",
        paidAt: paidAtTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );

    tx.set(
      processedRef,
      {
        paymentId: pid,
        processedAt: nowTs,
        uid,
        planOrderId: classification.planOrderId,
        status: "approved",
        rawStatus: "approved",
        reconciliationSource: "stuck_payment_reconciliation",
        updatedAt: nowTs,
      },
      { merge: true },
    );

    applied = true;
    outcome = ReconciliationOutcome.REPAIR_APPLIED;
  }).catch((err) => {
    if (err.message === ReasonCode.ALREADY_GRANTED) {
      return;
    }
    if (err.message === ReasonCode.GRANT_RACE_LOST) {
      outcome = ReconciliationOutcome.MANUAL_REVIEW_REQUIRED;
      return;
    }
    throw err;
  });

  return freeze({
    outcome,
    reasonCode: applied ? ReasonCode.APPROVED_NOT_GRANTED : ReasonCode.ALREADY_RECONCILED,
    applied,
    dryRun: false,
    paymentId: pid,
  });
}

function freeze(obj) {
  return Object.freeze({ blindWebhookReplay: false, ...obj });
}
