// functions/src/ensureUserPlan.js  (ESM / Node 20)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { checkRateLimit, getCallableIdentifier } from "./src/rateLimiter.js";

export const ROOT_EMAIL = "masterpalm@gmail.com";

/** Planos pagos com renovação por período (espelha ramo em computePlanState). */
export const PAID_PLANS_WITH_RENEWAL = Object.freeze([
  "pro_monthly",
  "pro_yearly",
  "basic_monthly",
  "intermediate_monthly",
]);

// LEGACY FLOW: callable mantido por retrocompatibilidade.
// Fonte principal de assinatura/plano continua sendo o fluxo canônico
// users/{uid}.currentPlanId/status/trialing/currentPeriodEnd.

export function normalizeCanonicalPlanId(raw) {
  const p = String(raw || "").trim().toLowerCase();
  if (p === "mensal" || p === "pro_monthly") return "pro_monthly";
  if (p === "anual" || p === "pro_yearly") return "pro_yearly";
  if (p === "basic" || p === "basic_monthly") return "basic_monthly";
  if (p === "intermediate" || p === "intermediate_monthly") return "intermediate_monthly";
  if (p === "trial_30d" || p === "free_trial_30d") return "free_trial_30d";
  if (p === "trial" || p === "trial_90d" || p === "free_trial_90d") return "free_trial_90d";
  if (p === "free_limited") return "free_limited";
  if (p === "lifetime") return "lifetime";
  return p;
}

function toLegacyPlanAlias(raw) {
  const p = normalizeCanonicalPlanId(raw);
  if (p === "pro_monthly") return "mensal";
  if (p === "pro_yearly") return "anual";
  return p;
}

// ✅ Admin init seguro (não cria duplicate-app)
function initDb() {
  if (!getApps().length) initializeApp();
  return getFirestore();
}

// Trial 90 dias (calendário)
function addDays(date, n) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

function addMonths(date, n) {
  const d = new Date(date);
  d.setMonth(d.getMonth() + n);
  return d;
}

function daysBetweenCeil(a, b) {
  const ms = b.getTime() - a.getTime();
  return Math.ceil(ms / (1000 * 60 * 60 * 24));
}

function toDateAny(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v?.toDate === "function") return v.toDate(); // Firestore Timestamp
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

function normalizeEmail(s) {
  return String(s || "").trim().toLowerCase();
}

export async function computePlanState({ db, uid, email }) {
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  const data = snap.exists ? (snap.data() || {}) : {};
  const now = new Date();

  // Root sempre ativo
  const isRoot = normalizeEmail(email) === normalizeEmail(ROOT_EMAIL);
  if (isRoot) {
    await ref.set(
      {
        email,
        isRoot: true,
        currentPlanId: "lifetime",
        status: "active",
        trialing: false,
        currentPeriodEnd: null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      status: "active",
      plan: "root",
      isRoot: true,
      daysLeft: 99999,
      endsAt: null,
      shouldNotify: false,
      message: "Root ativo.",
      userDoc: data,
    };
  }

  // 1) Manual grant tem prioridade
  const manual = data.manual_grant || null;

  if (manual?.type === "lifetime") {
    await ref.set(
      {
        email,
        currentPlanId: "lifetime",
        status: "active",
        trialing: false,
        currentPeriodEnd: null,
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      status: "active",
      plan: "lifetime",
      isRoot: false,
      daysLeft: 99999,
      endsAt: null,
      shouldNotify: false,
      message: "Acesso vitalício (manual).",
      userDoc: data,
    };
  }

  if (manual?.type === "until") {
    const untilAt = toDateAny(manual.untilAt);
    if (untilAt && now <= untilAt) {
      const daysLeft = daysBetweenCeil(now, untilAt);

      await ref.set(
        {
          email,
          currentPlanId: normalizeCanonicalPlanId(data.currentPlanId || data.plan || "manual"),
          status: "active",
          trialing: false,
          currentPeriodEnd: untilAt ? Timestamp.fromDate(untilAt) : null,
          blocked_reason: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        status: "active",
        plan: toLegacyPlanAlias(data.currentPlanId || data.plan || "manual"),
        isRoot: false,
        daysLeft,
        endsAt: untilAt.toISOString(),
        shouldNotify: false,
        message: "Acesso liberado manualmente até a data.",
        userDoc: data,
      };
    }
  }

  // 1b) manualOverride.enabled (PlanosService / admin) — não sofre downgrade automático
  const mo = data.manualOverride;
  if (mo && typeof mo === "object" && mo.enabled === true) {
    const moPlanId = normalizeCanonicalPlanId(
      String(mo.planId || data.currentPlanId || "lifetime").trim(),
    );
    const endMo = toDateAny(data.currentPeriodEnd);
    let daysLeftMo = 99999;
    let endsAtMo = null;
    if (moPlanId !== "lifetime" && endMo && endMo > now) {
      daysLeftMo = daysBetweenCeil(now, endMo);
      endsAtMo = endMo.toISOString();
    }
    await ref.set(
      {
        email,
        currentPlanId: moPlanId,
        status: "active",
        trialing: false,
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return {
      status: "active",
      plan: toLegacyPlanAlias(moPlanId),
      isRoot: false,
      daysLeft: daysLeftMo,
      endsAt: endsAtMo,
      shouldNotify: false,
      allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
      message: "Override manual ativo.",
      userDoc: data,
    };
  }

  // 2) Estado canônico no Firestore (callable trial 30d, planos pagos, free_limited)
  const canonicalPlan = normalizeCanonicalPlanId(data.currentPlanId || data.plan || "");
  const planAlias = toLegacyPlanAlias(canonicalPlan);
  const renewAt = toDateAny(data.currentPeriodEnd || data.plan_renewsAt);

  if (canonicalPlan === "lifetime") {
    await ref.set(
      {
        email,
        currentPlanId: "lifetime",
        status: "active",
        trialing: false,
        currentPeriodEnd: null,
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      status: "active",
      plan: "lifetime",
      isRoot: false,
      daysLeft: 99999,
      endsAt: null,
      shouldNotify: false,
      allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
      message: "Acesso vitalício.",
      userDoc: data,
    };
  }

  if (canonicalPlan === "free_limited") {
    await ref.set(
      {
        email,
        currentPlanId: "free_limited",
        status: "active",
        trialing: false,
        currentPeriodEnd: null,
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      status: "active",
      plan: "free_limited",
      isRoot: false,
      daysLeft: 99999,
      endsAt: null,
      shouldNotify: false,
      allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
      message: "Plano free limitado ativo.",
      userDoc: data,
    };
  }

  if (
    (canonicalPlan === "free_trial_30d" || canonicalPlan === "free_trial_90d") &&
    data.trialing === true
  ) {
    const end = renewAt;
    if (end && now <= end) {
      const daysLeft = daysBetweenCeil(now, end);
      await ref.set(
        {
          email,
          currentPlanId: canonicalPlan,
          status: "trialing",
          trialing: true,
          currentPeriodEnd: Timestamp.fromDate(end),
          blocked_reason: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return {
        status: "active",
        plan: "trial",
        isRoot: false,
        daysLeft,
        endsAt: end.toISOString(),
        shouldNotify: false,
        allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
        message: "Trial ativo.",
        userDoc: data,
      };
    }
  }

  if (PAID_PLANS_WITH_RENEWAL.includes(canonicalPlan) && renewAt) {
    if (now <= renewAt) {
      const daysLeft = daysBetweenCeil(now, renewAt);
      const notifyStart = 15;
      const notifyEvery = 5;
      let shouldNotify = false;
      let notifyMsg = null;
      if (daysLeft <= notifyStart && daysLeft > 0) {
        const lastNotifyAt = toDateAny(data.notify_lastAt);
        const canNotify =
          !lastNotifyAt || daysBetweenCeil(lastNotifyAt, now) >= notifyEvery;
        if (canNotify) {
          shouldNotify = true;
          notifyMsg = `Faltam ${daysLeft} dias para vencer seu plano.`;
          await ref.set(
            {
              notify_lastAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      }
      await ref.set(
        {
          email,
          currentPlanId: canonicalPlan,
          status: "active",
          trialing: false,
          currentPeriodEnd: Timestamp.fromDate(renewAt),
          blocked_reason: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      const msgPaid =
        data.cancelAtPeriodEnd === true
          ? "Renovação cancelada; seu acesso continua até o fim do período pago."
          : "Plano pago ativo.";
      return {
        status: "active",
        plan: planAlias,
        isRoot: false,
        daysLeft,
        endsAt: renewAt.toISOString(),
        shouldNotify,
        notifyMsg,
        allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
        cancelAtPeriodEnd: data.cancelAtPeriodEnd === true,
        message: msgPaid,
        userDoc: data,
      };
    }
    // Período pago encerrado sem renovação → free_limited (dados preservados; limites do free)
    await ref.set(
      {
        email,
        currentPlanId: "free_limited",
        status: "active",
        trialing: false,
        currentPeriodEnd: null,
        cancelAtPeriodEnd: false,
        trialUsed: true,
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      status: "active",
      plan: "free_limited",
      isRoot: false,
      daysLeft: 99999,
      endsAt: null,
      shouldNotify: true,
      notifyMsg:
        "Seu plano pago encerrou. Você está no Free limitado — seus dados foram mantidos.",
      allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
      cancelAtPeriodEnd: false,
      message: "Downgrade automático para free_limited após vencimento do período pago.",
      userDoc: data,
    };
  }

  // 3) Legado: trial_endsAt (contas antigas). Não cria mais trial de 90 dias automaticamente.
  const trialEndsAt = toDateAny(data.trial_endsAt);

  // Trial existente (legado)
  if (trialEndsAt) {
    if (now <= trialEndsAt) {
      const daysLeft = daysBetweenCeil(now, trialEndsAt);

      const notifyStart = 15;
      const notifyEvery = 5;

      let shouldNotify = false;
      let notifyMsg = null;

      if (daysLeft <= notifyStart && daysLeft > 0) {
        const lastNotifyAt = toDateAny(data.notify_lastAt);
        const canNotify =
          !lastNotifyAt || daysBetweenCeil(lastNotifyAt, now) >= notifyEvery;

        if (canNotify) {
          shouldNotify = true;
          notifyMsg = `Faltam ${daysLeft} dias para vencer seu plano gratuito.`;
          await ref.set(
            {
              notify_lastAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      }

      await ref.set(
        {
          email,
          currentPlanId: "free_trial_90d",
          status: "trialing",
          trialing: true,
          currentPeriodEnd: Timestamp.fromDate(trialEndsAt),
          blocked_reason: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        status: "active",
        plan: "trial",
        isRoot: false,
        daysLeft,
        endsAt: trialEndsAt.toISOString(),
        shouldNotify,
        notifyMsg,
        allowPlans: ["mensal", "anual"],
        message: "Trial ativo.",
        userDoc: data,
      };
    }

    // Trial venceu
    await ref.set(
      {
        email,
        currentPlanId: "free_trial_90d",
        status: "inactive",
        trialing: false,
        currentPeriodEnd: Timestamp.fromDate(trialEndsAt),
        blocked_reason: "Trial expirou",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      status: "blocked",
      plan: "trial",
      isRoot: false,
      daysLeft: 0,
      endsAt: trialEndsAt.toISOString(),
      shouldNotify: true,
      notifyMsg:
        "Seu plano gratuito venceu. Assine mensal ou anual para continuar.",
      allowPlans: ["mensal", "anual"],
      message: "Trial vencido.",
      userDoc: data,
    };
  }

  // 4) Já usou trial e não tem plano pago
  await ref.set(
    {
      email,
      status: "inactive",
      trialing: false,
      blocked_reason: "Sem plano ativo (trial já utilizado)",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    status: "blocked",
    plan: planAlias || canonicalPlan || "none",
    isRoot: false,
    daysLeft: 0,
    endsAt: null,
    shouldNotify: true,
    notifyMsg: "Você precisa assinar um plano (mensal ou anual) para continuar.",
    allowPlans: ["mensal", "anual", "basic_monthly", "intermediate_monthly"],
    message: "Bloqueado sem plano.",
    userDoc: data,
  };
}

// =============== CALLABLE PRINCIPAL ===============
export const ensureUserPlan = onCall(async (request) => {
  try {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }

    const db = initDb(); // ✅ sem duplicate-app
    const uid = request.auth.uid;
    const email = request.auth.token?.email || "";

    const result = await computePlanState({ db, uid, email });

    return {
      ok: true,
      status: result.status, // active | blocked
      plan: result.plan,
      isRoot: !!result.isRoot,
      daysLeft: result.daysLeft ?? 0,
      endsAt: result.endsAt || null,
      shouldNotify: !!result.shouldNotify,
      notifyMsg: result.notifyMsg || null,
      allowPlans: result.allowPlans || ["mensal", "anual"],
      message: result.message,
      cancelAtPeriodEnd: result.cancelAtPeriodEnd === true,
    };
  } catch (err) {
    console.error("[ensureUserPlan] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao validar plano do usuário.");
  }
});

// =============== CANCELAR / REATIVAR RENOVAÇÃO (fim do período pago) ===============
export const cancelPlanRenewalAtPeriodEnd = onCall(async (request) => {
  try {
    await checkRateLimit("cancelPlanRenewalAtPeriodEnd", getCallableIdentifier(request));
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }
    const db = initDb();
    const uid = request.auth.uid;
    const ref = db.collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const data = snap.data() || {};
    if (data.manualOverride && data.manualOverride.enabled === true) {
      throw new HttpsError(
        "failed-precondition",
        "Este acesso foi liberado manualmente; fale com o suporte para alterações.",
      );
    }
    const mg = data.manual_grant;
    if (mg?.type === "lifetime") {
      throw new HttpsError("failed-precondition", "Plano vitalício não usa este fluxo.");
    }
    const canonical = normalizeCanonicalPlanId(data.currentPlanId || "");
    const paid = ["pro_monthly", "pro_yearly", "basic_monthly", "intermediate_monthly"];
    if (!paid.includes(canonical)) {
      throw new HttpsError(
        "failed-precondition",
        "Nenhuma assinatura paga ativa para cancelar a renovação.",
      );
    }
    const renewAt = toDateAny(data.currentPeriodEnd || data.plan_renewsAt);
    if (!renewAt || renewAt <= new Date()) {
      throw new HttpsError("failed-precondition", "O período pago já encerrou.");
    }
    await ref.set(
      {
        cancelAtPeriodEnd: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { ok: true, cancelAtPeriodEnd: true };
  } catch (err) {
    console.error("[cancelPlanRenewalAtPeriodEnd] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Não foi possível cancelar a renovação.");
  }
});

export const reactivatePlanRenewal = onCall(async (request) => {
  try {
    await checkRateLimit("reactivatePlanRenewal", getCallableIdentifier(request));
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }
    const db = initDb();
    const uid = request.auth.uid;
    const ref = db.collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const data = snap.data() || {};
    if (data.cancelAtPeriodEnd !== true) {
      throw new HttpsError("failed-precondition", "Nada para reativar.");
    }
    const renewAt = toDateAny(data.currentPeriodEnd || data.plan_renewsAt);
    if (!renewAt || renewAt <= new Date()) {
      throw new HttpsError("failed-precondition", "O período já encerrou; assine novamente.");
    }
    await ref.set(
      {
        cancelAtPeriodEnd: false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { ok: true, cancelAtPeriodEnd: false };
  } catch (err) {
    console.error("[reactivatePlanRenewal] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Não foi possível reativar a renovação.");
  }
});

// =============== ROOT: CONCEDER PLANO MANUAL ===============
export const rootGrantPlan = onCall(async (request) => {
  try {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Faça login.");

    const callerEmail = normalizeEmail(request.auth.token?.email || "");
    if (callerEmail !== normalizeEmail(ROOT_EMAIL)) {
      throw new HttpsError("permission-denied", "Apenas o root pode liberar planos.");
    }

    const db = initDb();

    const { targetUid, type, untilIso, note } = request.data || {};
    if (!targetUid) throw new HttpsError("invalid-argument", "targetUid é obrigatório.");
    if (!["lifetime", "until"].includes(String(type || ""))) {
      throw new HttpsError("invalid-argument", "type inválido (use lifetime|until).");
    }

    const payload = {
      manual_grant: {
        type,
        untilAt:
          type === "until"
            ? Timestamp.fromDate(new Date(untilIso))
            : null,
        byEmail: callerEmail,
        note: String(note || "").slice(0, 200),
        grantedAt: FieldValue.serverTimestamp(),
      },
      currentPlanId: type === "lifetime" ? "lifetime" : "pro_monthly",
      status: "active",
      trialing: false,
      currentPeriodEnd:
        type === "until" ? Timestamp.fromDate(new Date(untilIso)) : null,
      blocked_reason: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(String(targetUid)).set(payload, { merge: true });

    return { ok: true, targetUid, granted: payload.manual_grant };
  } catch (err) {
    console.error("[rootGrantPlan] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao conceder plano manual.");
  }
});

// =============== TRIAL (30 dias — novas contas; callable mantém nome legado) ===============
export const activateUserTrial90d = onCall(async (request) => {
  try {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }
    await checkRateLimit("activateUserTrial90d", getCallableIdentifier(request));

    const db = initDb();
    const uid = request.auth.uid;
    const email = normalizeEmail(request.auth.token?.email || "");

    const userRef = db.collection("users").doc(uid);
    const subRef = userRef.collection("subscriptions").doc();

    await db.runTransaction(async (tx) => {
      const userDoc = await tx.get(userRef);
      const data = userDoc.exists ? userDoc.data() || {} : {};
      if ((data.trialUsed ?? false) === true) {
        throw new HttpsError("failed-precondition", "TRIAL_ALREADY_USED");
      }
      const now = new Date();
      const end = addDays(now, 30);
      tx.set(
        userRef,
        {
          email: email || data.email || null,
          currentPlanId: "free_trial_30d",
          status: "trialing",
          trialing: true,
          currentPeriodEnd: Timestamp.fromDate(end),
          trialUsed: true,
          trialUsedAt: Timestamp.fromDate(now),
          manualOverride: { enabled: false },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.set(subRef, {
        planId: "free_trial_30d",
        status: "trialing",
        trialing: true,
        createdAt: FieldValue.serverTimestamp(),
        currentPeriodEnd: Timestamp.fromDate(end),
        kind: "trial",
      });
    });

    return { ok: true };
  } catch (err) {
    console.error("[activateUserTrial90d] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao ativar trial.");
  }
});
