/**
 * Leitura somente leitura de billing/plano para suporte (root/programador).
 * Sem escrita. users/{uid} é a fonte canônica.
 */

import { HttpsError } from "firebase-functions/v2/https";
import { isRootAccountEmail } from "./rootAccounts.js";

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {typeof import("firebase-admin/auth")} opts.admin
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 * @param {function(string): string} opts.normalizePlanId
 */
export async function runGetPlanBillingSnapshotForSupport({
  db,
  admin: adminMod,
  request,
  normalizePlanId,
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const callerEmail = String(request.auth.token?.email || "")
    .trim()
    .toLowerCase();
  if (!isRootAccountEmail(callerEmail)) {
    console.warn(
      JSON.stringify({
        evt: "plan_support_snapshot_denied",
        callerUid: request.auth.uid,
      }),
    );
    throw new HttpsError(
      "permission-denied",
      "Apenas contas root/programador.",
    );
  }

  const data = request.data || {};
  const targetUidRaw = String(data.targetUid || "").trim();
  const targetEmailRaw = String(data.targetEmail || "").trim();

  if (!targetUidRaw && !targetEmailRaw) {
    throw new HttpsError(
      "invalid-argument",
      "Informe targetUid ou targetEmail.",
    );
  }
  if (targetUidRaw && targetEmailRaw) {
    throw new HttpsError(
      "invalid-argument",
      "Informe apenas um: targetUid ou targetEmail.",
    );
  }

  let uid = targetUidRaw || null;
  let resolvedEmail = "";

  if (targetEmailRaw) {
    const em = targetEmailRaw.toLowerCase();
    try {
      const rec = await adminMod.auth().getUserByEmail(em);
      uid = rec.uid;
      resolvedEmail = (rec.email || em).trim().toLowerCase();
    } catch (e) {
      const code = e?.code || "";
      if (code === "auth/user-not-found") {
        return {
          ok: true,
          found: false,
          reason: "auth_user_not_found",
          snapshot: null,
        };
      }
      throw new HttpsError("internal", String(e?.message || e));
    }
  } else {
    try {
      const rec = await adminMod.auth().getUser(uid);
      resolvedEmail = (rec.email || "").trim().toLowerCase();
    } catch (e) {
      const code = e?.code || "";
      if (code === "auth/user-not-found") {
        return {
          ok: true,
          found: false,
          reason: "auth_user_not_found",
          snapshot: null,
        };
      }
      throw new HttpsError("internal", String(e?.message || e));
    }
  }

  const snap = await db.collection("users").doc(uid).get();
  const d = snap.exists ? snap.data() || {} : {};

  const email = String(d.email || resolvedEmail || "")
    .trim()
    .toLowerCase();
  const rawPlan = String(d.currentPlanId || "");
  const currentPlanId = normalizePlanId(rawPlan);
  const status = String(d.status ?? "active");
  const trialing = d.trialing === true;
  const cpe = d.currentPeriodEnd;
  let currentPeriodEnd = null;
  if (cpe?.toDate) {
    currentPeriodEnd = cpe.toDate().toISOString();
  }

  const cancelAtPeriodEnd =
    d.cancelAtPeriodEnd === true || d.cancel_at_period_end === true;
  const billingVersion =
    d.billingVersion != null && d.billingVersion !== ""
      ? Number(d.billingVersion)
      : null;
  const billingSource =
    d.billingSource != null ? String(d.billingSource) : null;
  const providerSubscriptionId =
    d.providerSubscriptionId != null
      ? String(d.providerSubscriptionId)
      : null;

  const mo = d.manualOverride;
  const manualOverride =
    mo && typeof mo === "object"
      ? {
          enabled: mo.enabled === true,
          planId: mo.planId != null ? String(mo.planId) : null,
        }
      : null;

  const mg = d.manual_grant;
  const manualGrant =
    mg && typeof mg === "object"
      ? {
          present: true,
          type: mg.type != null ? String(mg.type) : null,
        }
      : { present: false, type: null };

  const moEnabled = manualOverride?.enabled === true;
  let usesMercadoRecurringPlanBilling = false;
  if (!moEnabled) {
    if (billingVersion === 2) usesMercadoRecurringPlanBilling = true;
    else if (
      (providerSubscriptionId || "").trim() &&
      String(billingSource || "")
        .toLowerCase()
        .startsWith("mp_")
    ) {
      usesMercadoRecurringPlanBilling = true;
    }
  }

  const labels = [];
  if (email && isRootAccountEmail(email)) labels.push("root");
  if (moEnabled) labels.push("manualOverride");
  if (manualGrant.present) {
    labels.push(
      manualGrant.type
        ? `manual_grant:${manualGrant.type}`
        : "manual_grant",
    );
  }
  if (currentPlanId === "free_limited") labels.push("free_limited");
  if (trialing) labels.push("trialing");
  if (usesMercadoRecurringPlanBilling) labels.push("doc_v2_mp");
  else if (currentPlanId && !moEnabled) labels.push("cancel_renew_path_legado");
  if (!snap.exists) labels.push("sem_doc_users");

  console.log(
    JSON.stringify({
      evt: "plan_support_snapshot_read",
      callerUid: request.auth.uid,
      targetUid: uid,
      usersDocExists: snap.exists,
    }),
  );

  return {
    ok: true,
    found: snap.exists,
    reason: snap.exists ? null : "no_users_document",
    snapshot: {
      uid,
      email: email || resolvedEmail || null,
      currentPlanId,
      status,
      trialing,
      currentPeriodEnd,
      cancelAtPeriodEnd,
      billingVersion,
      billingSource,
      providerSubscriptionId,
      manualOverride,
      manualGrant,
      usesMercadoRecurringPlanBilling,
      interpretationLabels: labels.join(", "),
      usersDocExists: snap.exists,
    },
  };
}
