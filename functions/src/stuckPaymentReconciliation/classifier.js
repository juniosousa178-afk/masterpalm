/**
 * Classificador de casos processing — detector → classifier.
 */

import { computePlanPeriodEnd } from "../planPeriod.js";
import { detectPriorGrant, resolvePaymentMapping } from "./mapping.js";
import {
  Classification,
  ReasonCode,
  ReconciliationOutcome,
} from "./reasonCodes.js";
import { ageMs, maskPaymentId, toDate } from "./utils.js";

/**
 * @typedef {object} ClassifyInput
 * @property {object} processed
 * @property {object|null} [providerPayment]
 * @property {object|null} [order]
 * @property {object|null} [user]
 * @property {object|null} [subscription]
 * @property {function(string): string} normalizePlanId
 * @property {Date} [now]
 * @property {number} [staleThresholdMs]
 */

/**
 * @param {ClassifyInput} input
 */
export function classifyStuckPayment(input) {
  const {
    processed,
    providerPayment,
    order,
    user,
    subscription,
    normalizePlanId,
    now = new Date(),
    staleThresholdMs = 5 * 60 * 1000,
  } = input;

  const paymentId = String(processed?.paymentId || processed?.id || "");
  const maskedPaymentId = maskPaymentId(paymentId);
  const procStatus = String(processed?.status || "");
  const updatedAt = processed?.updatedAt || processed?.createdAt;
  const age = ageMs(updatedAt, now);

  const base = {
    paymentId,
    maskedPaymentId,
    ageMs: age,
    providerStatus: providerPayment?.status || null,
    orderState: order?.orderStatus || null,
    entitlementState: user?.currentPlanId || null,
  };

  if (procStatus !== "processing") {
    if (procStatus === "approved") {
      return result({
        ...base,
        classification: Classification.ALREADY_GRANTED,
        outcome: ReconciliationOutcome.ALREADY_GRANTED,
        reasonCode: ReasonCode.ALREADY_GRANTED,
        autoRepair: false,
      });
    }
    return result({
      ...base,
      classification: Classification.MANUAL_REVIEW_REQUIRED,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PAYMENT_NOT_ELIGIBLE,
      autoRepair: false,
    });
  }

  if (age != null && age < staleThresholdMs) {
    return result({
      ...base,
      classification: Classification.IN_FLIGHT,
      outcome: ReconciliationOutcome.IN_FLIGHT,
      reasonCode: ReasonCode.PROCESSING_NOT_STALE,
      autoRepair: false,
    });
  }

  if (!providerPayment) {
    return result({
      ...base,
      classification: Classification.PROVIDER_NOT_FOUND,
      outcome: ReconciliationOutcome.PROVIDER_NOT_ELIGIBLE,
      reasonCode: ReasonCode.PAYMENT_NOT_FOUND,
      autoRepair: false,
    });
  }

  const pStatus = String(providerPayment.status || "").toLowerCase();
  const amount = Number(providerPayment.transaction_amount ?? providerPayment.amount ?? NaN);
  const refundCount = Array.isArray(providerPayment.refunds) ? providerPayment.refunds.length : 0;
  const chargeback = pStatus === "charged_back" || providerPayment.status_detail === "charged_back";

  if (pStatus === "refunded" || refundCount > 0) {
    return result({
      ...base,
      classification: Classification.PROVIDER_REFUNDED,
      outcome: ReconciliationOutcome.PROVIDER_NOT_ELIGIBLE,
      reasonCode: ReasonCode.PAYMENT_REFUNDED,
      autoRepair: false,
    });
  }
  if (chargeback) {
    return result({
      ...base,
      classification: Classification.PROVIDER_CHARGEDBACK,
      outcome: ReconciliationOutcome.PROVIDER_NOT_ELIGIBLE,
      reasonCode: ReasonCode.PAYMENT_CHARGEDBACK,
      autoRepair: false,
    });
  }
  if (pStatus === "pending" || pStatus === "in_process") {
    return result({
      ...base,
      classification: Classification.STALE_PROVIDER_PENDING,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PAYMENT_NOT_ELIGIBLE,
      autoRepair: false,
    });
  }
  if (pStatus !== "approved") {
    return result({
      ...base,
      classification: Classification.PROVIDER_REJECTED,
      outcome: ReconciliationOutcome.PROVIDER_NOT_ELIGIBLE,
      reasonCode: ReasonCode.PAYMENT_NOT_ELIGIBLE,
      autoRepair: false,
    });
  }

  if (!Number.isFinite(amount) || amount <= 0) {
    return result({
      ...base,
      classification: Classification.UNRELATED_PAYMENT,
      outcome: ReconciliationOutcome.UNRELATED_PAYMENT,
      reasonCode: ReasonCode.ZERO_AMOUNT,
      autoRepair: false,
    });
  }

  const mapping = resolvePaymentMapping({ processed, order, providerPayment, uidFromUser: user?.uid });
  if (mapping.confidence !== "UNAMBIGUOUS") {
    const noRefs =
      !providerPayment.external_reference &&
      !providerPayment.metadata?.plan_order_id &&
      !processed?.planOrderId;
    if (noRefs && amount <= 0) {
      return result({
        ...base,
        classification: Classification.UNRELATED_PAYMENT,
        outcome: ReconciliationOutcome.UNRELATED_PAYMENT,
        reasonCode: ReasonCode.UNRELATED_PAYMENT,
        autoRepair: false,
      });
    }
    return result({
      ...base,
      classification: Classification.MAPPING_FAILURE,
      outcome: ReconciliationOutcome.MAPPING_FAILURE,
      reasonCode: mapping.confidence === "UNRESOLVED" ? ReasonCode.ORDER_NOT_FOUND : ReasonCode.MAPPING_AMBIGUOUS,
      autoRepair: false,
      mapping: mapping.confidence,
    });
  }

  if (!order) {
    return result({
      ...base,
      classification: Classification.MAPPING_FAILURE,
      outcome: ReconciliationOutcome.MAPPING_FAILURE,
      reasonCode: ReasonCode.ORDER_NOT_FOUND,
      autoRepair: false,
    });
  }

  const purchasedPlan = mapping.planId || order.canonicalPlanId || order.legacyPlanAlias;
  if (!purchasedPlan) {
    return result({
      ...base,
      classification: Classification.MANUAL_REVIEW_REQUIRED,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PLAN_UNKNOWN,
      autoRepair: false,
    });
  }

  const prior = detectPriorGrant({
    user,
    subscription,
    order,
    paymentId,
    purchasedPlan,
    normalizePlanId,
  });
  if (prior.granted) {
    return result({
      ...base,
      classification: Classification.ALREADY_GRANTED,
      outcome: ReconciliationOutcome.ALREADY_GRANTED,
      reasonCode: ReasonCode.ALREADY_GRANTED,
      autoRepair: false,
      priorGrant: prior.reason,
    });
  }

  const approvedAt =
    toDate(providerPayment.date_approved) ||
    toDate(processed?.createdAt) ||
    null;
  if (!approvedAt) {
    return result({
      ...base,
      classification: Classification.MANUAL_REVIEW_REQUIRED,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PERIOD_UNKNOWN,
      autoRepair: false,
    });
  }

  const periodEnd = computePlanPeriodEnd(purchasedPlan, approvedAt, normalizePlanId);
  if (!periodEnd) {
    return result({
      ...base,
      classification: Classification.MANUAL_REVIEW_REQUIRED,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PERIOD_UNKNOWN,
      autoRepair: false,
    });
  }

  if (periodEnd.getTime() < now.getTime()) {
    return result({
      ...base,
      classification: Classification.BUSINESS_DECISION_REQUIRED,
      outcome: ReconciliationOutcome.BUSINESS_DECISION_REQUIRED,
      reasonCode: ReasonCode.PERIOD_EXPIRED,
      autoRepair: false,
      periodStart: approvedAt.toISOString(),
      periodEnd: periodEnd.toISOString(),
    });
  }

  if (String(order.orderStatus || "") !== "PENDENTE") {
    return result({
      ...base,
      classification: Classification.MANUAL_REVIEW_REQUIRED,
      outcome: ReconciliationOutcome.MANUAL_REVIEW_REQUIRED,
      reasonCode: ReasonCode.PAYMENT_NOT_ELIGIBLE,
      autoRepair: false,
    });
  }

  return result({
    ...base,
    classification: Classification.SAFE_REPAIR_CANDIDATE,
    outcome: ReconciliationOutcome.SAFE_REPAIR_CANDIDATE,
    reasonCode: ReasonCode.APPROVED_NOT_GRANTED,
    autoRepair: false,
    uid: mapping.uid,
    planOrderId: mapping.planOrderId,
    purchasedPlan: normalizePlanId(purchasedPlan),
    periodStart: approvedAt.toISOString(),
    periodEnd: periodEnd.toISOString(),
  });
}

function result(obj) {
  return Object.freeze({
    dryRunSafe: true,
    blindWebhookReplay: false,
    ...obj,
  });
}

/**
 * Agrega classificações em resumo sem PII.
 * @param {ReturnType<classifyStuckPayment>[]} cases
 */
export function summarizeMonitorScan(cases) {
  const summary = {
    totalProcessing: cases.length,
    inFlight: 0,
    safeRepairCandidates: 0,
    manualReview: 0,
    alreadyGranted: 0,
    providerRejected: 0,
    mappingFailures: 0,
    businessDecisionRequired: 0,
    unrelatedPayment: 0,
    providerNotEligible: 0,
  };

  for (const c of cases) {
    switch (c.classification) {
      case Classification.IN_FLIGHT:
        summary.inFlight++;
        break;
      case Classification.SAFE_REPAIR_CANDIDATE:
        summary.safeRepairCandidates++;
        break;
      case Classification.ALREADY_GRANTED:
        summary.alreadyGranted++;
        break;
      case Classification.BUSINESS_DECISION_REQUIRED:
        summary.businessDecisionRequired++;
        break;
      case Classification.UNRELATED_PAYMENT:
        summary.unrelatedPayment++;
        break;
      case Classification.MAPPING_FAILURE:
        summary.mappingFailures++;
        break;
      case Classification.PROVIDER_REJECTED:
      case Classification.PROVIDER_REFUNDED:
      case Classification.PROVIDER_CHARGEDBACK:
      case Classification.PROVIDER_NOT_FOUND:
        summary.providerNotEligible++;
        break;
      case Classification.MANUAL_REVIEW_REQUIRED:
      case Classification.STALE_PROVIDER_PENDING:
        summary.manualReview++;
        break;
      default:
        if (c.outcome === ReconciliationOutcome.MANUAL_REVIEW_REQUIRED) summary.manualReview++;
        break;
    }
  }
  return summary;
}
