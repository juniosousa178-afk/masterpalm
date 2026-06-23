/**
 * Tela Mestre — planos, assinaturas e acessos (somente leitura nesta etapa).
 */

import { HttpsError } from "firebase-functions/v2/https";
import { isRootAccountEmail } from "./rootAccounts.js";
import { maskUidForAudit, maskEmailForAudit } from "./planSupportRead.js";
import {
  normalizePlanId,
  resolveEffectivePlanAccess,
  toListUserPlanAccessRow,
  toDateAny,
  maskProviderSubscriptionIdForLog,
} from "./planEffectiveAccessResolver.js";

/** Único e-mail autorizado para operações Mestre de planos. */
export const MASTER_PLAN_ADMIN_EMAIL = "masterpalm26@gmail.com";

const DEFAULT_PAGE_SIZE = 25;
const MIN_PAGE_SIZE = 1;
const MAX_PAGE_SIZE = 50;
const MAX_SUBSCRIPTIONS = 25;

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

  const users = pageDocs.map((doc) => {
    const d = doc.data() || {};
    return toListUserPlanAccessRow({
      uid: doc.id,
      userData: d,
      email: d.email,
      courtesyGrant: extractCourtesyGrant(d),
      now,
    });
  });

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
  const targetUid = String(request.data?.targetUid || "").trim();
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
  }

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

  const planAccess = resolveEffectivePlanAccess({
    uid: targetUid,
    email,
    userData: d,
    courtesyGrant: extractCourtesyGrant(d),
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

  return {
    ok: true,
    user: {
      uid: targetUid,
      email: email || null,
      lojaId: lojaId || null,
      nome: nome || null,
      createdAt: createdAt ? createdAt.toISOString() : null,
    },
    planAccess,
    subscriptions,
  };
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

  return {
    ok: true,
    totalCanonicalUsers,
    totalByContractedPlan,
    totalRenewalCancelled,
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
