/**
 * Troca de plano recorrente MasterPalm (MP preapproval) — apenas planos do app.
 * external_reference: mpchg|{uid}|{changeId}|{requestedPlanId}
 */

import crypto from "node:crypto";
import { FieldValue, Timestamp, FieldPath } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import {
  mpCreatePreapproval,
  mpPutPreapproval,
  mpGetPreapproval,
  isRecurringPlanBillingEnabled,
  resolveCurrentPeriodEndMillis,
} from "./mpPlanRecurring.js";

export const PLAN_CHANGE_INTENTS = "plan_change_intents";

export function parseExternalReferenceMpPlanChange(externalRef) {
  const s = String(externalRef || "").trim();
  if (!s.startsWith("mpchg|")) return null;
  const parts = s.split("|");
  if (parts.length < 4) return null;
  const uid = String(parts[1] || "").trim();
  const changeId = String(parts[2] || "").trim();
  const requestedPlanId = String(parts.slice(3).join("|") || "").trim();
  if (!uid || !changeId || !requestedPlanId) return null;
  return { uid, changeId, requestedPlanId };
}

function hasStoreContextInPlanPayload(payload) {
  if (!payload || typeof payload !== "object") return false;
  const keys = [
    "lojaId",
    "storeId",
    "tenantId",
    "mpAccessToken",
    "accessToken",
    "mpToken",
    "payments",
    "payments_public",
  ];
  return keys.some((k) => payload[k] != null && String(payload[k]).trim() !== "");
}

/** Exportado para testes e reuso. */
export function isUserEligibleForPlanChange(userData) {
  const planStatus = String(userData?.planStatus || "").toLowerCase();
  const status = String(userData?.status || "").toLowerCase();
  const billingMode = String(userData?.billingMode || "").toLowerCase();
  const subId = String(userData?.providerSubscriptionId || "").trim();
  const activeLike =
    planStatus === "active" ||
    status === "active" ||
    planStatus === "trialing" ||
    status === "trialing";
  const endMs = resolveCurrentPeriodEndMillis(userData);
  const periodFuture = endMs != null && endMs > Date.now();
  return activeLike && billingMode === "recurring" && !!subId && periodFuture;
}

function unitPriceForPlanLocal(canonical, prices) {
  const c = String(canonical || "").toLowerCase();
  if (c === "basic_monthly") return prices.PRICE_BASIC_MONTHLY;
  if (c === "intermediate_monthly") return prices.PRICE_INTERMEDIATE_MONTHLY;
  if (c === "pro_yearly") return prices.PRICE_PRO_YEARLY;
  if (c === "pro_monthly") return prices.PRICE_PRO_MONTHLY;
  return prices.PRICE_PRO_MONTHLY;
}

function autoRecurringForPlan(canonical, prices) {
  const c = String(canonical || "").toLowerCase();
  const amount = unitPriceForPlanLocal(c, prices);
  if (c === "pro_yearly") {
    return {
      frequency: 1,
      frequency_type: "years",
      transaction_amount: amount,
      currency_id: "BRL",
    };
  }
  return {
    frequency: 1,
    frequency_type: "months",
    transaction_amount: amount,
    currency_id: "BRL",
  };
}

function buildPlanChangeSubscriptionFields({
  uid,
  email,
  canonicalPlanId,
  preapprovalId,
  initPoint,
  externalReference,
  billingCycle,
  autoRecurring,
  changeId,
  fromPlanId,
  oldPreapprovalId,
}) {
  const ar = autoRecurring || {};
  return {
    provider: "mercado_pago",
    billingMode: "recurring",
    source: "createPlanChangeSubscription",
    isPlanChange: true,
    changeId,
    uid,
    email,
    fromPlanId,
    planId: canonicalPlanId,
    canonicalPlanId,
    oldPreapprovalId,
    preapprovalId,
    providerSubscriptionId: preapprovalId,
    mercadoPagoPreapprovalId: preapprovalId,
    subscriptionId: preapprovalId,
    externalReference,
    initPoint,
    amount: ar.transaction_amount ?? null,
    currency: ar.currency_id || "BRL",
    frequency: ar.frequency ?? null,
    frequencyType: ar.frequency_type ?? null,
    billingCycle,
    status: "pending",
    paymentStatus: "pending",
    activatedAt: null,
    currentPeriodStart: null,
    currentPeriodEnd: null,
  };
}

/** paymentStatus que nunca qualifica como assinatura ativa para troca. */
const _OLD_SUB_INVALID_PAYMENT_STATUS = new Set([
  "abandoned",
  "pending",
  "replaced",
  "rejected",
  "cancelled",
  "canceled",
  "failed",
]);

/**
 * Valida se o documento users/{uid}/subscriptions/{id} representa a assinatura recorrente
 * atualmente ativa do currentPlanId (para usar como oldPreapprovalId na troca).
 * Exportado para testes.
 */
export function subscriptionQualifiesAsActiveOldForPlanChange(
  subData,
  currentPlanCanonical,
  normalizePlanId,
  nowMs,
) {
  const status = subData
    ? String(subData.status || "").toLowerCase()
    : "missing_doc";
  const paymentStatus = subData
    ? String(subData.paymentStatus || "").toLowerCase()
    : "missing_doc";
  if (!subData || typeof subData !== "object") {
    return { ok: false, status, paymentStatus, reason: "no_document" };
  }
  if (status !== "active") {
    return { ok: false, status, paymentStatus, reason: "status_not_active" };
  }
  if (_OLD_SUB_INVALID_PAYMENT_STATUS.has(paymentStatus)) {
    return { ok: false, status, paymentStatus, reason: "payment_status_invalid" };
  }
  if (paymentStatus !== "approved" && paymentStatus !== "active") {
    return { ok: false, status, paymentStatus, reason: "payment_status_not_approved" };
  }
  const bm = String(subData.billingMode || "").toLowerCase();
  if (bm !== "recurring") {
    return { ok: false, status, paymentStatus, reason: "billing_mode_not_recurring" };
  }
  const subPlan = normalizePlanId(
    String(subData.planId || subData.canonicalPlanId || "").trim(),
  );
  if (!subPlan || subPlan !== currentPlanCanonical) {
    return { ok: false, status, paymentStatus, reason: "plan_mismatch" };
  }
  const endMs = resolveCurrentPeriodEndMillis(subData);
  if (endMs == null || endMs <= nowMs) {
    return { ok: false, status, paymentStatus, reason: "period_not_future" };
  }
  return { ok: true, status, paymentStatus, reason: null };
}

/**
 * Resolve o preapprovalId da assinatura realmente ativa para o currentPlanId do usuário.
 * Ignora IDs no documento do usuário se o subdoc não for active/approved/recorrente/plano ok.
 */
export async function resolveOldPreapprovalIdForPlanChange(
  db,
  uid,
  userData,
  normalizePlanId,
  nowMs = Date.now(),
) {
  const currentPlanId = normalizePlanId(String(userData?.currentPlanId || ""));
  const candidates = [];
  for (const key of ["providerSubscriptionId", "mercadoPagoPreapprovalId", "subscriptionId"]) {
    const v = String(userData?.[key] || "").trim();
    if (v && !candidates.includes(v)) candidates.push(v);
  }

  console.info("[PLAN_CHANGE_OLD_SUB_RESOLVE_START]", {
    uid,
    currentPlanId,
    candidatePreapprovalIds: candidates,
  });

  const userRef = db.collection("users").doc(uid);
  const subsSnap = await userRef.collection("subscriptions").get();
  const subById = new Map(subsSnap.docs.map((d) => [d.id, d.data() || {}]));

  const tryCandidate = (id) => {
    const subData = subById.get(id);
    const q = subscriptionQualifiesAsActiveOldForPlanChange(
      subData,
      currentPlanId,
      normalizePlanId,
      nowMs,
    );
    return q.ok ? { id, status: q.status, paymentStatus: q.paymentStatus } : null;
  };

  for (const c of candidates) {
    const hit = tryCandidate(c);
    if (hit) {
      console.info("[PLAN_CHANGE_OLD_SUB_RESOLVE_SUCCESS]", {
        uid,
        currentPlanId,
        candidatePreapprovalId: c,
        resolvedOldPreapprovalId: hit.id,
        subStatus: hit.status,
        subPaymentStatus: hit.paymentStatus,
      });
      return hit.id;
    }
  }

  let best = null;
  let bestEnd = -1;
  for (const [id, data] of subById) {
    const q = subscriptionQualifiesAsActiveOldForPlanChange(
      data,
      currentPlanId,
      normalizePlanId,
      nowMs,
    );
    if (!q.ok) continue;
    const endMs = resolveCurrentPeriodEndMillis(data) ?? 0;
    if (endMs > bestEnd) {
      bestEnd = endMs;
      best = { id, status: q.status, paymentStatus: q.paymentStatus };
    }
  }

  if (best) {
    console.info("[PLAN_CHANGE_OLD_SUB_RESOLVE_SUCCESS]", {
      uid,
      currentPlanId,
      candidatePreapprovalId: null,
      resolvedOldPreapprovalId: best.id,
      subStatus: best.status,
      subPaymentStatus: best.paymentStatus,
      via: "subscription_collection_scan",
    });
    return best.id;
  }

  console.error("[PLAN_CHANGE_OLD_SUB_RESOLVE_ERROR]", {
    uid,
    currentPlanId,
    candidatePreapprovalIds: candidates,
    resolvedOldPreapprovalId: null,
    reason: "no_valid_active_subscription",
  });
  return null;
}

export async function runCreatePlanChangeSubscription({
  db,
  request,
  token,
  webBase,
  prices,
  planTitleForMp,
  normalizePlanId,
}) {
  if (!isRecurringPlanBillingEnabled()) {
    throw new HttpsError("failed-precondition", "RECURRING_PLAN_BILLING_DISABLED");
  }
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Faça login para continuar.");
  }
  const data = request.data || {};
  if (hasStoreContextInPlanPayload(data)) {
    throw new HttpsError("invalid-argument", "Payload inválido: contexto de loja não é permitido.");
  }

  const uid = request.auth.uid;
  const email = String(request.auth.token?.email || "").trim().toLowerCase();
  const planRaw = String(data.requestedPlanId || data.plan || data.planId || "")
    .trim()
    .toLowerCase();
  const allowed = new Set([
    "mensal",
    "anual",
    "basic_monthly",
    "intermediate_monthly",
    "pro_monthly",
    "pro_yearly",
  ]);
  if (!allowed.has(planRaw)) {
    throw new HttpsError("invalid-argument", "requestedPlanId inválido para troca de plano.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const ud = userSnap.exists ? userSnap.data() || {} : {};
  if (!isUserEligibleForPlanChange(ud)) {
    throw new HttpsError(
      "failed-precondition",
      "Não há assinatura recorrente ativa para trocar. Use assinatura comum.",
    );
  }

  const currentPlan = normalizePlanId(String(ud.currentPlanId || ""));
  const canonical = normalizePlanId(planRaw);

  if (canonical === currentPlan) {
    return {
      ok: true,
      alreadyActive: true,
      message: "Você já está com este plano ativo.",
    };
  }

  const oldPreapprovalId = await resolveOldPreapprovalIdForPlanChange(
    db,
    uid,
    ud,
    normalizePlanId,
    Date.now(),
  );
  if (!oldPreapprovalId) {
    throw new HttpsError(
      "failed-precondition",
      "Não foi encontrada uma assinatura ativa válida para troca de plano.",
    );
  }

  const changeId = crypto.randomUUID().replace(/-/g, "");
  const billingCycle = canonical === "pro_yearly" ? "annual" : "monthly";
  const autoRecurring = autoRecurringForPlan(canonical, prices);
  const externalReference = `mpchg|${uid}|${changeId}|${canonical}`;

  console.info("[PLAN_CHANGE_CREATE_START]", {
    uid,
    fromPlanId: currentPlan,
    requestedPlanId: canonical,
    changeId,
    oldPreapprovalId,
    newPreapprovalId: null,
  });

  const intentRef = db.collection(PLAN_CHANGE_INTENTS).doc(changeId);
  await intentRef.set(
    {
      uid,
      email,
      fromPlanId: currentPlan,
      requestedPlanId: canonical,
      oldPreapprovalId,
      status: "pending",
      paymentStatus: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "createPlanChangeSubscription",
    },
    { merge: true },
  );

  const returnUrl =
    String(data.returnUrl || "").trim() ||
    `${webBase.replace(/\/$/, "")}/assinatura/troca/${changeId}/retorno`;

  const start = new Date();
  const end = new Date(start);
  end.setFullYear(end.getFullYear() + 10);

  const body = {
    reason: `${planTitleForMp(canonical)} (troca de plano)`,
    external_reference: externalReference,
    payer_email: email || undefined,
    auto_recurring: {
      ...autoRecurring,
      start_date: start.toISOString(),
      end_date: end.toISOString(),
    },
    back_url: returnUrl,
    status: "pending",
  };

  let mpRes;
  try {
    mpRes = await mpCreatePreapproval(token, body);
  } catch (e) {
    console.error("[PLAN_CHANGE_CREATE_ERROR]", {
      uid,
      fromPlanId: currentPlan,
      requestedPlanId: canonical,
      changeId,
      oldPreapprovalId,
      err: String(e?.message || e),
    });
    await intentRef.set(
      {
        status: "error",
        paymentStatus: "error",
        mpError: String(e?.message || e).slice(0, 400),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw new HttpsError("internal", e?.message || "Erro ao criar troca de plano no Mercado Pago.");
  }

  const newPreapprovalId = String(mpRes.id || "");
  const initPoint = String(mpRes.init_point || mpRes.initPoint || "").trim();
  if (!newPreapprovalId || !initPoint) {
    console.error("[PLAN_CHANGE_CREATE_ERROR]", {
      uid,
      changeId,
      err: "resposta_mp_incompleta",
    });
    throw new HttpsError("internal", "Resposta inválida do Mercado Pago (troca de plano).");
  }

  const subPath = `users/${uid}/subscriptions/${newPreapprovalId}`;
  const subFields = buildPlanChangeSubscriptionFields({
    uid,
    email,
    canonicalPlanId: canonical,
    preapprovalId: newPreapprovalId,
    initPoint,
    externalReference,
    billingCycle,
    autoRecurring,
    changeId,
    fromPlanId: currentPlan,
    oldPreapprovalId,
  });

  const batch = db.batch();
  const subRef = userRef.collection("subscriptions").doc(newPreapprovalId);
  batch.set(
    subRef,
    {
      ...subFields,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    intentRef,
    {
      newPreapprovalId,
      newSubscriptionPath: subPath,
      initPoint,
      externalReference,
      status: "pending",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    userRef,
    {
      pendingPlanChangeId: changeId,
      pendingPlanChangeFromPlanId: currentPlan,
      pendingPlanChangeToPlanId: canonical,
      pendingPlanChangePreapprovalId: newPreapprovalId,
      pendingPlanChangeStatus: "pending",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();

  console.info("[PLAN_CHANGE_CREATE_SUCCESS]", {
    uid,
    fromPlanId: currentPlan,
    requestedPlanId: canonical,
    changeId,
    oldPreapprovalId,
    newPreapprovalId,
  });

  return {
    ok: true,
    initPoint,
    changeId,
    newPreapprovalId,
    externalReference,
    fromPlanId: currentPlan,
    requestedPlanId: canonical,
  };
}

/**
 * Processa webhook de pagamento com external_reference mpchg|...
 * @param {object} opts
 * @param {import("firebase-admin/firestore").Firestore} opts.db
 * @param {string} opts.token MP platform
 * @param {(d: object) => string} opts.normalizePlanId
 * @param {*} opts.nowTs
 * @param {(d: Date, n: number) => Date} opts.addMonths
 * @param {(d: Date, n: number) => Date} opts.addYears
 */
export async function processPlanChangePaymentWebhook({
  db,
  payment,
  paymentId,
  token,
  normalizePlanId,
  nowTs,
  addMonths,
  addYears,
}) {
  const externalRef = String(payment?.external_reference || "").trim();
  const parsed = parseExternalReferenceMpPlanChange(externalRef);
  if (!parsed) return { handled: false };

  const { uid, changeId, requestedPlanId } = parsed;
  const canonical = normalizePlanId(requestedPlanId);
  const payId = String(paymentId || "");
  const status = String(payment?.status || "").toLowerCase();

  const intentRef = db.collection(PLAN_CHANGE_INTENTS).doc(changeId);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) {
    console.error("[PLAN_CHANGE_ACTIVATE_ERROR]", { err: "intent_not_found", changeId, uid });
    return { handled: true };
  }
  const intent = intentSnap.data() || {};
  if (String(intent.uid || "") !== uid) {
    console.error("[PLAN_CHANGE_ACTIVATE_ERROR]", { err: "uid_mismatch", changeId });
    return { handled: true };
  }

  const oldPreapprovalId = String(intent.oldPreapprovalId || "").trim();
  let newPreapprovalId = String(
    payment?.preapproval_id || payment?.preapproval?.id || intent.newPreapprovalId || "",
  ).trim();

  if (status !== "approved") {
    await intentRef.set(
      {
        status: status === "pending" || status === "in_process" ? "pending" : "failed",
        paymentStatus: status,
        rawPaymentStatus: String(payment?.status || ""),
        lastPaymentId: payId,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    return { handled: true };
  }

  if (!newPreapprovalId) {
    console.error("[PLAN_CHANGE_ACTIVATE_ERROR]", {
      uid,
      changeId,
      err: "new_preapproval_missing",
      paymentId: payId,
    });
    return { handled: true };
  }

  console.info("[PLAN_CHANGE_PAYMENT_CONFIRMED]", {
    uid,
    planId: canonical,
    paymentId: payId,
    preapprovalId: newPreapprovalId,
    changeId,
    oldPreapprovalId,
  });

  const processedRef = db.collection("processed_plan_payments").doc(payId);
  let skipApproved = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(processedRef);
    const d = snap.exists ? snap.data() || {} : {};
    if (snap.exists && d.status === "approved") {
      skipApproved = true;
      return;
    }
    tx.set(
      processedRef,
      {
        paymentId: payId,
        status: "processing",
        rawStatus: String(payment?.status || ""),
        kind: "plan_change",
        changeId,
        updatedAt: nowTs,
        createdAt: d.createdAt || nowTs,
      },
      { merge: true },
    );
  });
  if (skipApproved) {
    console.info("[PLAN_CHANGE_ALREADY_PROCESSED]", {
      uid,
      changeId,
      paymentId: payId,
      preapprovalId: newPreapprovalId,
    });
    return { handled: true };
  }

  const userRef = db.collection("users").doc(uid);
  const newSubRef = userRef.collection("subscriptions").doc(newPreapprovalId);
  const oldSubRef = oldPreapprovalId
    ? userRef.collection("subscriptions").doc(oldPreapprovalId)
    : null;

  const newSubSnap = await newSubRef.get();
  const nsd = newSubSnap.exists ? newSubSnap.data() || {} : {};
  if (String(nsd.status || "").toLowerCase() === "active" && String(nsd.lastPaymentId || "") === payId) {
    console.info("[PLAN_CHANGE_ALREADY_PROCESSED]", {
      uid,
      changeId,
      paymentId: payId,
      preapprovalId: newPreapprovalId,
    });
    await processedRef.set(
      { status: "approved", processedAt: nowTs, kind: "plan_change", changeId },
      { merge: true },
    );
    return { handled: true };
  }

  const now = new Date();
  const isAnnual = canonical === "pro_yearly";
  const periodEnd = isAnnual ? addYears(now, 1) : addMonths(now, 1);
  const periodStartTs = Timestamp.fromDate(now);
  const periodEndTs = Timestamp.fromDate(periodEnd);

  console.info("[PLAN_CHANGE_ACTIVATE_START]", {
    uid,
    fromPlanId: intent.fromPlanId,
    requestedPlanId: canonical,
    paymentId: payId,
    changeId,
    oldPreapprovalId,
    newPreapprovalId,
  });

  try {
    const batch = db.batch();
    batch.set(
      userRef,
      {
        status: "active",
        planStatus: "active",
        billingMode: "recurring",
        billingVersion: 2,
        billingSource: "mp_recurring_plan_change_approved",
        currentPlanId: canonical,
        currentPeriodStart: periodStartTs,
        currentPeriodEnd: periodEndTs,
        provider: "mercado_pago",
        providerSubscriptionId: newPreapprovalId,
        mercadoPagoPreapprovalId: newPreapprovalId,
        subscriptionId: newPreapprovalId,
        previousPlanId: String(intent.fromPlanId || ""),
        previousSubscriptionId: oldPreapprovalId || null,
        lastPlanChangeId: changeId,
        planLastPaymentId: payId,
        planLastSyncedAt: nowTs,
        pendingPlanChangeId: null,
        pendingPlanChangeFromPlanId: null,
        pendingPlanChangeToPlanId: null,
        pendingPlanChangePreapprovalId: null,
        pendingPlanChangeStatus: null,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    batch.set(
      newSubRef,
      {
        status: "active",
        paymentStatus: "approved",
        planId: canonical,
        canonicalPlanId: canonical,
        lastPaymentId: payId,
        activatedAt: nowTs,
        currentPeriodStart: periodStartTs,
        currentPeriodEnd: periodEndTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    if (oldSubRef) {
      batch.set(
        oldSubRef,
        {
          status: "replaced",
          paymentStatus: "replaced",
          replacedByPreapprovalId: newPreapprovalId,
          replacedByPlanChangeId: changeId,
          replacedAt: nowTs,
          updatedAt: nowTs,
        },
        { merge: true },
      );
    }
    batch.set(
      intentRef,
      {
        status: "completed",
        paymentStatus: "approved",
        lastPaymentId: payId,
        activatedAt: nowTs,
        completedAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await batch.commit();
  } catch (e) {
    console.error("[PLAN_CHANGE_ACTIVATE_ERROR]", {
      uid,
      changeId,
      paymentId: payId,
      err: String(e?.message || e),
    });
    throw e;
  }

  console.info("[PLAN_CHANGE_USER_ACTIVATED]", {
    uid,
    planId: canonical,
    paymentId: payId,
    changeId,
    newPreapprovalId,
  });

  let oldCancellationStatus = "skipped";
  let requiresManualCancellation = false;
  let oldCancellationError = null;

  if (oldPreapprovalId && oldPreapprovalId !== newPreapprovalId) {
    console.info("[PLAN_CHANGE_OLD_SUB_CANCEL_START]", {
      uid,
      oldPreapprovalId,
      newPreapprovalId,
      changeId,
    });
    try {
      await mpPutPreapproval(token, oldPreapprovalId, { status: "cancelled" });
      oldCancellationStatus = "cancelled";
      console.info("[PLAN_CHANGE_OLD_SUB_CANCEL_SUCCESS]", {
        uid,
        oldPreapprovalId,
        changeId,
      });
    } catch (e) {
      oldCancellationStatus = "error";
      requiresManualCancellation = true;
      oldCancellationError = String(e?.message || e).slice(0, 400);
      console.error("[PLAN_CHANGE_OLD_SUB_CANCEL_ERROR]", {
        uid,
        oldPreapprovalId,
        changeId,
        err: oldCancellationError,
      });
    }

    const patch = {
      oldCancellationStatus,
      requiresManualCancellation,
      updatedAt: nowTs,
    };
    if (oldCancellationError) patch.oldCancellationError = oldCancellationError;

    await intentRef.set(patch, { merge: true });
    if (oldSubRef) {
      await oldSubRef.set(patch, { merge: true });
    }
    if (requiresManualCancellation) {
      await userRef.set(
        {
          planChangeRequiresManualCancellation: true,
          planChangeManualCancellationHint: {
            oldPreapprovalId,
            changeId,
            error: oldCancellationError,
            at: nowTs,
          },
          updatedAt: nowTs,
        },
        { merge: true },
      );
    }
  }

  await processedRef.set(
    {
      paymentId: payId,
      processedAt: nowTs,
      uid,
      status: "approved",
      rawStatus: String(payment?.status || ""),
      kind: "plan_change",
      changeId,
    },
    { merge: true },
  );

  return { handled: true };
}

/** Estados finais de preapproval MP que encerram a troca sem ativar o plano novo. */
const _PLAN_CHANGE_PREAPPROVAL_TERMINAL_FAIL = new Set([
  "cancelled",
  "canceled",
  "rejected",
  "failed",
]);

function _terminalPlanChangeIntentFields(mpStatus) {
  const s = String(mpStatus || "").toLowerCase();
  if (s === "canceled") {
    return { status: "cancelled", paymentStatus: "cancelled" };
  }
  if (s === "cancelled") {
    return { status: "cancelled", paymentStatus: "cancelled" };
  }
  if (s === "rejected") {
    return { status: "rejected", paymentStatus: "rejected" };
  }
  if (s === "failed") {
    return { status: "failed", paymentStatus: "failed" };
  }
  return { status: "failed", paymentStatus: "failed" };
}

/**
 * Localiza uid/changeId quando o webhook de preapproval é de uma troca de plano.
 * 1) plan_change_intents.newPreapprovalId
 * 2) collectionGroup subscriptions/{preapprovalId} com isPlanChange
 */
export async function findPlanChangeRoutingForPreapproval(db, preapprovalId) {
  const preId = String(preapprovalId || "").trim();
  if (!preId) return null;

  const iq = await db
    .collection(PLAN_CHANGE_INTENTS)
    .where("newPreapprovalId", "==", preId)
    .limit(25)
    .get();

  if (!iq.empty) {
    let best = null;
    let bestScore = -1;
    for (const d of iq.docs) {
      const data = d.data() || {};
      const u = String(data.uid || "").trim();
      if (!u) continue;
      const st = String(data.status || "").toLowerCase();
      const score = st === "pending" ? 2 : st === "failed" || st === "error" ? 0 : 1;
      if (score > bestScore) {
        bestScore = score;
        best = { uid: u, changeId: d.id, source: "plan_change_intents" };
      }
    }
    if (best) return best;
  }

  const subs = await db
    .collectionGroup("subscriptions")
    .where(FieldPath.documentId(), "==", preId)
    .limit(5)
    .get();

  for (const doc of subs.docs) {
    const data = doc.data() || {};
    if (data.isPlanChange !== true) continue;
    const u = String(data.uid || "").trim();
    if (!u) continue;
    const m = doc.ref.path.match(/^users\/([^/]+)\/subscriptions\//);
    if (!m || m[1] !== u) continue;
    const chg = String(data.changeId || "").trim();
    return { uid: u, changeId: chg || null, source: "subscriptions_doc" };
  }

  return null;
}

async function _applyPlanChangePreapprovalTerminalFailure({
  db,
  uid,
  resolvedChangeId,
  preapprovalId,
  mpStatus,
  nowTs,
}) {
  const { status: intentStatus, paymentStatus: intentPayment } =
    _terminalPlanChangeIntentFields(mpStatus);
  const userRef = db.collection("users").doc(uid);
  const subRef = userRef.collection("subscriptions").doc(preapprovalId);
  const batch = db.batch();

  batch.set(
    subRef,
    {
      status: intentStatus,
      paymentStatus: intentPayment,
      mpPreapprovalStatus: mpStatus,
      updatedAt: nowTs,
    },
    { merge: true },
  );

  const cid = String(resolvedChangeId || "").trim();
  if (cid) {
    const intentRef = db.collection(PLAN_CHANGE_INTENTS).doc(cid);
    batch.set(
      intentRef,
      {
        status: intentStatus,
        paymentStatus: intentPayment,
        mpPreapprovalStatus: mpStatus,
        updatedAt: nowTs,
      },
      { merge: true },
    );
  }

  batch.set(
    userRef,
    {
      pendingPlanChangeId: FieldValue.delete(),
      pendingPlanChangeFromPlanId: FieldValue.delete(),
      pendingPlanChangeToPlanId: FieldValue.delete(),
      pendingPlanChangePreapprovalId: FieldValue.delete(),
      pendingPlanChangeStatus: FieldValue.delete(),
      pendingSubscriptionId: FieldValue.delete(),
      pendingPlanId: FieldValue.delete(),
      pendingBillingMode: FieldValue.delete(),
      updatedAt: nowTs,
    },
    { merge: true },
  );

  await batch.commit();
}

async function _syncPlanChangePreapprovalNonTerminal({
  db,
  uid,
  resolvedChangeId,
  preapprovalId,
  mpStatus,
  nowTs,
}) {
  const userRef = db.collection("users").doc(uid);
  const subRef = userRef.collection("subscriptions").doc(preapprovalId);
  await subRef.set(
    {
      mpPreapprovalStatus: mpStatus,
      updatedAt: nowTs,
    },
    { merge: true },
  );
  const cid = String(resolvedChangeId || "").trim();
  if (cid) {
    await db.collection(PLAN_CHANGE_INTENTS).doc(cid).set(
      {
        mpPreapprovalStatus: mpStatus,
        updatedAt: nowTs,
      },
      { merge: true },
    );
  }
}

/**
 * Ramo planWebhook: notificação de preapproval/subscription MP para troca de plano (mpchg).
 * Evita cair em handlePreapprovalWebhookNotification (mprec) sem uid.
 * @returns {{ handled: boolean }}
 */
export async function handlePlanChangePreapprovalWebhook({
  db,
  token,
  preapprovalId,
  nowTs,
  getPreapproval = mpGetPreapproval,
}) {
  const route = await findPlanChangeRoutingForPreapproval(db, preapprovalId);
  if (!route) return { handled: false };

  const { uid, changeId, source } = route;

  console.info("[PLAN_CHANGE_PREAPPROVAL_EVENT_RECEIVED]", {
    uid,
    preapprovalId: String(preapprovalId || ""),
    changeId: changeId || null,
    routeSource: source,
  });

  let pre;
  try {
    pre = await getPreapproval(token, preapprovalId);
  } catch (e) {
    console.error("[PLAN_CHANGE_PREAPPROVAL_ROUTE_ERROR]", {
      preapprovalId: String(preapprovalId || ""),
      uid,
      err: String(e?.message || e),
    });
    return { handled: true };
  }

  const extRef = String(pre?.external_reference || "").trim();
  if (!extRef.startsWith("mpchg|")) {
    console.error("[PLAN_CHANGE_PREAPPROVAL_ROUTE_ERROR]", {
      reason: "expected_mpchg_external_reference",
      preapprovalId: String(preapprovalId || ""),
      uid,
      external_reference: extRef.slice(0, 120),
    });
    return { handled: true };
  }

  const ext = parseExternalReferenceMpPlanChange(extRef);
  if (!ext || ext.uid !== uid) {
    console.error("[PLAN_CHANGE_PREAPPROVAL_ROUTE_ERROR]", {
      reason: "mpchg_uid_mismatch",
      preapprovalId: String(preapprovalId || ""),
      uid,
    });
    return { handled: true };
  }

  let resolvedChangeId = String(changeId || "").trim();
  if (!resolvedChangeId) resolvedChangeId = String(ext.changeId || "").trim();
  if (!resolvedChangeId || resolvedChangeId !== ext.changeId) {
    console.error("[PLAN_CHANGE_PREAPPROVAL_ROUTE_ERROR]", {
      reason: "changeId_mismatch",
      preapprovalId: String(preapprovalId || ""),
      uid,
      resolvedChangeId: resolvedChangeId || null,
      extChangeId: ext.changeId || null,
    });
    return { handled: true };
  }

  const mpStatus = String(pre?.status || "").toLowerCase();

  if (_PLAN_CHANGE_PREAPPROVAL_TERMINAL_FAIL.has(mpStatus)) {
    console.info("[PLAN_CHANGE_PREAPPROVAL_REJECTED]", {
      uid,
      preapprovalId: String(preapprovalId || ""),
      changeId: resolvedChangeId,
      mpStatus,
    });
    await _applyPlanChangePreapprovalTerminalFailure({
      db,
      uid,
      resolvedChangeId,
      preapprovalId,
      mpStatus,
      nowTs,
    });
    return { handled: true };
  }

  await _syncPlanChangePreapprovalNonTerminal({
    db,
    uid,
    resolvedChangeId,
    preapprovalId,
    mpStatus,
    nowTs,
  });
  console.info("[PLAN_CHANGE_PREAPPROVAL_STATUS_SYNCED]", {
    uid,
    preapprovalId: String(preapprovalId || ""),
    mpStatus,
    changeId: resolvedChangeId,
  });
  return { handled: true };
}
