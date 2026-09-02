/**
 * Monitor — scanner de processed_plan_payments em processing.
 * DEFAULT: DRY_RUN=true, AUTO_EXECUTE_REPAIR=false
 */

import { classifyStuckPayment, summarizeMonitorScan } from "./classifier.js";
import { maskPaymentId } from "./utils.js";

export const DEFAULT_MONITOR_OPTIONS = Object.freeze({
  dryRun: true,
  autoExecuteRepair: false,
  staleThresholdMs: 5 * 60 * 1000,
});

/**
 * @param {object[]} processingRecords — docs com status=processing
 * @param {object} context
 * @param {function(string): Promise<object|null>} context.fetchProviderPayment
 * @param {function(string): Promise<object|null>} context.fetchOrder
 * @param {function(string): Promise<object|null>} context.fetchUser
 * @param {function(string,string): Promise<object|null>} context.fetchSubscription
 * @param {function(string): string} context.normalizePlanId
 * @param {object} [options]
 */
export async function scanProcessingPayments(processingRecords, context, options = {}) {
  const opts = { ...DEFAULT_MONITOR_OPTIONS, ...options };
  const now = options.now || new Date();
  const cases = [];

  for (const rec of processingRecords) {
    const paymentId = String(rec.paymentId || rec.id || "");
    const providerPayment = await context.fetchProviderPayment(paymentId);
    const planOrderId = rec.planOrderId || providerPayment?.external_reference || null;
    const order = planOrderId ? await context.fetchOrder(String(planOrderId)) : null;
    const uid = rec.uid || order?.userId || providerPayment?.metadata?.uid || null;
    const user = uid ? await context.fetchUser(String(uid)) : null;
    const subscription = uid && paymentId ? await context.fetchSubscription(String(uid), paymentId) : null;

    const classification = classifyStuckPayment({
      processed: rec,
      providerPayment,
      order,
      user,
      subscription,
      normalizePlanId: context.normalizePlanId,
      now,
      staleThresholdMs: opts.staleThresholdMs,
    });

    cases.push({
      caseId: rec.caseId || `CASE-${cases.length + 1}`,
      ...classification,
      log: {
        caseId: rec.caseId || `CASE-${cases.length + 1}`,
        maskedPaymentId: maskPaymentId(paymentId),
        classification: classification.classification,
        reasonCode: classification.reasonCode,
        ageMs: classification.ageMs,
        providerStatus: classification.providerStatus,
        orderState: classification.orderState,
        entitlementState: classification.entitlementState,
      },
    });
  }

  return {
    dryRun: opts.dryRun,
    autoExecuteRepair: opts.autoExecuteRepair,
    scannedAt: now.toISOString(),
    cases,
    summary: summarizeMonitorScan(cases),
  };
}
