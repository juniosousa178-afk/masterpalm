/**
 * Assinatura recorrente (Mercado Pago — preapproval) — domínio APENAS de planos do app.
 * Coexiste com planCreatePreference / pagamentos pontuais. Catálogo da loja: fora de escopo.
 *
 * Feature flag backend: USE_RECURRING_PLAN_BILLING=true (env / secrets runtime).
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const PLAN_RECURRING_INTENTS = "plan_recurring_intents";
export const PROCESSED_PLAN_EVENTS = "processed_plan_events";

export function isRecurringPlanBillingEnabled() {
  const v = String(process.env.USE_RECURRING_PLAN_BILLING || "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

/** Mascara IDs externos sensíveis em logs (preapproval, etc.). */
export function maskProviderSubscriptionIdForLog(id) {
  const s = String(id || "").trim();
  if (!s) return "—";
  if (s.length <= 8) return `${s.slice(0, 2)}***`;
  return `${s.slice(0, 4)}…${s.slice(-4)}`;
}

async function fetchWithTimeout(url, opts = {}, timeoutMs = 20000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...opts, signal: controller.signal });
    clearTimeout(id);
    return res;
  } catch (e) {
    clearTimeout(id);
    throw e;
  }
}

export async function mpGetPreapproval(token, preapprovalId) {
  const r = await fetchWithTimeout(
    `https://api.mercadopago.com/preapproval/${encodeURIComponent(String(preapprovalId))}`,
    { headers: { Authorization: `Bearer ${token}` } },
    20000,
  );
  const txt = await r.text();
  let data = {};
  try {
    data = JSON.parse(txt);
  } catch {
    data = {};
  }
  if (!r.ok) {
    const err = new Error(`MP preapproval GET ${r.status}: ${txt.slice(0, 500)}`);
    err.status = r.status;
    throw err;
  }
  return data;
}

export async function mpCreatePreapproval(token, body) {
  const r = await fetchWithTimeout(
    "https://api.mercadopago.com/preapproval",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
    25000,
  );
  const txt = await r.text();
  let data = {};
  try {
    data = JSON.parse(txt);
  } catch {
    data = {};
  }
  if (!r.ok) {
    const err = new Error(`MP preapproval POST ${r.status}: ${txt.slice(0, 800)}`);
    err.status = r.status;
    err.mpBody = data;
    throw err;
  }
  return data;
}

export async function mpPutPreapproval(token, preapprovalId, body) {
  const r = await fetchWithTimeout(
    `https://api.mercadopago.com/preapproval/${encodeURIComponent(String(preapprovalId))}`,
    {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
    20000,
  );
  const txt = await r.text();
  let data = {};
  try {
    data = JSON.parse(txt);
  } catch {
    data = {};
  }
  if (!r.ok) {
    const err = new Error(`MP preapproval PUT ${r.status}: ${txt.slice(0, 500)}`);
    err.status = r.status;
    throw err;
  }
  return data;
}

/** Extrai próximo vencimento aproximado a partir do objeto preapproval MP. */
/**
 * Patch Firestore para preapproval MP em status `pending` — não apaga `email` quando ausente.
 * Exportado para testes unitários.
 */
export function mergePendingPreapprovalPatch({ billingPatch, email, nowTs }) {
  const pendingPatch = {
    ...billingPatch,
    billingSource: "mp_preapproval_pending",
    updatedAt: nowTs,
  };
  const em = String(email || "").trim();
  if (em) pendingPatch.email = em.toLowerCase();
  return pendingPatch;
}

export function inferPeriodEndFromPreapproval(pre, now = new Date()) {
  const n = pre?.next_payment_date || pre?.next_payment_date_time;
  if (n) {
    const d = new Date(n);
    if (!isNaN(d.getTime())) return d;
  }
  const fq = Number(pre?.auto_recurring?.frequency || 1);
  const ft = String(pre?.auto_recurring?.frequency_type || "months").toLowerCase();
  const x = new Date(now);
  if (ft === "months") x.setMonth(x.getMonth() + fq);
  else if (ft === "days") x.setDate(x.getDate() + fq);
  else if (ft === "years") x.setFullYear(x.getFullYear() + fq);
  else x.setMonth(x.getMonth() + 1);
  return x;
}

/**
 * Fim do período de cobrança atual (epoch ms) a partir de doc users/subscriptions.
 * Usado por plan change / elegibilidade; puro, sem rede.
 */
export function resolveCurrentPeriodEndMillis(doc) {
  if (!doc || typeof doc !== "object") return null;
  const c = doc.currentPeriodEnd;
  if (c == null) return null;
  if (typeof c.toMillis === "function") {
    try {
      const ms = Number(c.toMillis());
      return Number.isFinite(ms) ? ms : null;
    } catch {
      return null;
    }
  }
  if (c instanceof Date) {
    const ms = c.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof c === "number") return Number.isFinite(c) ? c : null;
  if (typeof c === "string") {
    const d = new Date(c);
    return !Number.isNaN(d.getTime()) ? d.getTime() : null;
  }
  if (typeof c.seconds === "number") {
    const ns = typeof c.nanoseconds === "number" ? c.nanoseconds : 0;
    return c.seconds * 1000 + Math.floor(ns / 1e6);
  }
  if (typeof c._seconds === "number") {
    const ns = typeof c._nanoseconds === "number" ? c._nanoseconds : 0;
    return c._seconds * 1000 + Math.floor(ns / 1e6);
  }
  const pre = doc.preapprovalSnapshot || doc.preapproval;
  if (pre && typeof pre === "object") {
    try {
      const end = inferPeriodEndFromPreapproval(pre);
      const ms = end.getTime();
      return Number.isFinite(ms) ? ms : null;
    } catch {
      return null;
    }
  }
  return null;
}

/**
 * Impede `runCreatePlanSubscription` quando já há recorrência ativa e o plano pedido é outro
 * (troca deve passar pelo fluxo de plan change, não por nova subscrição “comum”).
 */
export function shouldBlockCreateRecurringSubscription({
  canonicalRequested,
  userData,
  normalizePlanId,
}) {
  const norm =
    typeof normalizePlanId === "function"
      ? normalizePlanId
      : (x) => String(x || "").trim().toLowerCase();
  if (!userData || typeof userData !== "object") {
    return { blocked: false };
  }
  const endMs = resolveCurrentPeriodEndMillis(userData);
  const periodFuture = endMs != null && endMs > Date.now();
  const billingMode = String(userData.billingMode || "").toLowerCase();
  const subId = String(userData.providerSubscriptionId || "").trim();
  const planStatus = String(userData.planStatus || "").toLowerCase();
  const status = String(userData.status || "").toLowerCase();
  const activeLike =
    planStatus === "active" ||
    status === "active" ||
    planStatus === "trialing" ||
    status === "trialing";
  const activeRecurring =
    activeLike && billingMode === "recurring" && !!subId && periodFuture;
  if (!activeRecurring) {
    return { blocked: false };
  }
  const cur = norm(userData.currentPlanId);
  const req = norm(canonicalRequested);
  if (!req || !cur) return { blocked: false };
  if (req === cur) return { blocked: false };
  return { blocked: true };
}

/**
 * Sincroniza users/{uid} a partir de preapproval autorizado/pausado/cancelado.
 * Não promove plano pago só por "pending" sem regra explícita.
 */
export async function syncFirestoreFromPreapproval({
  db,
  uid,
  email,
  canonicalPlanId,
  preapproval,
  nowTs,
}) {
  const id = String(preapproval.id || "");
  const status = String(preapproval.status || "").toLowerCase();
  const ref = db.collection("users").doc(uid);

  const billingPatch = {
    provider: "mercado_pago",
    billingSource: "mp_subscription",
    billingVersion: 2,
    billingMode: "recurring",
    providerSubscriptionId: id,
    mercadoPagoPreapprovalId: id,
    subscriptionId: id,
    planLastSyncedAt: nowTs,
    updatedAt: nowTs,
  };

  if (status === "pending") {
    await ref.set(
      {
        ...mergePendingPreapprovalPatch({ billingPatch, email, nowTs }),
        planStatus: "pending",
        pendingPlanId: canonicalPlanId,
        pendingSubscriptionId: id,
        pendingBillingMode: "recurring",
      },
      { merge: true },
    );
    await ref.collection("subscriptions").doc(id).set(
      {
        provider: "mercado_pago",
        billingMode: "recurring",
        preapprovalId: id,
        planId: canonicalPlanId,
        status: "pending",
        externalReference: String(preapproval.external_reference || ""),
        source: "planWebhook",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_RECURRING_PREAPPROVAL_PENDING",
        uid,
        status: "pending",
        preapprovalId: id,
      }),
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_USER_NOT_ACTIVATED",
        uid,
        reason: "pending",
        preapprovalId: id,
      }),
    );
    return { ok: true, phase: "pending" };
  }

  // Segurança: preapproval authorized/active não ativa plano sem confirmação de cobrança aprovada.
  if (status === "authorized" || status === "active") {
    await ref.set(
      {
        ...billingPatch,
        planStatus: "authorized_pending_payment",
        pendingPlanId: canonicalPlanId,
        pendingSubscriptionId: id,
        pendingBillingMode: "recurring",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await ref.collection("subscriptions").doc(id).set(
      {
        provider: "mercado_pago",
        billingMode: "recurring",
        preapprovalId: id,
        planId: canonicalPlanId,
        status: "authorized_pending_payment",
        externalReference: String(preapproval.external_reference || ""),
        source: "planWebhook",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_RECURRING_PREAPPROVAL_PENDING",
        uid,
        status,
        preapprovalId: id,
      }),
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_USER_NOT_ACTIVATED",
        uid,
        reason: "authorized_pending_payment",
        preapprovalId: id,
      }),
    );
    return { ok: true, phase: "authorized_pending_payment" };
  }

  if (status === "approved") {
    await ref.set(
      {
        ...billingPatch,
        planStatus: "approved_pending_reconcile",
        pendingPlanId: canonicalPlanId,
        pendingSubscriptionId: id,
        pendingBillingMode: "recurring",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await ref.collection("subscriptions").doc(id).set(
      {
        provider: "mercado_pago",
        billingMode: "recurring",
        preapprovalId: id,
        planId: canonicalPlanId,
        status: "approved_pending_reconcile",
        externalReference: String(preapproval.external_reference || ""),
        source: "planWebhook",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_RECURRING_PREAPPROVAL_PENDING",
        uid,
        status: "approved",
        preapprovalId: id,
      }),
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_USER_NOT_ACTIVATED",
        uid,
        reason: "approved_pending_payment_event",
        preapprovalId: id,
      }),
    );
    return { ok: true, phase: "approved_pending_payment_event" };
  }

  if (status === "paused") {
    await ref.set(
      {
        ...billingPatch,
        planStatus: "paused",
        cancelAtPeriodEnd: true,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await ref.collection("subscriptions").doc(id).set(
      { status: "paused", source: "planWebhook", updatedAt: nowTs },
      { merge: true },
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_USER_NOT_ACTIVATED",
        uid,
        reason: "paused",
        preapprovalId: id,
      }),
    );
    return { ok: true, phase: "paused" };
  }

  if (status === "cancelled" || status === "canceled" || status === "rejected") {
    const finalStatus = status === "rejected" ? "rejected" : "cancelled";
    await ref.set(
      {
        ...billingPatch,
        billingSource: "mp_subscription_cancelled",
        planStatus: finalStatus,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await ref.collection("subscriptions").doc(id).set(
      { status: finalStatus, source: "planWebhook", updatedAt: nowTs },
      { merge: true },
    );
    console.log(
      JSON.stringify({
        evt: "PLAN_USER_NOT_ACTIVATED",
        uid,
        reason: finalStatus,
        preapprovalId: id,
      }),
    );
    return { ok: true, phase: finalStatus };
  }

  await ref.set({ ...billingPatch, updatedAt: nowTs }, { merge: true });
  return { ok: true, phase: status || "unknown" };
}

export function parseExternalReferenceMpRecurring(externalRef) {
  const s = String(externalRef || "").trim();
  if (s.startsWith("plan:")) {
    const parts = s.split(":");
    if (parts.length >= 3) return { uid: parts[1], canonicalPlanId: parts[2] };
    return null;
  }
  if (!s.startsWith("mprec|")) return null;
  const parts = s.split("|");
  if (parts.length < 3) return null;
  return { uid: parts[1], canonicalPlanId: parts[2] };
}

/**
 * Webhook branch: notificação de preapproval (id = preapproval).
 */
export async function handlePreapprovalWebhookNotification({
  db,
  token,
  preapprovalId,
  nowTs,
  normalizePlanId,
}) {
  console.log(
    JSON.stringify({
      evt: "PLAN_WEBHOOK_RECEIVED",
      type: "subscription",
      action: "preapproval",
      id: String(preapprovalId),
    }),
  );
  const processedRef = db.collection(PROCESSED_PLAN_EVENTS).doc(`preapproval_${preapprovalId}`);
  const pr = await processedRef.get();
  if (pr.exists && pr.data()?.status === "processed") {
    console.warn(JSON.stringify({ evt: "plan_preapproval_webhook_dup", preapprovalId }));
    return { consumed: true, duplicate: true };
  }

  let pre;
  try {
    pre = await mpGetPreapproval(token, preapprovalId);
  } catch (e) {
    console.error("[mpPlanRecurring] get preapproval", preapprovalId, e?.message || e);
    return { consumed: false };
  }
  console.log(
    JSON.stringify({
      evt: "PLAN_WEBHOOK_PREAPPROVAL_FETCHED",
      preapprovalId: String(preapprovalId),
      status: String(pre?.status || "").toLowerCase(),
      externalReference: String(pre?.external_reference || "").slice(0, 160),
    }),
  );

  const ext = parseExternalReferenceMpRecurring(pre.external_reference);
  let uid = ext?.uid;
  let plan = ext ? normalizePlanId(ext.canonicalPlanId) : null;

  if (!uid) {
    const intent = await db.collection(PLAN_RECURRING_INTENTS).doc(String(preapprovalId)).get();
    if (intent.exists) {
      const d = intent.data() || {};
      uid = d.uid;
      plan = normalizePlanId(d.canonicalPlanId || plan);
    }
  }

  if (!uid) {
    console.warn("[mpPlanRecurring] preapproval sem uid", preapprovalId);
    await processedRef.set(
      { preapprovalId, status: "skipped_no_uid", updatedAt: nowTs },
      { merge: true },
    );
    return { consumed: true };
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const email = (userSnap.exists && userSnap.data()?.email) || pre.payer_email || "";

  const syncResult = await syncFirestoreFromPreapproval({
    db,
    uid,
    email,
    canonicalPlanId: plan || "pro_monthly",
    preapproval: pre,
    nowTs,
  });

  await processedRef.set(
    {
      preapprovalId: String(preapprovalId),
      uid,
      status: "processed",
      mpStatus: pre.status,
      updatedAt: nowTs,
    },
    { merge: true },
  );

  console.log(
    JSON.stringify({
      evt: "plan_v2_preapproval_webhook",
      uid,
      preapprovalId: String(preapprovalId),
      mpStatus: String(pre.status || ""),
      phase: syncResult?.phase || "unknown",
      planId: plan || "pro_monthly",
    }),
  );

  return { consumed: true };
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

export async function runCreatePlanSubscription({
  db,
  request,
  token,
  webBase,
  prices,
  planTitleForMp,
  normalizePlanId,
}) {
  if (!isRecurringPlanBillingEnabled()) {
    console.log(JSON.stringify({ evt: "PLAN_RECURRING_FLAG", enabled: false }));
    throw new HttpsError("failed-precondition", "RECURRING_PLAN_BILLING_DISABLED");
  }
  console.log(JSON.stringify({ evt: "PLAN_RECURRING_FLAG", enabled: true }));
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Faça login para continuar.");
  }
  const uid = request.auth.uid;
  const email = String(request.auth.token?.email || "").trim().toLowerCase();
  const data = request.data || {};
  const planRaw = String(data.plan || data.planId || "").trim().toLowerCase();
  const allowed = new Set([
    "mensal",
    "anual",
    "basic_monthly",
    "intermediate_monthly",
    "pro_monthly",
    "pro_yearly",
  ]);
  if (!allowed.has(planRaw)) {
    throw new HttpsError("invalid-argument", "plan inválido para assinatura recorrente.");
  }
  const canonical = normalizePlanId(planRaw);
  const returnUrl =
    String(data.returnUrl || "").trim() ||
    `${webBase.replace(/\/$/, "")}/planos/retorno`;

  const start = new Date();
  const end = new Date(start);
  end.setFullYear(end.getFullYear() + 10);

  const body = {
    reason: planTitleForMp(canonical),
    external_reference: `plan:${uid}:${canonical}:${Date.now()}`,
    payer_email: email || undefined,
    auto_recurring: {
      ...autoRecurringForPlan(canonical, prices),
      start_date: start.toISOString(),
      end_date: end.toISOString(),
    },
    back_url: returnUrl,
    status: "authorized",
  };
  console.log(
    JSON.stringify({
      evt: "PLAN_RECURRING_CREATE_START",
      uid,
      planId: canonical,
      amount: Number(body.auto_recurring?.transaction_amount || 0),
      frequencyType: String(body.auto_recurring?.frequency_type || ""),
    }),
  );

  let mpRes;
  try {
    mpRes = await mpCreatePreapproval(token, body);
  } catch (e) {
    console.error("[createPlanSubscription] MP error", e?.message || e);
    console.error(
      JSON.stringify({
        evt: "PLAN_RECURRING_CREATE_ERROR",
        message: String(e?.message || "unknown").slice(0, 250),
      }),
    );
    throw new HttpsError("internal", e?.message || "Erro ao criar assinatura no Mercado Pago.");
  }

  const preapprovalId = String(mpRes.id || "");
  const initPoint = String(mpRes.init_point || mpRes.initPoint || "").trim();
  if (!preapprovalId || !initPoint) {
    console.error("[createPlanSubscription] resposta MP incompleta", JSON.stringify(mpRes).slice(0, 500));
    throw new HttpsError("internal", "Resposta inválida do Mercado Pago (assinatura recorrente).");
  }

  const intentRef = db.collection(PLAN_RECURRING_INTENTS).doc(preapprovalId);
  await intentRef.set(
    {
      uid,
      email,
      canonicalPlanId: canonical,
      preapprovalId,
      initPoint,
      createdAt: FieldValue.serverTimestamp(),
      status: "pending",
    },
    { merge: true },
  );

  const userRef = db.collection("users").doc(uid);
  await userRef.set(
    {
      email,
      provider: "mercado_pago",
      billingVersion: 2,
      billingSource: "mp_preapproval_pending",
      billingMode: "recurring",
      providerSubscriptionId: preapprovalId,
      providerPreapprovalPlanId: mpRes.preapproval_plan_id || null,
      planStatus: "pending",
      pendingPlanId: canonical,
      pendingSubscriptionId: preapprovalId,
      pendingBillingMode: "recurring",
      planLastSyncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await userRef.collection("subscriptions").doc(preapprovalId).set(
    {
      provider: "mercado_pago",
      billingMode: "recurring",
      preapprovalId,
      planId: canonical,
      planName: canonical,
      amount: Number(body.auto_recurring?.transaction_amount || 0),
      currency: String(body.auto_recurring?.currency_id || "BRL"),
      frequency: Number(body.auto_recurring?.frequency || 1),
      frequencyType: String(body.auto_recurring?.frequency_type || "months"),
      status: String(mpRes.status || "pending").toLowerCase() || "pending",
      externalReference: body.external_reference,
      initPoint,
      source: "createPlanSubscription",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    JSON.stringify({
      evt: "plan_v2_create_preapproval",
      uid,
      canonicalPlanId: canonical,
      preapprovalId,
      billingVersion: 2,
      billingSource: "mp_preapproval_pending",
      decision: "init_ok",
    }),
  );
  console.log(
    JSON.stringify({
      evt: "PLAN_RECURRING_CREATE_SUCCESS",
      preapprovalId,
      hasInitPoint: !!initPoint,
    }),
  );

  return {
    ok: true,
    initPoint,
    preapprovalId,
    externalReference: body.external_reference,
    canonicalPlanId: canonical,
  };
}

export async function runCancelPlanSubscription({ db, request, token }) {
  console.log(
    JSON.stringify({
      tag: "[PLAN-CANCEL][INICIO]",
      uid: request.auth?.uid || null,
    }),
  );

  if (!request.auth?.uid) {
    console.log(JSON.stringify({ tag: "[PLAN-CANCEL][ERRO]", reason: "unauthenticated" }));
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const uid = request.auth.uid;

  if (!isRecurringPlanBillingEnabled()) {
    console.log(
      JSON.stringify({
        tag: "[PLAN-CANCEL][BILLING-DESABILITADO-MAS-CANCELAMENTO-PERMITIDO]",
        uid,
      }),
    );
  }

  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.log(JSON.stringify({ tag: "[PLAN-CANCEL][ERRO]", uid, reason: "profile_not_found" }));
    throw new HttpsError("failed-precondition", "Perfil não encontrado.");
  }
  const d = snap.data() || {};

  console.log(JSON.stringify({ tag: "[PLAN-CANCEL][AUTORIZACAO-OK]", uid }));

  if (d.manualOverride?.enabled === true) {
    throw new HttpsError("failed-precondition", "Plano com override manual.");
  }
  const subId = String(d.providerSubscriptionId || "").trim();
  if (!subId) {
    console.log(JSON.stringify({ tag: "[PLAN-CANCEL][SEM-ASSINATURA]", uid }));
    throw new HttpsError("failed-precondition", "ASSINATURA_RECORRENTE_NAO_ENCONTRADA");
  }

  const subIdLog = maskProviderSubscriptionIdForLog(subId);
  console.log(
    JSON.stringify({
      tag: "[PLAN-CANCEL][ASSINATURA-ENCONTRADA]",
      uid,
      providerSubscriptionId: subIdLog,
    }),
  );

  if (d.cancelAtPeriodEnd === true) {
    console.log(
      JSON.stringify({
        tag: "[PLAN-CANCEL][JÁ-CANCELADA]",
        uid,
        providerSubscriptionId: subIdLog,
      }),
    );
    return { ok: true, cancelAtPeriodEnd: true, alreadyCancelled: true };
  }

  try {
    await mpPutPreapproval(token, subId, { status: "paused" });
    console.log(
      JSON.stringify({
        tag: "[PLAN-CANCEL][PROVEDOR-OK]",
        uid,
        providerSubscriptionId: subIdLog,
      }),
    );
  } catch (e) {
    console.warn(
      JSON.stringify({
        tag: "[PLAN-CANCEL][ERRO]",
        phase: "mp_pause",
        evt: "plan_v2_cancel_mp_pause_failed",
        uid,
        providerSubscriptionId: subIdLog,
        err: String(e?.message || e).slice(0, 200),
      }),
    );
  }

  await ref.set(
    {
      cancelAtPeriodEnd: true,
      billingVersion: 2,
      billingSource: "mp_subscription",
      planLastSyncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    JSON.stringify({
      tag: "[PLAN-CANCEL][FIM]",
      evt: "plan_v2_cancel_subscription",
      uid,
      planId: String(d.currentPlanId || ""),
      providerSubscriptionId: subIdLog,
      billingVersion: d.billingVersion ?? 2,
      cancelAtPeriodEnd: true,
      decision: "firestore_ok",
    }),
  );

  return { ok: true, cancelAtPeriodEnd: true };
}

export async function runReactivatePlanSubscription({ db, request, token }) {
  if (!isRecurringPlanBillingEnabled()) {
    throw new HttpsError("failed-precondition", "RECURRING_PLAN_BILLING_DISABLED");
  }
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Faça login.");
  const uid = request.auth.uid;
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Perfil não encontrado.");
  const d = snap.data() || {};
  const subId = String(d.providerSubscriptionId || "").trim();
  if (!subId) {
    throw new HttpsError("failed-precondition", "Nenhuma assinatura MP para reativar.");
  }
  if (d.cancelAtPeriodEnd !== true) {
    throw new HttpsError("failed-precondition", "Nada para reativar.");
  }

  try {
    await mpPutPreapproval(token, subId, { status: "authorized" });
  } catch (e) {
    console.warn(
      JSON.stringify({
        evt: "plan_v2_reactivate_mp_failed",
        uid,
        providerSubscriptionId: subId,
        err: String(e?.message || e),
      }),
    );
    throw new HttpsError("internal", "Não foi possível reativar no Mercado Pago.");
  }

  await ref.set(
    {
      cancelAtPeriodEnd: false,
      billingVersion: 2,
      billingSource: "mp_subscription",
      planLastSyncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    JSON.stringify({
      evt: "plan_v2_reactivate_subscription",
      uid,
      planId: String(d.currentPlanId || ""),
      providerSubscriptionId: subId,
      billingVersion: d.billingVersion ?? 2,
      cancelAtPeriodEnd: false,
      decision: "ok",
    }),
  );

  return { ok: true, cancelAtPeriodEnd: false };
}

export async function runSyncPlanSubscription({ db, request, token, normalizePlanId }) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Faça login.");
  const uid = request.auth.uid;
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Perfil não encontrado.");
  const d = snap.data() || {};
  const subId = String(d.providerSubscriptionId || "").trim();
  if (!subId) {
    console.log(
      JSON.stringify({
        evt: "plan_v2_sync_subscription",
        uid,
        synced: false,
        reason: "no_provider_subscription",
        billingVersion: d.billingVersion ?? null,
      }),
    );
    return { ok: true, synced: false, reason: "no_provider_subscription" };
  }

  let pre;
  try {
    pre = await mpGetPreapproval(token, subId);
  } catch (e) {
    throw new HttpsError("internal", e?.message || "Falha ao consultar Mercado Pago.");
  }

  const ext = parseExternalReferenceMpRecurring(pre.external_reference);
  const plan = normalizePlanId(ext?.canonicalPlanId || d.currentPlanId || "pro_monthly");
  const email = String(d.email || request.auth.token?.email || "");

  const syncResult = await syncFirestoreFromPreapproval({
    db,
    uid,
    email,
    canonicalPlanId: plan,
    preapproval: pre,
    nowTs: FieldValue.serverTimestamp(),
  });

  console.log(
    JSON.stringify({
      evt: "plan_v2_sync_subscription",
      uid,
      planId: plan,
      providerSubscriptionId: subId,
      mpStatus: String(pre.status || ""),
      phase: syncResult?.phase || "unknown",
      synced: true,
    }),
  );

  return { ok: true, synced: true, mpStatus: pre.status };
}
