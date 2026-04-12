/**
 * Leitura somente leitura de billing/plano para suporte (root/programador).
 * Sem escrita. users/{uid} é a fonte canônica.
 */

import { HttpsError } from "firebase-functions/v2/https";
import { isRootAccountEmail } from "./rootAccounts.js";

/** E-mail do alvo: primeiro caractere local + *** + domínio (auditoria sem expor endereço completo). */
export function maskEmailForAudit(email) {
  const s = String(email || "").trim().toLowerCase();
  if (!s.includes("@")) return null;
  const at = s.indexOf("@");
  const local = s.slice(0, at);
  const domain = s.slice(at + 1);
  if (!domain) return "***";
  const loc = local.length <= 1 ? "*" : `${local[0]}***`;
  return `${loc}@${domain}`;
}

/** UID: prefixo + sufixo curto (evita logar identificador inteiro em cópias acidentais). */
export function maskUidForAudit(uid) {
  const u = String(uid || "").trim();
  if (u.length < 10) return "***";
  return `${u.slice(0, 6)}…${u.slice(-4)}`;
}

/** Nomes estáveis de evento (contrato de auditoria — coberto por testes). */
export const PLAN_SUPPORT_AUDIT_EVT = Object.freeze({
  READ: "plan_support_snapshot_read",
  DENIED: "plan_support_snapshot_denied",
  NOT_FOUND: "plan_support_snapshot_not_found",
  INVALID: "plan_support_snapshot_invalid",
  ERROR: "plan_support_snapshot_error",
});

export function buildAuditDeniedUnauthenticated() {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.DENIED,
    deniedReason: "unauthenticated",
  };
}

export function buildAuditDeniedNotRoot({ callerUid, callerEmail }) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.DENIED,
    deniedReason: "not_root",
    callerUid,
    callerEmail,
  };
}

export function buildAuditInvalid({ callerUid, callerEmail, deniedReason }) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.INVALID,
    callerUid,
    callerEmail,
    deniedReason,
  };
}

export function buildAuditNotFoundEmail({
  callerUid,
  callerEmail,
  targetEmailMasked,
}) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.NOT_FOUND,
    callerUid,
    callerEmail,
    lookupMode: "email",
    targetEmailMasked,
    authLookup: "user_not_found",
  };
}

export function buildAuditNotFoundUid({
  callerUid,
  callerEmail,
  targetUidMasked,
}) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.NOT_FOUND,
    callerUid,
    callerEmail,
    lookupMode: "uid",
    targetUidMasked,
    authLookup: "user_not_found",
  };
}

export function buildAuditError({
  callerUid,
  callerEmail,
  lookupMode,
  err,
}) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.ERROR,
    callerUid,
    callerEmail,
    lookupMode,
    err,
  };
}

export function buildAuditRead({
  callerUid,
  callerEmail,
  lookupMode,
  targetUid,
  targetEmailMasked,
  usersDocExists,
  found,
}) {
  return {
    evt: PLAN_SUPPORT_AUDIT_EVT.READ,
    callerUid,
    callerEmail,
    lookupMode,
    targetUid,
    targetEmailMasked,
    usersDocExists,
    found,
  };
}

function auditLog(payload) {
  console.log(JSON.stringify(payload));
}

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
    auditLog(buildAuditDeniedUnauthenticated());
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const callerUid = request.auth.uid;
  const callerEmail = String(request.auth.token?.email || "")
    .trim()
    .toLowerCase();
  if (!isRootAccountEmail(callerEmail)) {
    auditLog(buildAuditDeniedNotRoot({ callerUid, callerEmail }));
    throw new HttpsError(
      "permission-denied",
      "Apenas contas root/programador.",
    );
  }

  const data = request.data || {};
  const targetUidRaw = String(data.targetUid || "").trim();
  const targetEmailRaw = String(data.targetEmail || "").trim();

  if (!targetUidRaw && !targetEmailRaw) {
    auditLog(
      buildAuditInvalid({
        callerUid,
        callerEmail,
        deniedReason: "missing_target",
      }),
    );
    throw new HttpsError(
      "invalid-argument",
      "Informe targetUid ou targetEmail.",
    );
  }
  if (targetUidRaw && targetEmailRaw) {
    auditLog(
      buildAuditInvalid({
        callerUid,
        callerEmail,
        deniedReason: "both_target_uid_and_email",
      }),
    );
    throw new HttpsError(
      "invalid-argument",
      "Informe apenas um: targetUid ou targetEmail.",
    );
  }

  const lookupMode = targetEmailRaw ? "email" : "uid";

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
        auditLog(
          buildAuditNotFoundEmail({
            callerUid,
            callerEmail,
            targetEmailMasked: maskEmailForAudit(em),
          }),
        );
        return {
          ok: true,
          found: false,
          reason: "auth_user_not_found",
          snapshot: null,
        };
      }
      auditLog(
        buildAuditError({
          callerUid,
          callerEmail,
          lookupMode: "email",
          err: String(e?.code || e?.message || e).slice(0, 120),
        }),
      );
      throw new HttpsError("internal", String(e?.message || e));
    }
  } else {
    try {
      const rec = await adminMod.auth().getUser(uid);
      resolvedEmail = (rec.email || "").trim().toLowerCase();
    } catch (e) {
      const code = e?.code || "";
      if (code === "auth/user-not-found") {
        auditLog(
          buildAuditNotFoundUid({
            callerUid,
            callerEmail,
            targetUidMasked: maskUidForAudit(uid),
          }),
        );
        return {
          ok: true,
          found: false,
          reason: "auth_user_not_found",
          snapshot: null,
        };
      }
      auditLog(
        buildAuditError({
          callerUid,
          callerEmail,
          lookupMode: "uid",
          err: String(e?.code || e?.message || e).slice(0, 120),
        }),
      );
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

  auditLog(
    buildAuditRead({
      callerUid,
      callerEmail,
      lookupMode,
      targetUid: uid,
      targetEmailMasked: maskEmailForAudit(email || resolvedEmail),
      usersDocExists: snap.exists,
      found: snap.exists,
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
