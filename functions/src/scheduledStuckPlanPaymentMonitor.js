/**
 * Núcleo testável do scheduledMonitorStuckPlanPayments.
 * READ-ONLY: sem writes Firestore/MP; não importa executor.
 *
 * Paginação: oldest stale first (updatedAt asc).
 * Se MAX_PAGES/MAX_RECORDS atingidos → truncated=true (sem starvation silenciosa).
 *
 * Alert Policy futura: cooldown recomendado 24h (RECOMMENDED_ALERT_COOLDOWN_HOURS).
 * Dedup via incidentKey estável (Cloud Logging) — sem write Firestore.
 */

import { Timestamp } from "firebase-admin/firestore";
import { classifyStuckPayment } from "./stuckPaymentReconciliation/classifier.js";
import { Classification, ReasonCode } from "./stuckPaymentReconciliation/reasonCodes.js";
import { maskPaymentId } from "./stuckPaymentReconciliation/utils.js";

export const PROCESSED_PLAN_PAYMENTS_COL = "processed_plan_payments";
export const PLAN_ORDERS_COL_READ = "plan_orders";

export const MONITOR_SCHEDULE = "every 30 minutes";
export const DEFAULT_STALE_THRESHOLD_MINUTES = 60;
export const STALE_THRESHOLD_ENV = "STUCK_PLAN_PAYMENT_STALE_MINUTES";
export const MONITOR_PAGE_SIZE = 50;
export const MONITOR_MAX_PAGES = 4;
export const MONITOR_MAX_RECORDS = 200;
export const MAX_PROVIDER_CONCURRENCY = 5;
export const RECOMMENDED_ALERT_COOLDOWN_HOURS = 24;

/** Classificações que emitem sinal de alerta estruturado. */
export const ALERTABLE_CLASSIFICATIONS = Object.freeze([
  Classification.SAFE_REPAIR_CANDIDATE,
  Classification.STALE_PROVIDER_APPROVED,
  Classification.MAPPING_FAILURE,
  Classification.BUSINESS_DECISION_REQUIRED,
  Classification.PROVIDER_NOT_FOUND,
  Classification.MANUAL_REVIEW_REQUIRED,
]);

/**
 * Resolve threshold em minutos. Ausente/inválido → 60 + warning.
 * @param {NodeJS.ProcessEnv|Record<string,string|undefined>} [env]
 * @param {{ warn?: function }} [log]
 */
export function resolveStaleThresholdMinutes(env = process.env, log = console) {
  const raw = env?.[STALE_THRESHOLD_ENV];
  if (raw == null || String(raw).trim() === "") {
    return DEFAULT_STALE_THRESHOLD_MINUTES;
  }
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0 || !Number.isInteger(n)) {
    log.warn?.(
      JSON.stringify({
        event: "stuck_plan_payment_monitor_threshold_invalid",
        envVar: STALE_THRESHOLD_ENV,
        raw: String(raw).slice(0, 32),
        fallbackMinutes: DEFAULT_STALE_THRESHOLD_MINUTES,
      }),
    );
    return DEFAULT_STALE_THRESHOLD_MINUTES;
  }
  return n;
}

/**
 * Constrói query Firestore bounded (status + stale cutoff + orderBy updatedAt asc).
 * @param {import('firebase-admin/firestore').Firestore} db
 * @param {{ staleCutoffTs: import('firebase-admin/firestore').Timestamp, pageSize?: number, startAfterDoc?: object|null }} opts
 */
export function buildStaleProcessingQuery(db, { staleCutoffTs, pageSize = MONITOR_PAGE_SIZE, startAfterDoc = null }) {
  let q = db
    .collection(PROCESSED_PLAN_PAYMENTS_COL)
    .where("status", "==", "processing")
    .where("updatedAt", "<=", staleCutoffTs)
    .orderBy("updatedAt", "asc")
    .limit(pageSize);
  if (startAfterDoc) {
    q = q.startAfter(startAfterDoc);
  }
  return q;
}

/**
 * Pool de concorrência bounded.
 * @template T,R
 * @param {T[]} items
 * @param {number} concurrency
 * @param {(item: T, index: number) => Promise<R>} fn
 * @returns {Promise<R[]>}
 */
export async function mapWithConcurrency(items, concurrency, fn) {
  const limit = Math.max(1, Math.min(concurrency, items.length || 1));
  const results = new Array(items.length);
  let next = 0;
  async function worker() {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => worker()));
  return results;
}

/**
 * @param {string} paymentId
 * @param {string} classification
 * @param {string} reasonCode
 */
export function buildAlertIncidentKey(paymentId, classification, reasonCode) {
  const caseId = buildCaseId(paymentId);
  return `${caseId}|${classification}|${reasonCode}`;
}

export function buildCaseId(paymentId) {
  return `spp_${maskPaymentId(paymentId)}`;
}

function isAlertable(classification) {
  return ALERTABLE_CLASSIFICATIONS.includes(classification);
}

/**
 * Executa uma passagem read-only do monitor.
 * @param {object} params
 * @param {import('firebase-admin/firestore').Firestore} params.db — somente get/query
 * @param {(paymentId: string) => Promise<object|null>} params.fetchProviderPayment
 * @param {(planId: string) => string} params.normalizePlanId
 * @param {Date} [params.now]
 * @param {NodeJS.ProcessEnv|Record<string,string|undefined>} [params.env]
 * @param {{ log?: function, warn?: function, error?: function }} [params.logger]
 * @param {number} [params.pageSize]
 * @param {number} [params.maxPages]
 * @param {number} [params.maxRecords]
 * @param {number} [params.maxProviderConcurrency]
 * @param {string} [params.runId]
 */
export async function runStuckPlanPaymentMonitor({
  db,
  fetchProviderPayment,
  normalizePlanId,
  now = new Date(),
  env = process.env,
  logger = console,
  pageSize = MONITOR_PAGE_SIZE,
  maxPages = MONITOR_MAX_PAGES,
  maxRecords = MONITOR_MAX_RECORDS,
  maxProviderConcurrency = MAX_PROVIDER_CONCURRENCY,
  runId = `spm_${now.getTime().toString(36)}`,
}) {
  const startedAt = now.toISOString();
  const t0 = Date.now();
  const staleMinutes = resolveStaleThresholdMinutes(env, logger);
  const staleThresholdMs = staleMinutes * 60 * 1000;
  const staleCutoff = new Date(now.getTime() - staleThresholdMs);
  const staleCutoffTs = Timestamp.fromDate(staleCutoff);

  const providerCache = new Map();
  let providerCalls = 0;
  let providerFailures = 0;
  let peakInFlight = 0;
  let inFlight = 0;

  async function fetchProviderCached(paymentId) {
    const pid = String(paymentId || "");
    if (!pid) return null;
    if (providerCache.has(pid)) return providerCache.get(pid);
    inFlight++;
    peakInFlight = Math.max(peakInFlight, inFlight);
    try {
      providerCalls++;
      const payment = await fetchProviderPayment(pid);
      providerCache.set(pid, payment ?? null);
      return payment ?? null;
    } catch (err) {
      providerFailures++;
      providerCache.set(pid, null);
      logger.warn?.(
        JSON.stringify({
          event: "stuck_plan_payment_monitor_provider_error",
          runId,
          maskedPaymentId: maskPaymentId(pid),
          err: String(err?.message || err).slice(0, 200),
        }),
      );
      return null;
    } finally {
      inFlight--;
    }
  }

  /** @type {object[]} */
  const records = [];
  let pagesProcessed = 0;
  let truncated = false;
  let startAfterDoc = null;

  for (let page = 0; page < maxPages; page++) {
    if (records.length >= maxRecords) {
      truncated = true;
      break;
    }
    const remaining = maxRecords - records.length;
    const limit = Math.min(pageSize, remaining);
    const q = buildStaleProcessingQuery(db, {
      staleCutoffTs,
      pageSize: limit,
      startAfterDoc,
    });
    const snap = await q.get();
    pagesProcessed++;
    if (snap.empty || !snap.docs?.length) break;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      records.push({
        id: doc.id,
        paymentId: data.paymentId || doc.id,
        ...data,
      });
    }

    startAfterDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < limit) break;
    if (page === maxPages - 1 && snap.docs.length === limit) {
      truncated = true;
    }
  }

  if (truncated) {
    logger.warn?.(
      JSON.stringify({
        event: "stuck_plan_payment_monitor_alert",
        alertType: "MONITOR_TRUNCATED",
        runId,
        severity: "warn",
        recordsProcessedSoFar: records.length,
        pagesProcessed,
        maxPages,
        maxRecords,
        note: "additional_stale_processing_records_remain",
        incidentKey: `run:${runId}|MONITOR_TRUNCATED`,
        recommendedCooldownHours: RECOMMENDED_ALERT_COOLDOWN_HOURS,
      }),
    );
  }

  const enriched = await mapWithConcurrency(records, maxProviderConcurrency, async (rec) => {
    const paymentId = String(rec.paymentId || rec.id || "");
    const providerPayment = await fetchProviderCached(paymentId);
    const planOrderId =
      rec.planOrderId || providerPayment?.external_reference || null;

    let order = null;
    if (planOrderId) {
      const orderSnap = await db.collection(PLAN_ORDERS_COL_READ).doc(String(planOrderId)).get();
      if (orderSnap.exists) {
        order = { id: planOrderId, planOrderId, ...(orderSnap.data() || {}) };
      }
    }

    const uid = rec.uid || order?.userId || providerPayment?.metadata?.uid || null;
    let user = null;
    let subscription = null;
    if (uid) {
      const userSnap = await db.collection("users").doc(String(uid)).get();
      if (userSnap.exists) user = userSnap.data() || {};
      if (paymentId) {
        const subSnap = await db
          .collection("users")
          .doc(String(uid))
          .collection("subscriptions")
          .doc(paymentId)
          .get();
        if (subSnap.exists) subscription = subSnap.data() || {};
      }
    }

    const classification = classifyStuckPayment({
      processed: rec,
      providerPayment,
      order,
      user,
      subscription,
      normalizePlanId,
      now,
      staleThresholdMs: 0,
    });

    const caseId = buildCaseId(paymentId);
    const ageMinutes =
      classification.ageMs != null ? Math.round(classification.ageMs / 60000) : null;
    const incidentKey = buildAlertIncidentKey(
      paymentId,
      classification.classification,
      classification.reasonCode,
    );

    const caseLog = {
      event: "stuck_plan_payment_monitor_case",
      runId,
      caseId,
      maskedPaymentId: maskPaymentId(paymentId),
      classification: classification.classification,
      reasonCode: classification.reasonCode,
      processingAgeMinutes: ageMinutes,
      providerStatus: classification.providerStatus,
      orderState: classification.orderState,
      entitlementState: classification.entitlementState,
      incidentKey,
    };
    logger.log?.(JSON.stringify(caseLog));

    if (isAlertable(classification.classification)) {
      logger.warn?.(
        JSON.stringify({
          event: "stuck_plan_payment_monitor_alert",
          alertType: classification.classification,
          runId,
          caseId,
          maskedPaymentId: maskPaymentId(paymentId),
          classification: classification.classification,
          reasonCode: classification.reasonCode,
          incidentKey,
          severity: "warn",
          recommendedCooldownHours: RECOMMENDED_ALERT_COOLDOWN_HOURS,
        }),
      );
    }

    return {
      caseId,
      ...classification,
      incidentKey,
      providerFetched: providerPayment != null,
    };
  });

  if (providerFailures >= 2) {
    logger.warn?.(
      JSON.stringify({
        event: "stuck_plan_payment_monitor_alert",
        alertType: "REPEATED_PROVIDER_FAILURE",
        runId,
        severity: "warn",
        providerFailures,
        providerCalls,
        incidentKey: `run:${runId}|REPEATED_PROVIDER_FAILURE`,
        recommendedCooldownHours: RECOMMENDED_ALERT_COOLDOWN_HOURS,
      }),
    );
  }

  const countsByClassification = {};
  const countsByReasonCode = {};
  for (const c of enriched) {
    const cl = c.classification || "UNKNOWN";
    const rc = c.reasonCode || "UNKNOWN";
    countsByClassification[cl] = (countsByClassification[cl] || 0) + 1;
    countsByReasonCode[rc] = (countsByReasonCode[rc] || 0) + 1;
  }

  const summary = {
    event: "stuck_plan_payment_monitor_run",
    runId,
    startedAt,
    durationMs: Date.now() - t0,
    staleThresholdMinutes: staleMinutes,
    staleCutoff: staleCutoff.toISOString(),
    pageSize,
    pagesProcessed,
    recordsProcessed: enriched.length,
    truncated,
    countsByClassification,
    countsByReasonCode,
    providerCalls,
    providerFailures,
    providerCacheSize: providerCache.size,
    peakProviderConcurrency: peakInFlight,
    maxProviderConcurrency,
    firestoreWrites: 0,
    providerWrites: 0,
    executorInvoked: false,
  };
  logger.log?.(JSON.stringify(summary));

  return {
    ...summary,
    cases: enriched,
    ReasonCode,
  };
}
