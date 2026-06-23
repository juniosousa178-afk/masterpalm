/**
 * Resolver puro de acesso efetivo (plano contratado vs acesso efetivo).
 * Sem I/O — não lê/escreve Firestore nem chama provedores externos.
 */

import { isRootAccountEmail } from "./rootAccounts.js";
import { maskProviderSubscriptionIdForLog } from "./mpPlanRecurring.js";
import { maskEmailForAudit } from "./planSupportRead.js";
import { PAID_PLANS_WITH_RENEWAL } from "../ensureUserPlan.js";

export { maskEmailForAudit, maskProviderSubscriptionIdForLog };

const KNOWN_PLAN_IDS = new Set([
  "pro_monthly",
  "pro_yearly",
  "basic_monthly",
  "intermediate_monthly",
  "free_trial_30d",
  "free_trial_90d",
  "free_limited",
  "lifetime",
  "mensal",
  "anual",
]);

export function normalizePlanId(raw) {
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

export function isKnownPlanId(planId) {
  const n = normalizePlanId(planId);
  return KNOWN_PLAN_IDS.has(n) || n === "pro_monthly" || n === "pro_yearly";
}

/** Planos que podem ser concedidos via cortesia Mestre. */
export const GRANTABLE_COURTESY_PLAN_IDS = Object.freeze([
  "basic_monthly",
  "intermediate_monthly",
  "pro_monthly",
  "pro_yearly",
  "lifetime",
  "free_trial_30d",
  "free_trial_90d",
]);

export function isGrantableCourtesyPlanId(planId) {
  return GRANTABLE_COURTESY_PLAN_IDS.includes(normalizePlanId(planId));
}

/** Bloqueio administrativo grave — cortesia não ultrapassa. */
export function isAdministrativeHardBlock(userData) {
  const d = userData && typeof userData === "object" ? userData : {};
  if (d.adminAccessBlocked === true) return true;
  if (String(d.status || "").toLowerCase() === "blocked") return true;
  const br = String(d.blocked_reason || "").trim();
  return br.toLowerCase().startsWith("admin:");
}

/** @param {unknown} v */
export function toDateAny(v) {
  if (v == null) return null;
  if (v instanceof Date) {
    return Number.isNaN(v.getTime()) ? null : v;
  }
  if (typeof v?.toDate === "function") {
    try {
      const d = v.toDate();
      return d instanceof Date && !Number.isNaN(d.getTime()) ? d : null;
    } catch {
      return null;
    }
  }
  if (typeof v === "number" && Number.isFinite(v)) {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === "string") {
    const s = v.trim();
    if (!s) return null;
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function daysBetweenCeil(from, to) {
  const ms = to.getTime() - from.getTime();
  if (ms <= 0) return 0;
  return Math.ceil(ms / (1000 * 60 * 60 * 24));
}

function isoOrNull(d) {
  return d ? d.toISOString() : null;
}

function buildSubscriptionBlock(userData) {
  const billingSource = userData?.billingSource != null ? String(userData.billingSource) : null;
  const providerSubscriptionId =
    userData?.providerSubscriptionId != null ? String(userData.providerSubscriptionId) : null;
  const billingVersion =
    userData?.billingVersion != null && userData.billingVersion !== ""
      ? Number(userData.billingVersion)
      : null;
  const billingMode =
    userData?.billingMode != null ? String(userData.billingMode).toLowerCase() : null;
  const planStatus =
    userData?.planStatus != null ? String(userData.planStatus).toLowerCase() : null;

  let provider = null;
  if (billingSource?.toLowerCase().startsWith("mp_")) provider = "mercado_pago";
  else if (providerSubscriptionId) provider = "mercado_pago";

  let paymentMethodLabel = null;
  if (provider === "mercado_pago") {
    if (billingMode === "recurring" || billingVersion === 2) {
      paymentMethodLabel = "Mercado Pago (recorrente)";
    } else {
      paymentMethodLabel = "Mercado Pago";
    }
  }

  return {
    provider,
    paymentMethodLabel,
    billingVersion: Number.isFinite(billingVersion) ? billingVersion : null,
    billingSource,
    billingMode,
    planStatus,
    maskedProviderSubscriptionId: providerSubscriptionId
      ? maskProviderSubscriptionIdForLog(providerSubscriptionId)
      : null,
  };
}

function emptyCourtesy() {
  return {
    active: false,
    source: null,
    planId: null,
    type: null,
    startsAt: null,
    expiresAt: null,
    permanent: false,
    reason: null,
    grantedByEmailMasked: null,
    grantedAt: null,
    revokedAt: null,
  };
}

function courtesyFromGrant(courtesyGrant, now) {
  if (!courtesyGrant || typeof courtesyGrant !== "object") {
    return emptyCourtesy();
  }
  if (courtesyGrant.active !== true) return emptyCourtesy();

  const planId = normalizePlanId(courtesyGrant.planId);
  if (!isKnownPlanId(planId)) return emptyCourtesy();

  const type = String(courtesyGrant.type || "").toLowerCase();
  const permanent = type === "permanent";
  const startsAt = toDateAny(courtesyGrant.startsAt);
  const expiresAt = toDateAny(courtesyGrant.expiresAt);

  if (startsAt && now < startsAt) return emptyCourtesy();
  if (!permanent) {
    if (!expiresAt || now > expiresAt) return emptyCourtesy();
  }

  return {
    active: true,
    source: "manual_courtesy",
    planId,
    type: permanent ? "permanent" : "temporary",
    startsAt: isoOrNull(startsAt),
    expiresAt: permanent ? null : isoOrNull(expiresAt),
    permanent,
    reason: courtesyGrant.reason != null ? String(courtesyGrant.reason).slice(0, 500) : null,
    grantedByEmailMasked: maskEmailForAudit(courtesyGrant.grantedByEmail),
    grantedAt: isoOrNull(toDateAny(courtesyGrant.grantedAt)),
    revokedAt: isoOrNull(toDateAny(courtesyGrant.revokedAt)),
  };
}

function isManualGrantActive(mg, now) {
  if (!mg || typeof mg !== "object") return false;
  const type = String(mg.type || "").toLowerCase();
  if (type === "lifetime") return true;
  if (type === "until") {
    const untilAt = toDateAny(mg.untilAt);
    return !!(untilAt && now <= untilAt);
  }
  return false;
}

function manualGrantPlanId(mg, userData) {
  const fromGrant = normalizePlanId(mg?.planId || "");
  if (isKnownPlanId(fromGrant)) return fromGrant;
  const fromUser = normalizePlanId(userData?.currentPlanId || "");
  if (isKnownPlanId(fromUser)) return fromUser;
  return null;
}

function isManualOverrideActive(mo) {
  if (!mo || typeof mo !== "object") return false;
  if (mo.enabled !== true) return false;
  const pid = normalizePlanId(mo.planId || "");
  return isKnownPlanId(pid);
}

function manualOverridePlanId(mo) {
  return isManualOverrideActive(mo) ? normalizePlanId(mo.planId) : null;
}

function isPaidPeriodActive(canonicalPlan, renewAt, now) {
  if (canonicalPlan === "lifetime") return true;
  if (!PAID_PLANS_WITH_RENEWAL.includes(canonicalPlan)) return false;
  if (!renewAt) return false;
  return now <= renewAt;
}

function isTrialActive(canonicalPlan, userData, renewAt, now) {
  if (canonicalPlan !== "free_trial_30d" && canonicalPlan !== "free_trial_90d") {
    return false;
  }
  if (userData?.trialing !== true) return false;
  if (!renewAt) return false;
  return now <= renewAt;
}

/**
 * @param {object} opts
 * @param {string} opts.uid
 * @param {string} opts.email
 * @param {object} opts.userData
 * @param {Date} [opts.now]
 * @param {object|null} [opts.courtesyGrant]
 */
export function resolveEffectivePlanAccess({
  uid,
  email,
  userData,
  now = new Date(),
  courtesyGrant = null,
}) {
  const data = userData && typeof userData === "object" ? userData : {};
  const em = String(email || data.email || "").trim().toLowerCase();
  const contractedPlanId = normalizePlanId(data.currentPlanId || data.plan || "");
  const renewAt = toDateAny(data.currentPeriodEnd || data.plan_renewsAt || data.current_period_end);
  const cancelAtPeriodEnd =
    data.cancelAtPeriodEnd === true || data.cancel_at_period_end === true;
  const blockedReason =
    data.blocked_reason != null ? String(data.blocked_reason) : null;

  const subscription = buildSubscriptionBlock(data);
  const courtesy = courtesyFromGrant(courtesyGrant, now);

  const renewal = {
    active: !cancelAtPeriodEnd && isPaidPeriodActive(contractedPlanId, renewAt, now),
    cancelAtPeriodEnd,
    cancelledAt: cancelAtPeriodEnd
      ? isoOrNull(toDateAny(data.renewalCancelledAt || data.cancelledAt))
      : null,
    renewsAt: isoOrNull(renewAt),
  };

  const trialEndsAt =
    contractedPlanId === "free_trial_30d" || contractedPlanId === "free_trial_90d"
      ? renewAt
      : toDateAny(data.trial_endsAt);
  const trialActive = isTrialActive(contractedPlanId, data, renewAt, now);

  const trial = {
    active: trialActive,
    endsAt: isoOrNull(trialEndsAt || renewAt),
  };

  const base = {
    contractedPlanId: contractedPlanId || null,
    effectivePlanId: contractedPlanId || "free_limited",
    accessSource: "expired",
    effectiveStatus: "expired",
    currentPeriodEnd: isoOrNull(renewAt),
    daysRemaining: renewAt && renewAt > now ? daysBetweenCeil(now, renewAt) : 0,
    nextDowngradeAt:
      cancelAtPeriodEnd && renewAt && renewAt > now ? isoOrNull(renewAt) : null,
    renewal,
    subscription,
    courtesy,
    trial,
    blockedReason,
  };

  // 1. Bloqueio administrativo grave
  if (isAdministrativeHardBlock(data)) {
    return {
      ...base,
      effectivePlanId: "free_limited",
      accessSource: "blocked",
      effectiveStatus: "blocked",
      daysRemaining: 0,
      nextDowngradeAt: null,
      courtesy: emptyCourtesy(),
    };
  }

  // 2. Root lifetime
  if (isRootAccountEmail(em)) {
    return {
      ...base,
      effectivePlanId: "lifetime",
      accessSource: "root_lifetime",
      effectiveStatus: "active",
      currentPeriodEnd: null,
      daysRemaining: null,
      nextDowngradeAt: null,
      renewal: { active: false, cancelAtPeriodEnd: false, cancelledAt: null, renewsAt: null },
    };
  }

  // 3. Cortesia manual ativa (manualCourtesyGrant — somente quando fornecida)
  if (courtesy.active) {
    return {
      ...base,
      effectivePlanId: courtesy.planId,
      accessSource: "manual_courtesy",
      effectiveStatus: "courtesy_active",
      currentPeriodEnd: courtesy.expiresAt,
      daysRemaining:
        courtesy.expiresAt != null
          ? daysBetweenCeil(now, new Date(courtesy.expiresAt))
          : null,
      nextDowngradeAt: courtesy.permanent ? null : courtesy.expiresAt,
    };
  }

  // 4. manual_grant legado
  const mg = data.manual_grant;
  if (isManualGrantActive(mg, now)) {
    const mgp = manualGrantPlanId(mg, data);
    if (mgp) {
      const mgUntil = toDateAny(mg?.untilAt);
      return {
        ...base,
        effectivePlanId: mgp,
        accessSource: "manual_grant_legacy",
        effectiveStatus: "active",
        currentPeriodEnd: String(mg?.type || "").toLowerCase() === "lifetime" ? null : isoOrNull(mgUntil),
        daysRemaining:
          mgUntil && mgUntil > now ? daysBetweenCeil(now, mgUntil) : null,
        nextDowngradeAt: null,
      };
    }
  }

  // 5. manualOverride legado
  const mo = data.manualOverride;
  const moPlan = manualOverridePlanId(mo);
  if (moPlan) {
    const moEnd = renewAt;
    return {
      ...base,
      effectivePlanId: moPlan,
      accessSource: "manual_override_legacy",
      effectiveStatus: "active",
      currentPeriodEnd: moPlan === "lifetime" ? null : isoOrNull(moEnd),
      daysRemaining:
        moPlan === "lifetime"
          ? null
          : moEnd && moEnd > now
            ? daysBetweenCeil(now, moEnd)
            : 0,
      nextDowngradeAt: null,
      renewal: { active: false, cancelAtPeriodEnd: false, cancelledAt: null, renewsAt: null },
    };
  }

  // 6–7. Assinatura paga ativa (inclui cancelAtPeriodEnd com período futuro)
  if (isPaidPeriodActive(contractedPlanId, renewAt, now)) {
    const scheduled = cancelAtPeriodEnd === true;
    return {
      ...base,
      effectivePlanId: contractedPlanId,
      accessSource: "paid_subscription",
      effectiveStatus: scheduled ? "cancel_scheduled" : "active",
      daysRemaining: daysBetweenCeil(now, renewAt),
      nextDowngradeAt: scheduled ? isoOrNull(renewAt) : null,
      renewal: {
        active: !scheduled,
        cancelAtPeriodEnd: scheduled,
        cancelledAt: scheduled
          ? isoOrNull(toDateAny(data.renewalCancelledAt || data.cancelledAt))
          : null,
        renewsAt: isoOrNull(renewAt),
      },
    };
  }

  if (contractedPlanId === "lifetime") {
    return {
      ...base,
      effectivePlanId: "lifetime",
      accessSource: "paid_subscription",
      effectiveStatus: "active",
      currentPeriodEnd: null,
      daysRemaining: null,
      nextDowngradeAt: null,
    };
  }

  // 8. Trial ativo
  if (trialActive) {
    return {
      ...base,
      effectivePlanId: contractedPlanId,
      accessSource: "trial",
      effectiveStatus: "active",
      daysRemaining: renewAt ? daysBetweenCeil(now, renewAt) : 0,
    };
  }

  // 9. free_limited
  if (contractedPlanId === "free_limited") {
    return {
      ...base,
      effectivePlanId: "free_limited",
      accessSource: "free_limited",
      effectiveStatus: "free_limited",
      currentPeriodEnd: null,
      daysRemaining: null,
      nextDowngradeAt: null,
    };
  }

  // Pago vencido → espelha downgrade para free_limited (sem alterar doc)
  if (PAID_PLANS_WITH_RENEWAL.includes(contractedPlanId) && renewAt && now > renewAt) {
    return {
      ...base,
      effectivePlanId: "free_limited",
      accessSource: "free_limited",
      effectiveStatus: "free_limited",
      currentPeriodEnd: null,
      daysRemaining: null,
      nextDowngradeAt: null,
      blockedReason: blockedReason || "Período pago encerrado",
    };
  }

  // 9. Expirado / bloqueado
  return {
    ...base,
    effectivePlanId: contractedPlanId || "free_limited",
    accessSource: "expired",
    effectiveStatus: "expired",
    daysRemaining: 0,
  };
}

/** Resumo de lista (subset seguro do DTO completo). */
export function toListUserPlanAccessRow({ uid, userData, email, courtesyGrant, now }) {
  const em = String(email || userData?.email || "").trim().toLowerCase();
  const access = resolveEffectivePlanAccess({
    uid,
    email: em,
    userData,
    now,
    courtesyGrant,
  });

  const lojaId = String(
    userData?.lojaId || userData?.storeId || userData?.store_id || userData?.ownerStoreId || "",
  ).trim();
  const nome = String(userData?.nome || userData?.displayName || userData?.name || "").trim();

  const updatedAtRaw = userData?.updatedAt || userData?.planLastSyncedAt;
  let updatedAt = null;
  const u = toDateAny(updatedAtRaw);
  if (u) updatedAt = u.toISOString();

  return {
    uid,
    emailMasked: maskEmailForAudit(em),
    store: {
      lojaId: lojaId || null,
      nome: nome || null,
    },
    contractedPlanId: access.contractedPlanId,
    effectivePlanId: access.effectivePlanId,
    accessSource: access.accessSource,
    effectiveStatus: access.effectiveStatus,
    currentPeriodEnd: access.currentPeriodEnd,
    daysRemaining: access.daysRemaining,
    renewal: {
      cancelAtPeriodEnd: access.renewal.cancelAtPeriodEnd,
      active: access.renewal.active,
    },
    subscription: {
      provider: access.subscription.provider,
      paymentMethodLabel: access.subscription.paymentMethodLabel,
      maskedProviderSubscriptionId: access.subscription.maskedProviderSubscriptionId,
    },
    courtesy: {
      active: access.courtesy.active,
      planId: access.courtesy.planId,
      expiresAt: access.courtesy.expiresAt,
      permanent: access.courtesy.permanent,
    },
    updatedAt,
  };
}
