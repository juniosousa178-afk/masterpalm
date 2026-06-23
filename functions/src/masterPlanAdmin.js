/**
 * Tela Mestre — planos, assinaturas e acessos.
 */

import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { createHash } from "node:crypto";
import { isRootAccountEmail } from "./rootAccounts.js";
import { maskUidForAudit, maskEmailForAudit } from "./planSupportRead.js";
import {
  normalizePlanId,
  resolveEffectivePlanAccess,
  toListUserPlanAccessRow,
  toDateAny,
  maskProviderSubscriptionIdForLog,
  isGrantableCourtesyPlanId,
} from "./planEffectiveAccessResolver.js";

/** Único e-mail autorizado para operações Mestre de planos. */
export const MASTER_PLAN_ADMIN_EMAIL = "masterpalm26@gmail.com";

const DEFAULT_PAGE_SIZE = 25;
const MIN_PAGE_SIZE = 1;
const MAX_PAGE_SIZE = 50;
const MAX_SUBSCRIPTIONS = 25;
export const COURTESY_DOC_ID = "current";
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;

const CONTRACTED_PLAN_IDS_FOR_SUMMARY = [
  "basic_monthly",
  "intermediate_monthly",
  "pro_monthly",
  "pro_yearly",
  "free_limited",
  "free_trial_30d",
  "free_trial_90d",
  "lifetime",
];

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function masterAuditLog(payload) {
  console.log(JSON.stringify({ tag: "[MASTER-PLAN-ADMIN]", ...payload }));
}

/**
 * Autorização exclusiva Mestre: masterpalm26@gmail.com + isRootAccountEmail.
 * @param {import("firebase-functions/v2/https").CallableRequest} request
 * @returns {{ uid: string, email: string }}
 */
export function assertMasterPlanAdmin(request) {
  if (!request?.auth?.uid) {
    masterAuditLog({ evt: "denied", reason: "unauthenticated" });
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const uid = request.auth.uid;
  const email = normalizeEmail(request.auth.token?.email || "");
  if (email !== MASTER_PLAN_ADMIN_EMAIL) {
    masterAuditLog({
      evt: "denied",
      reason: "not_master_plan_admin",
      callerUid: maskUidForAudit(uid),
      callerEmailMasked: maskEmailForAudit(email),
    });
    throw new HttpsError("permission-denied", "Acesso restrito à administração Mestre.");
  }
  if (!isRootAccountEmail(email)) {
    masterAuditLog({
      evt: "denied",
      reason: "not_root_layer",
      callerUid: maskUidForAudit(uid),
    });
    throw new HttpsError("permission-denied", "Perfil root inválido para Mestre.");
  }
  masterAuditLog({
    evt: "authorized",
    callerUid: maskUidForAudit(uid),
    callerEmailMasked: maskEmailForAudit(email),
  });
  return { uid, email };
}

function clampPageSize(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return DEFAULT_PAGE_SIZE;
  const i = Math.floor(n);
  if (i < MIN_PAGE_SIZE) return MIN_PAGE_SIZE;
  if (i > MAX_PAGE_SIZE) return MAX_PAGE_SIZE;
  return i;
}

function extractCourtesyGrant(userData) {
  const cg = userData?.manualCourtesyGrant;
  if (cg && typeof cg === "object") return cg;
  return null;
}

export function courtesyGrantRef(db, uid) {
  return db
    .collection("users")
    .doc(uid)
    .collection("manualCourtesyGrant")
    .doc(COURTESY_DOC_ID);
}

export async function loadCourtesyGrant(db, uid) {
  const snap = await courtesyGrantRef(db, uid).get();
  if (!snap.exists) return null;
  const data = snap.data();
  return data && typeof data === "object" ? data : null;
}

export function validateRequestId(requestId) {
  const id = String(requestId || "").trim();
  if (!REQUEST_ID_PATTERN.test(id)) {
    throw new HttpsError(
      "invalid-argument",
      "Identificador da solicitação inválido. Tente novamente.",
    );
  }
  return id;
}

/** ID determinístico de auditoria — nunca expõe requestId bruto no caminho. */
export function buildAuditActionIdentity(actorUid, targetUid, actionType, requestId) {
  const validatedRequestId = validateRequestId(requestId);
  const fingerprintInput = [
    actorUid,
    targetUid,
    actionType,
    validatedRequestId,
  ].join("\u0000");
  const requestFingerprint = createHash("sha256")
    .update(fingerprintInput, "utf8")
    .digest("hex");
  const actionId = `master_plan_${requestFingerprint}`;
  return { actionId, requestFingerprint };
}

function compactCourtesyForAudit(courtesyGrant) {
  if (!courtesyGrant || typeof courtesyGrant !== "object") return null;
  return {
    active: courtesyGrant.active === true,
    planId: courtesyGrant.planId != null ? normalizePlanId(courtesyGrant.planId) : null,
    type: courtesyGrant.type != null ? String(courtesyGrant.type) : null,
    expiresAt: toDateAny(courtesyGrant.expiresAt),
    permanent: String(courtesyGrant.type || "").toLowerCase() === "permanent",
    reason:
      courtesyGrant.reason != null ? String(courtesyGrant.reason).slice(0, 200) : null,
  };
}

function buildAuditSnapshot({ uid, email, userData, courtesyGrant, now }) {
  const access = resolveEffectivePlanAccess({
    uid,
    email,
    userData,
    now,
    courtesyGrant,
  });
  return {
    contractedPlanId: access.contractedPlanId,
    effectivePlanId: access.effectivePlanId,
    accessSource: access.accessSource,
    effectiveStatus: access.effectiveStatus,
    currentPeriodEnd: access.currentPeriodEnd,
    cancelAtPeriodEnd: access.renewal.cancelAtPeriodEnd === true,
    courtesy: access.courtesy.active
      ? {
          active: true,
          planId: access.courtesy.planId,
          type: access.courtesy.type,
          expiresAt: access.courtesy.expiresAt,
          permanent: access.courtesy.permanent,
        }
      : compactCourtesyForAudit(courtesyGrant),
  };
}

function resolveTargetStoreId(userData) {
  return String(
    userData?.lojaId || userData?.storeId || userData?.store_id || userData?.ownerStoreId || "",
  ).trim();
}

async function resolveTargetUidByEmail(db, email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  const snap = await db.collection("users").where("email", "==", normalized).limit(2).get();
  if (snap.empty) return null;
  if (snap.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      "Há mais de um cadastro com este e-mail. Consulte pelo UID.",
    );
  }
  return snap.docs[0].id;
}

/** Exige exatamente um entre targetUid e targetEmail. */
export async function resolveMasterPlanTargetExclusive(db, data) {
  const { targetUid, targetEmail, hasUid, hasEmail } = normalizeMasterPlanTargetInput(data);
  if (hasUid && hasEmail) {
    throw new HttpsError(
      "invalid-argument",
      "Informe somente UID ou e-mail, não ambos.",
    );
  }
  if (!hasUid && !hasEmail) {
    throw new HttpsError("invalid-argument", "Informe UID ou e-mail para consulta.");
  }
  if (hasUid) return targetUid;
  const resolved = await resolveTargetUidByEmail(db, targetEmail);
  if (!resolved) {
    throw new HttpsError("not-found", "Usuário não encontrado.");
  }
  return resolved;
}

function sanitizeCourtesyForSelf(courtesy) {
  if (!courtesy || courtesy.active !== true) {
    return {
      active: false,
      planId: null,
      type: null,
      startsAt: null,
      expiresAt: null,
      permanent: false,
    };
  }
  return {
    active: true,
    planId: courtesy.planId ?? null,
    type: courtesy.type ?? null,
    startsAt: courtesy.startsAt ?? null,
    expiresAt: courtesy.expiresAt ?? null,
    permanent: courtesy.permanent === true,
  };
}

function sanitizePlanAccessForSelf(planAccess) {
  return {
    contractedPlanId: planAccess.contractedPlanId,
    effectivePlanId: planAccess.effectivePlanId,
    accessSource: planAccess.accessSource,
    effectiveStatus: planAccess.effectiveStatus,
    currentPeriodEnd: planAccess.currentPeriodEnd,
    daysRemaining: planAccess.daysRemaining,
    nextDowngradeAt: planAccess.nextDowngradeAt ?? null,
    renewal: {
      active: planAccess.renewal?.active === true,
      cancelAtPeriodEnd: planAccess.renewal?.cancelAtPeriodEnd === true,
      cancelledAt: planAccess.renewal?.cancelledAt ?? null,
      renewsAt: planAccess.renewal?.renewsAt ?? null,
    },
    subscription: {
      provider: planAccess.subscription?.provider ?? null,
      paymentMethodLabel: planAccess.subscription?.paymentMethodLabel ?? null,
      maskedProviderSubscriptionId:
        planAccess.subscription?.maskedProviderSubscriptionId ?? null,
    },
    courtesy: sanitizeCourtesyForSelf(planAccess.courtesy),
    trial: {
      active: planAccess.trial?.active === true,
      endsAt: planAccess.trial?.endsAt ?? null,
    },
    blockedReason: planAccess.blockedReason ?? null,
  };
}

function sanitizeResultPayload(payload) {
  if (!payload || typeof payload !== "object") return payload;
  const clone = { ...payload };
  if (clone.planAccess) {
    clone.planAccess = sanitizePlanAccessForSelf(clone.planAccess);
  }
  return clone;
}

/** Remove undefined e valores não serializáveis para Callable. */
export function sanitizeCallableResponse(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }
  if (typeof value?.toDate === "function") {
    const d = toDateAny(value);
    return d ? d.toISOString() : null;
  }
  if (Array.isArray(value)) {
    return value
      .map((item) => sanitizeCallableResponse(item))
      .filter((item) => item !== undefined);
  }
  if (typeof value === "object") {
    const out = {};
    for (const [key, raw] of Object.entries(value)) {
      if (raw === undefined) continue;
      const sanitized = sanitizeCallableResponse(raw);
      if (sanitized !== undefined) out[key] = sanitized;
    }
    return out;
  }
  if (typeof value === "number" && !Number.isFinite(value)) return null;
  return value;
}

/** Normaliza entrada de consulta Mestre — ausente, null ou vazio conta como ausente. */
export function normalizeMasterPlanTargetInput(data) {
  const targetUid = String(data?.targetUid ?? "").trim();
  const targetEmail = normalizeEmail(data?.targetEmail ?? "");
  return {
    targetUid,
    targetEmail,
    hasUid: !!targetUid,
    hasEmail: !!targetEmail,
  };
}

function mapSubscriptionDoc(doc) {
  const s = doc.data?.() ?? doc.data ?? {};
  const planId = normalizePlanId(s.planId || s.plan_id || "");
  const providerSub = s.preapprovalId || s.providerSubscriptionId || doc.id || "";
  const created = toDateAny(s.createdAt);
  const updated = toDateAny(s.updatedAt);
  const end = toDateAny(s.currentPeriodEnd || s.current_period_end);
  const src = s.billingSource != null ? String(s.billingSource) : null;
  let provider = null;
  if (src?.toLowerCase().startsWith("mp_") || providerSub) provider = "mercado_pago";

  return {
    id: doc.id,
    planId: planId || null,
    status: s.status != null ? String(s.status) : null,
    kind: s.kind != null ? String(s.kind) : null,
    paymentStatus: s.paymentStatus != null ? String(s.paymentStatus) : null,
    currentPeriodEnd: end ? end.toISOString() : null,
    provider,
    maskedProviderSubscriptionId: providerSub
      ? maskProviderSubscriptionIdForLog(String(providerSub))
      : null,
    createdAt: created ? created.toISOString() : null,
    updatedAt: updated ? updated.toISOString() : null,
  };
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterListUsersPlanAccess({ db, request }) {
  assertMasterPlanAdmin(request);
  const data = request.data || {};
  const pageSize = clampPageSize(data.pageSize);
  const pageToken = String(data.pageToken || "").trim();

  let q = db.collection("users").orderBy("__name__").limit(pageSize + 1);
  if (pageToken) {
    q = q.startAfter(pageToken);
  }

  const snap = await q.get();
  const docs = snap.docs;
  const hasMore = docs.length > pageSize;
  const pageDocs = hasMore ? docs.slice(0, pageSize) : docs;
  const now = new Date();

  const users = await Promise.all(
    pageDocs.map(async (doc) => {
      const d = doc.data() || {};
      const courtesyGrant = await loadCourtesyGrant(db, doc.id);
      return toListUserPlanAccessRow({
        uid: doc.id,
        userData: d,
        email: d.email,
        courtesyGrant,
        now,
      });
    }),
  );

  const nextPageToken = hasMore ? pageDocs[pageDocs.length - 1].id : null;

  return {
    ok: true,
    users,
    pageSize,
    nextPageToken,
    hasMore,
  };
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterGetUserPlanDetails({ db, request }) {
  assertMasterPlanAdmin(request);
  const targetUid = await resolveMasterPlanTargetExclusive(db, request.data || {});

  const userRef = db.collection("users").doc(targetUid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Usuário não encontrado.");
  }

  const d = snap.data() || {};
  const email = normalizeEmail(d.email || "");
  const lojaId = String(
    d.lojaId || d.storeId || d.store_id || d.ownerStoreId || "",
  ).trim();
  const nome = String(d.nome || d.displayName || d.name || "").trim();
  const createdAt = toDateAny(d.createdAt);

  const courtesyGrant = await loadCourtesyGrant(db, targetUid);
  const planAccess = resolveEffectivePlanAccess({
    uid: targetUid,
    email,
    userData: d,
    courtesyGrant,
  });

  let subscriptions = [];
  try {
    const subsSnap = await userRef
      .collection("subscriptions")
      .orderBy("createdAt", "desc")
      .limit(MAX_SUBSCRIPTIONS)
      .get();
    subscriptions = subsSnap.docs.map(mapSubscriptionDoc);
  } catch {
    const subsSnap = await userRef.collection("subscriptions").limit(MAX_SUBSCRIPTIONS).get();
    subscriptions = subsSnap.docs.map(mapSubscriptionDoc);
  }

  return sanitizeCallableResponse({
    ok: true,
    user: {
      uid: targetUid,
      email: email || null,
      lojaId: lojaId || null,
      nome: nome || null,
      createdAt: createdAt ? createdAt.toISOString() : null,
    },
    planAccess: sanitizeCallableResponse(planAccess),
    subscriptions: subscriptions.map((s) => sanitizeCallableResponse(s)),
  });
}

async function safeCount(query) {
  try {
    const agg = await query.count().get();
    return agg.data().count;
  } catch (e) {
    masterAuditLog({
      evt: "summary_count_error",
      err: String(e?.message || e).slice(0, 120),
    });
    return null;
  }
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterGetPlanAccessSummary({ db, request }) {
  assertMasterPlanAdmin(request);
  const usersCol = db.collection("users");

  const totalCanonicalUsers = await safeCount(usersCol);
  const totalRenewalCancelled = await safeCount(
    usersCol.where("cancelAtPeriodEnd", "==", true),
  );

  const totalByContractedPlan = {};
  for (const planId of CONTRACTED_PLAN_IDS_FOR_SUMMARY) {
    const c = await safeCount(usersCol.where("currentPlanId", "==", planId));
    totalByContractedPlan[planId] = c;
  }

  const totalWithManualOverrideLegacy = await safeCount(
    usersCol.where("manualOverride.enabled", "==", true),
  );

  let totalActiveCourtesy = null;
  let totalActiveCourtesyPendingImplementation = false;
  try {
    const cgSnap = await db
      .collectionGroup("manualCourtesyGrant")
      .where("active", "==", true)
      .count()
      .get();
    totalActiveCourtesy = cgSnap.data().count;
  } catch (e) {
    masterAuditLog({
      evt: "summary_courtesy_count_error",
      err: String(e?.message || e).slice(0, 120),
    });
    totalActiveCourtesy = null;
    totalActiveCourtesyPendingImplementation = true;
  }

  return {
    ok: true,
    totalCanonicalUsers,
    totalByContractedPlan,
    totalRenewalCancelled,
    totalActiveCourtesy,
    totalActiveCourtesyPendingImplementation,
    totalWithManualGrantLegacy: {
      pendingImplementation: true,
      reason:
        "Contagem exata exige avaliar untilAt de manual_grant por usuário; adiado para etapa com resolver em batch.",
    },
    totalWithManualOverrideLegacy: {
      count: totalWithManualOverrideLegacy,
      pendingImplementation: totalWithManualOverrideLegacy === null,
      reason:
        totalWithManualOverrideLegacy === null
          ? "count() indisponível neste ambiente."
          : null,
    },
  };
}

function parseCourtesyExpiresAt(raw, type, now) {
  const t = String(type || "").toLowerCase();
  if (t === "permanent") {
    if (raw != null && String(raw).trim() !== "") {
      throw new HttpsError(
        "invalid-argument",
        "Cortesia permanente não deve ter data de expiração.",
      );
    }
    return null;
  }
  const d = toDateAny(raw);
  if (!d || d <= now) {
    throw new HttpsError(
      "invalid-argument",
      "Cortesia temporária exige data final futura.",
    );
  }
  return d;
}

function validateReason(reason) {
  const r = String(reason || "").trim();
  if (!r) {
    throw new HttpsError("invalid-argument", "Motivo é obrigatório.");
  }
  if (r.length > 500) {
    throw new HttpsError("invalid-argument", "Motivo deve ter no máximo 500 caracteres.");
  }
  return r;
}

function assertTargetNotActor(actorUid, targetUid) {
  if (actorUid === targetUid) {
    throw new HttpsError(
      "invalid-argument",
      "Não é permitido conceder cortesia ao próprio administrador Mestre.",
    );
  }
}

function mapAuditActionDoc(doc) {
  const d = doc.data?.() ?? doc.data ?? {};
  return sanitizeCallableResponse({
    actionId: doc.id,
    actionType: d.actionType != null ? String(d.actionType) : null,
    actorUid: d.actorUid != null ? String(d.actorUid) : null,
    actorEmailMasked: maskEmailForAudit(d.actorEmail),
    targetUid: d.targetUid != null ? String(d.targetUid) : null,
    targetEmailMasked: d.targetEmailMasked != null ? String(d.targetEmailMasked) : null,
    targetStoreId: d.targetStoreId != null ? String(d.targetStoreId) : null,
    reason: d.reason != null ? String(d.reason).slice(0, 500) : null,
    beforeSnapshot: d.beforeSnapshot ?? null,
    afterSnapshot: d.afterSnapshot ?? null,
    createdAt: toDateAny(d.createdAt)?.toISOString() ?? null,
    source: d.source != null ? String(d.source) : null,
  });
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterGrantCourtesyAccess({ db, request }) {
  const { uid: actorUid, email: actorEmail } = assertMasterPlanAdmin(request);
  const data = request.data || {};
  const targetUid = String(data.targetUid || "").trim();
  const planId = normalizePlanId(data.planId);
  const type = String(data.type || "").trim().toLowerCase();
  const reason = validateReason(data.reason);
  const requestId = validateRequestId(data.requestId);
  const now = new Date();

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
  }
  assertTargetNotActor(actorUid, targetUid);
  if (!isGrantableCourtesyPlanId(planId)) {
    throw new HttpsError("invalid-argument", "Plano inválido para cortesia.");
  }
  if (type !== "temporary" && type !== "permanent") {
    throw new HttpsError("invalid-argument", "Tipo deve ser temporary ou permanent.");
  }
  const expiresAt = parseCourtesyExpiresAt(data.expiresAt, type, now);

  const { actionId, requestFingerprint } = buildAuditActionIdentity(
    actorUid,
    targetUid,
    "grant_courtesy",
    requestId,
  );
  const auditRef = db.collection("admin_plan_actions").doc(actionId);
  const userRef = db.collection("users").doc(targetUid);
  const courtesyRef = courtesyGrantRef(db, targetUid);

  return db.runTransaction(async (tx) => {
    const priorAudit = await tx.get(auditRef);
    if (priorAudit.exists) {
      const cached = priorAudit.data()?.resultPayload;
      if (cached) {
        return sanitizeResultPayload({ ...cached, idempotentReplay: true });
      }
    }

    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Usuário não encontrado.");
    }
    const userData = userSnap.data() || {};
    const targetEmail = normalizeEmail(userData.email || "");
    const beforeSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: null,
      now,
    });

    const courtesyDoc = {
      schemaVersion: 1,
      active: true,
      planId,
      type,
      startsAt: now,
      expiresAt,
      reason,
      grantedByUid: actorUid,
      grantedByEmail: actorEmail,
      grantedAt: now,
      requestFingerprint,
      updatedAt: now,
      revokedAt: null,
      revokedByUid: null,
      revokedByEmail: null,
      revokeReason: null,
    };

    tx.set(courtesyRef, courtesyDoc, { merge: false });

    const afterSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: courtesyDoc,
      now,
    });

    const result = {
      ok: true,
      idempotentReplay: false,
      actionType: "grant_courtesy",
      targetUid,
      planAccess: sanitizePlanAccessForSelf(
        resolveEffectivePlanAccess({
          uid: targetUid,
          email: targetEmail,
          userData,
          courtesyGrant: courtesyDoc,
          now,
        }),
      ),
      courtesy: afterSnapshot.courtesy,
    };

    tx.set(auditRef, {
      actionType: "grant_courtesy",
      actorUid,
      actorEmail,
      targetUid,
      targetEmailMasked: maskEmailForAudit(targetEmail),
      targetStoreId: resolveTargetStoreId(userData) || null,
      requestFingerprint,
      reason,
      beforeSnapshot,
      afterSnapshot,
      createdAt: FieldValue.serverTimestamp(),
      source: "master_plan_admin",
      resultPayload: sanitizeResultPayload(result),
    });

    return result;
  });
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterUpdateCourtesyAccess({ db, request }) {
  const { uid: actorUid, email: actorEmail } = assertMasterPlanAdmin(request);
  const data = request.data || {};
  const targetUid = String(data.targetUid || "").trim();
  const reason = validateReason(data.reason);
  const requestId = validateRequestId(data.requestId);
  const now = new Date();
  const newExpiresAt = toDateAny(data.expiresAt);

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
  }
  if (!newExpiresAt || newExpiresAt <= now) {
    throw new HttpsError("invalid-argument", "Nova data final deve ser futura.");
  }

  const { actionId, requestFingerprint } = buildAuditActionIdentity(
    actorUid,
    targetUid,
    "extend_courtesy",
    requestId,
  );
  const auditRef = db.collection("admin_plan_actions").doc(actionId);
  const userRef = db.collection("users").doc(targetUid);
  const courtesyRef = courtesyGrantRef(db, targetUid);

  return db.runTransaction(async (tx) => {
    const priorAudit = await tx.get(auditRef);
    if (priorAudit.exists) {
      const cached = priorAudit.data()?.resultPayload;
      if (cached) {
        return sanitizeResultPayload({ ...cached, idempotentReplay: true });
      }
    }

    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Usuário não encontrado.");
    }
    const userData = userSnap.data() || {};
    const targetEmail = normalizeEmail(userData.email || "");

    const courtesySnap = await tx.get(courtesyRef);
    if (!courtesySnap.exists) {
      throw new HttpsError("failed-precondition", "Cortesia ativa não encontrada.");
    }
    const current = courtesySnap.data() || {};
    if (current.active !== true) {
      throw new HttpsError("failed-precondition", "Cortesia não está ativa.");
    }
    if (String(current.type || "").toLowerCase() !== "temporary") {
      throw new HttpsError(
        "failed-precondition",
        "Somente cortesias temporárias podem ser estendidas.",
      );
    }
    const currentExpires = toDateAny(current.expiresAt);
    if (!currentExpires) {
      throw new HttpsError("failed-precondition", "Cortesia temporária sem validade.");
    }
    if (newExpiresAt.getTime() <= currentExpires.getTime()) {
      throw new HttpsError(
        "invalid-argument",
        "Nova validade deve ser posterior à validade atual.",
      );
    }

    const beforeSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: current,
      now,
    });

    const updatedCourtesy = {
      ...current,
      expiresAt: newExpiresAt,
      reason,
      updatedAt: now,
      requestFingerprint,
    };
    tx.set(courtesyRef, updatedCourtesy, { merge: true });

    const afterSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: updatedCourtesy,
      now,
    });

    const result = {
      ok: true,
      idempotentReplay: false,
      actionType: "extend_courtesy",
      targetUid,
      planAccess: sanitizePlanAccessForSelf(
        resolveEffectivePlanAccess({
          uid: targetUid,
          email: targetEmail,
          userData,
          courtesyGrant: updatedCourtesy,
          now,
        }),
      ),
      courtesy: afterSnapshot.courtesy,
    };

    tx.set(auditRef, {
      actionType: "extend_courtesy",
      actorUid,
      actorEmail,
      targetUid,
      targetEmailMasked: maskEmailForAudit(targetEmail),
      targetStoreId: resolveTargetStoreId(userData) || null,
      requestFingerprint,
      reason,
      beforeSnapshot,
      afterSnapshot,
      createdAt: FieldValue.serverTimestamp(),
      source: "master_plan_admin",
      resultPayload: sanitizeResultPayload(result),
    });

    return result;
  });
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterRevokeCourtesyAccess({ db, request }) {
  const { uid: actorUid, email: actorEmail } = assertMasterPlanAdmin(request);
  const data = request.data || {};
  const targetUid = String(data.targetUid || "").trim();
  const reason = validateReason(data.reason);
  const requestId = validateRequestId(data.requestId);
  const now = new Date();

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
  }

  const { actionId, requestFingerprint } = buildAuditActionIdentity(
    actorUid,
    targetUid,
    "revoke_courtesy",
    requestId,
  );
  const auditRef = db.collection("admin_plan_actions").doc(actionId);
  const userRef = db.collection("users").doc(targetUid);
  const courtesyRef = courtesyGrantRef(db, targetUid);

  return db.runTransaction(async (tx) => {
    const priorAudit = await tx.get(auditRef);
    if (priorAudit.exists) {
      const cached = priorAudit.data()?.resultPayload;
      if (cached) {
        return sanitizeResultPayload({ ...cached, idempotentReplay: true });
      }
    }

    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Usuário não encontrado.");
    }
    const userData = userSnap.data() || {};
    const targetEmail = normalizeEmail(userData.email || "");

    const courtesySnap = await tx.get(courtesyRef);
    if (!courtesySnap.exists) {
      throw new HttpsError("failed-precondition", "Cortesia não encontrada.");
    }
    const current = courtesySnap.data() || {};
    if (current.active !== true) {
      throw new HttpsError("failed-precondition", "Cortesia já está inativa.");
    }

    const beforeSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: current,
      now,
    });

    const revokedCourtesy = {
      ...current,
      active: false,
      revokedAt: now,
      revokedByUid: actorUid,
      revokedByEmail: actorEmail,
      revokeReason: reason,
      updatedAt: now,
      requestFingerprint,
    };
    tx.set(courtesyRef, revokedCourtesy, { merge: true });

    const afterSnapshot = buildAuditSnapshot({
      uid: targetUid,
      email: targetEmail,
      userData,
      courtesyGrant: revokedCourtesy,
      now,
    });

    const result = {
      ok: true,
      idempotentReplay: false,
      actionType: "revoke_courtesy",
      targetUid,
      planAccess: sanitizePlanAccessForSelf(
        resolveEffectivePlanAccess({
          uid: targetUid,
          email: targetEmail,
          userData,
          courtesyGrant: revokedCourtesy,
          now,
        }),
      ),
      courtesy: afterSnapshot.courtesy,
    };

    tx.set(auditRef, {
      actionType: "revoke_courtesy",
      actorUid,
      actorEmail,
      targetUid,
      targetEmailMasked: maskEmailForAudit(targetEmail),
      targetStoreId: resolveTargetStoreId(userData) || null,
      requestFingerprint,
      reason,
      beforeSnapshot,
      afterSnapshot,
      createdAt: FieldValue.serverTimestamp(),
      source: "master_plan_admin",
      resultPayload: sanitizeResultPayload(result),
    });

    return result;
  });
}

/**
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runMasterListPlanAuditActions({ db, request }) {
  assertMasterPlanAdmin(request);
  const data = request.data || {};
  const targetUid = String(data.targetUid || "").trim();
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
  }
  const pageSize = clampPageSize(data.pageSize);
  const pageToken = String(data.pageToken || "").trim();

  // Consulta simples por targetUid (sem orderBy) — evita índice composto em produção.
  const snap = await db
    .collection("admin_plan_actions")
    .where("targetUid", "==", targetUid)
    .limit(500)
    .get();

  const sorted = [...snap.docs].sort((a, b) => {
    const ta = toDateAny(a.data()?.createdAt)?.getTime() ?? 0;
    const tb = toDateAny(b.data()?.createdAt)?.getTime() ?? 0;
    return tb - ta;
  });

  let startIdx = 0;
  if (pageToken) {
    const tokenIdx = sorted.findIndex((doc) => doc.id === pageToken);
    startIdx = tokenIdx >= 0 ? tokenIdx + 1 : 0;
  }

  const slice = sorted.slice(startIdx, startIdx + pageSize + 1);
  const hasMore = slice.length > pageSize;
  const pageDocs = hasMore ? slice.slice(0, pageSize) : slice;
  const actions = pageDocs.map(mapAuditActionDoc);
  const nextPageToken = hasMore ? pageDocs[pageDocs.length - 1].id : null;

  return sanitizeCallableResponse({
    ok: true,
    actions,
    pageSize,
    nextPageToken,
    hasMore,
  });
}

/**
 * Acesso efetivo do próprio usuário autenticado (somente leitura).
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {import("firebase-functions/v2/https").CallableRequest} opts.request
 */
export async function runGetMyPlanEffectiveAccess({ db, request }) {
  if (!request?.auth?.uid) {
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const uid = request.auth.uid;
  const email = normalizeEmail(request.auth.token?.email || "");

  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Perfil não encontrado.");
  }
  const userData = snap.data() || {};
  const courtesyGrant = await loadCourtesyGrant(db, uid);
  const planAccess = resolveEffectivePlanAccess({
    uid,
    email: email || normalizeEmail(userData.email || ""),
    userData,
    courtesyGrant,
  });

  return {
    ok: true,
    uid,
    planAccess: sanitizePlanAccessForSelf(planAccess),
  };
}
