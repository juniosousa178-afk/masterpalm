/**
 * Job agendado: reconcilia users/{uid} com plano pago vencido → free_limited
 * reutilizando computePlanState (mesma regra que ensureUserPlan).
 * Não substitui o callable; fecha o gap de quem não abre o app.
 *
 * Lógica testável: src/scheduledExpiredPaidReconcileBatch.js
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { runScheduledReconcileBatch } from "./src/scheduledExpiredPaidReconcileBatch.js";

function initAdminDb() {
  if (!getApps().length) initializeApp();
  return getFirestore();
}

export { classifyExpiredPaidSchedulerDoc } from "./src/scheduledExpiredPaidReconcileBatch.js";

export const scheduledReconcileExpiredPaidPlans = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Sao_Paulo",
    region: "southamerica-east1",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = initAdminDb();
    const now = new Date();
    const ts = Timestamp.fromDate(now);

    let snap;
    try {
      snap = await db
        .collection("users")
        .where("currentPeriodEnd", "<", ts)
        .orderBy("currentPeriodEnd", "asc")
        .limit(400)
        .get();
    } catch (e) {
      console.error(
        JSON.stringify({
          evt: "scheduled_expired_paid_plan_query_error",
          err: String(e?.message || e),
        }),
      );
      throw e;
    }

    const stats = await runScheduledReconcileBatch({ db, now, snap });
    console.log(JSON.stringify(stats));
  },
);
