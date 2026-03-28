// functions/src/ensureUserPlan.js  (ESM / Node 20)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const ROOT_EMAIL = "masterpalm@gmail.com";

// LEGACY FLOW: callable mantido por retrocompatibilidade.
// Fonte principal de assinatura/plano continua sendo o fluxo canônico
// users/{uid}.currentPlanId/status/trialing/currentPeriodEnd.

function normalizeCanonicalPlanId(raw) {
  const p = String(raw || "").trim().toLowerCase();
  if (p === "mensal" || p === "pro_monthly") return "pro_monthly";
  if (p === "anual" || p === "pro_yearly") return "pro_yearly";
  if (p === "trial" || p === "trial_90d" || p === "free_trial_90d") return "free_trial_90d";
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

// Trial 3 meses
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

async function computePlanState({ db, uid, email }) {
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

  // 2) Plano pago (mensal/anual)
  const canonicalPlan = normalizeCanonicalPlanId(data.currentPlanId || data.plan || "");
  const plan = toLegacyPlanAlias(canonicalPlan);
  const renewAt = toDateAny(data.currentPeriodEnd || data.plan_renewsAt);

  if ((canonicalPlan === "pro_monthly" || canonicalPlan === "pro_yearly") && renewAt) {
    if (now <= renewAt) {
      const daysLeft = daysBetweenCeil(now, renewAt);

      // Notifica 15 dias antes, de 5 em 5 dias
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

      return {
        status: "active",
        plan,
        isRoot: false,
        daysLeft,
        endsAt: renewAt.toISOString(),
        shouldNotify,
        notifyMsg,
        allowPlans: ["mensal", "anual"],
        message: "Plano pago ativo.",
        userDoc: data,
      };
    }

    // vencido
    await ref.set(
      {
        email,
        currentPlanId: canonicalPlan,
        status: "inactive",
        trialing: false,
        currentPeriodEnd: Timestamp.fromDate(renewAt),
        blocked_reason: "Plano pago vencido",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      status: "blocked",
      plan,
      isRoot: false,
      daysLeft: 0,
      endsAt: renewAt.toISOString(),
      shouldNotify: true,
      notifyMsg: "Seu plano venceu. Assine para continuar.",
      allowPlans: ["mensal", "anual"],
      message: "Plano vencido.",
      userDoc: data,
    };
  }

  // 3) Trial 3 meses (uma vez)
  const trialUsed = !!data.trial_used;
  const trialEndsAt = toDateAny(data.trial_endsAt);
  const trialStartedAt = toDateAny(data.trial_startedAt);

  if (!trialUsed && !trialEndsAt && !trialStartedAt) {
    const start = now;
    const end = addMonths(now, 3);

    await ref.set(
      {
        email,
        currentPlanId: "free_trial_90d",
        status: "trialing",
        trialing: true,
        currentPeriodEnd: Timestamp.fromDate(end),
        trial_used: true,
        trial_startedAt: Timestamp.fromDate(start),
        trial_endsAt: Timestamp.fromDate(end),
        notify_lastAt: FieldValue.delete(),
        blocked_reason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: data.createdAt || FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const daysLeft = daysBetweenCeil(now, end);

    return {
      status: "active",
      plan: "trial",
      isRoot: false,
      daysLeft,
      endsAt: end.toISOString(),
      shouldNotify: false,
      allowPlans: ["mensal", "anual"],
      message: "Trial iniciado (3 meses).",
      userDoc: data,
    };
  }

  // Trial existente
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
    plan: plan || "none",
    isRoot: false,
    daysLeft: 0,
    endsAt: null,
    shouldNotify: true,
    notifyMsg: "Você precisa assinar um plano (mensal ou anual) para continuar.",
    allowPlans: ["mensal", "anual"],
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
    };
  } catch (err) {
    console.error("[ensureUserPlan] error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Erro ao validar plano do usuário.");
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
