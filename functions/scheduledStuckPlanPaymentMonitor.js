/**
 * Scheduled Function: monitor read-only de processed_plan_payments em processing stale.
 *
 * Cloud Scheduler → scheduledMonitorStuckPlanPayments
 *   → detect / classify / structured log / alert signal
 *   → STOP
 *
 * NÃO importa executor.js. NÃO possui write mode.
 * Repair permanece MANUAL ONLY (autorização separada).
 *
 * Lógica testável: src/scheduledStuckPlanPaymentMonitor.js
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import {
  MONITOR_SCHEDULE,
  runStuckPlanPaymentMonitor,
} from "./src/scheduledStuckPlanPaymentMonitor.js";
import { normalizePlanId } from "./src/planEffectiveAccessResolver.js";

const S_MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

function initAdminDb() {
  if (!getApps().length) initializeApp();
  return getFirestore();
}

/**
 * Fetch Mercado Pago payment — GET only.
 * @param {string} accessToken
 * @param {string} paymentId
 */
async function fetchMercadoPagoPaymentReadonly(accessToken, paymentId) {
  const pid = String(paymentId || "").trim();
  if (!pid) return null;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 12_000);
  try {
    const r = await fetch(`https://api.mercadopago.com/v1/payments/${encodeURIComponent(pid)}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: ctrl.signal,
    });
    if (r.status === 404) return null;
    if (!r.ok) {
      throw new Error(`mp_http_${r.status}`);
    }
    return await r.json();
  } finally {
    clearTimeout(timer);
  }
}

export const scheduledMonitorStuckPlanPayments = onSchedule(
  {
    schedule: MONITOR_SCHEDULE,
    timeZone: "America/Sao_Paulo",
    region: "southamerica-east1",
    memory: "512MiB",
    timeoutSeconds: 300,
    secrets: [S_MP_ACCESS_TOKEN],
  },
  async () => {
    const db = initAdminDb();
    const token = String((await S_MP_ACCESS_TOKEN.value()) || "").trim();
    if (!token) {
      console.error(
        JSON.stringify({
          event: "stuck_plan_payment_monitor_token_missing",
          flow: "scheduledMonitorStuckPlanPayments",
        }),
      );
      return;
    }

    await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId,
      fetchProviderPayment: (paymentId) => fetchMercadoPagoPaymentReadonly(token, paymentId),
    });
  },
);

export { MONITOR_SCHEDULE };
