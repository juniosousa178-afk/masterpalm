/**
 * Resolução de mapping payment → order → user → plan.
 * Email isolado NÃO é sinal suficiente para mapping unambiguous.
 */

export const MappingConfidence = Object.freeze({
  UNAMBIGUOUS: "UNAMBIGUOUS",
  AMBIGUOUS: "AMBIGUOUS",
  UNRESOLVED: "UNRESOLVED",
});

/**
 * @param {object} input
 * @param {object|null} input.processed
 * @param {object|null} input.order
 * @param {object|null} input.providerPayment
 * @param {string|null} input.uidFromUser
 */
export function resolvePaymentMapping({
  processed,
  order,
  providerPayment,
  uidFromUser,
}) {
  const paymentId = String(processed?.paymentId || processed?.id || providerPayment?.id || "");
  const procUid = processed?.uid ? String(processed.uid) : null;
  const procOrderId = processed?.planOrderId ? String(processed.planOrderId) : null;
  const extRef = providerPayment?.external_reference
    ? String(providerPayment.external_reference)
    : null;
  const md = providerPayment?.metadata || {};
  const mdUid = md.uid || md.user_id || md.userId || null;
  const mdOrderId = md.plan_order_id || md.planOrderId || null;
  const orderUid = order?.userId ? String(order.userId) : null;
  const orderId = order?.planOrderId || order?.id || null;

  const signals = [];

  if (procUid && procOrderId) {
    signals.push({ type: "processed_doc", uid: procUid, planOrderId: procOrderId });
  }
  if (extRef?.startsWith("po_") && order && extRef === (orderId || order.planOrderId)) {
    signals.push({ type: "external_reference_order", uid: orderUid, planOrderId: extRef });
  }
  if (mdUid && mdOrderId) {
    signals.push({ type: "provider_metadata", uid: String(mdUid), planOrderId: String(mdOrderId) });
  }
  if (orderUid && orderId && !extRef?.startsWith("po_")) {
    signals.push({ type: "order_doc", uid: orderUid, planOrderId: String(orderId) });
  }

  if (signals.length === 0) {
    return {
      confidence: MappingConfidence.UNRESOLVED,
      uid: null,
      planOrderId: null,
      planId: null,
      emailOnly: false,
    };
  }

  const uids = new Set(signals.map((s) => s.uid).filter(Boolean));
  const orderIds = new Set(signals.map((s) => s.planOrderId).filter(Boolean));

  if (uids.size > 1 || orderIds.size > 1) {
    return {
      confidence: MappingConfidence.AMBIGUOUS,
      uid: null,
      planOrderId: null,
      planId: order?.canonicalPlanId || md.normalized_plan_id || md.plan || null,
      emailOnly: false,
    };
  }

  const uid = [...uids][0] || procUid || orderUid || mdUid || uidFromUser || null;
  const planOrderId = [...orderIds][0] || procOrderId || (extRef?.startsWith("po_") ? extRef : null) || mdOrderId || null;
  const planId =
    order?.canonicalPlanId ||
    order?.legacyPlanAlias ||
    md.normalized_plan_id ||
    md.plan ||
    null;

  const hasStrongSignal =
    (procUid && procOrderId) ||
    (extRef?.startsWith("po_") && orderUid && order) ||
    (mdUid && mdOrderId);

  if (!hasStrongSignal || !uid || !planOrderId) {
    return {
      confidence: MappingConfidence.AMBIGUOUS,
      uid,
      planOrderId,
      planId,
      emailOnly: false,
    };
  }

  if (orderUid && uid && orderUid !== uid) {
    return {
      confidence: MappingConfidence.AMBIGUOUS,
      uid: null,
      planOrderId: null,
      planId,
      emailOnly: false,
    };
  }

  return {
    confidence: MappingConfidence.UNAMBIGUOUS,
    uid: String(uid),
    planOrderId: String(planOrderId),
    planId: planId ? String(planId) : null,
    emailOnly: false,
  };
}

/**
 * Detecta grant prévio do mesmo pagamento ou plano pago sobreposto.
 */
export function detectPriorGrant({ user, subscription, order, paymentId, purchasedPlan, normalizePlanId }) {
  const pid = String(paymentId || "");
  const plan = normalizePlanId(purchasedPlan || "");

  if (order?.orderStatus === "ATIVO" || order?.paymentConfirmation === "PAGO_CONFIRMADO") {
    return { granted: true, reason: "order_final" };
  }
  if (subscription?.status === "active" && String(subscription.paymentId || "") === pid) {
    return { granted: true, reason: "subscription_active" };
  }
  if (user?.planLastPaymentId && String(user.planLastPaymentId) === pid) {
    if (normalizePlanId(user.currentPlanId || "") === plan && plan) {
      return { granted: true, reason: "user_plan_last_payment" };
    }
  }
  if (plan && normalizePlanId(user?.currentPlanId || "") === plan) {
    const end = user?.currentPeriodEnd;
    const endDate = end?.toDate ? end.toDate() : end ? new Date(end) : null;
    if (endDate && endDate.getTime() > Date.now()) {
      return { granted: true, reason: "overlapping_entitlement" };
    }
  }
  return { granted: false, reason: null };
}
