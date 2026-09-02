/**
 * Ativação de plano pago (checkout pontual / plan_orders).
 * Usa Timestamp modular (ESM) — não admin.firestore.Timestamp.
 */

import { Timestamp } from "firebase-admin/firestore";
import { PLAN_ORDERS_COL } from "./planOrdersWebhook.js";

function addMonths(d, n) {
  const x = new Date(d);
  x.setMonth(x.getMonth() + n);
  return x;
}

function addYears(d, n) {
  const x = new Date(d);
  x.setFullYear(x.getFullYear() + n);
  return x;
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {string} opts.uid
 * @param {string} opts.plan
 * @param {string} [opts.paymentId]
 * @param {string} [opts.status]
 * @param {number|null} [opts.amount]
 * @param {string|null} [opts.planOrderId]
 * @param {object} [opts.billingExtras]
 * @param {function(string): string} opts.normalizePlanId
 * @param {import("firebase-admin/firestore").FieldValue | object} opts.nowTs
 */
export async function activatePlanForUser({
  db,
  uid,
  plan,
  paymentId,
  status: _status,
  amount,
  planOrderId,
  billingExtras,
  normalizePlanId,
  nowTs,
}) {
  const now = new Date();
  let renew = null;
  const canonicalPlanId = normalizePlanId(plan);
  if (canonicalPlanId === "pro_yearly") renew = addYears(now, 1);
  else if (
    canonicalPlanId === "pro_monthly" ||
    canonicalPlanId === "basic_monthly" ||
    canonicalPlanId === "intermediate_monthly"
  ) {
    renew = addMonths(now, 1);
  } else {
    renew = addMonths(now, 1);
  }

  const ref = db.collection("users").doc(uid);

  const payload = {
    currentPlanId: canonicalPlanId || "pro_monthly",
    status: "active",
    billingStatus: "active",
    currentPeriodEnd: renew ? Timestamp.fromDate(renew) : null,
    trialing: false,
    trialUsed: true,
    cancelAtPeriodEnd: false,
    planLastPaymentId: String(paymentId || ""),
    updatedAt: nowTs,
    ...(billingExtras && typeof billingExtras === "object" ? billingExtras : {}),
  };

  await ref.set(payload, { merge: true });

  await ref.collection("subscriptions").doc(String(paymentId || Date.now())).set(
    {
      planId: canonicalPlanId || "pro_monthly",
      status: "active",
      trialing: false,
      currentPeriodEnd: renew ? Timestamp.fromDate(renew) : null,
      kind: "paid",
      paymentId: String(paymentId || ""),
      planOrderId: planOrderId || null,
      amount: amount ?? null,
      createdAt: nowTs,
      updatedAt: nowTs,
    },
    { merge: true },
  );

  if (planOrderId) {
    await db
      .collection(PLAN_ORDERS_COL)
      .doc(String(planOrderId))
      .set(
        {
          userId: uid,
          activatedPlanId: canonicalPlanId || "pro_monthly",
          expiresAt: renew ? Timestamp.fromDate(renew) : null,
          updatedAt: nowTs,
        },
        { merge: true },
      );
  }

  return payload;
}
