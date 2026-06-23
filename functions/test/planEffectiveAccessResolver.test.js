/**
 * node --test test/planEffectiveAccessResolver.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  resolveEffectivePlanAccess,
  normalizePlanId,
  toDateAny,
  maskProviderSubscriptionIdForLog,
} from "../src/planEffectiveAccessResolver.js";

const future = () => new Date(Date.now() + 86_400_000 * 30);
const past = () => new Date(Date.now() - 86_400_000 * 10);

function baseUser(overrides = {}) {
  return {
    currentPlanId: "free_limited",
    status: "active",
    trialing: false,
    ...overrides,
  };
}

describe("toDateAny", () => {
  it("aceita Date, ISO string, millis e Timestamp-like", () => {
    const d = new Date("2030-01-15T12:00:00.000Z");
    assert.equal(toDateAny(d)?.toISOString(), d.toISOString());
    assert.equal(toDateAny(d.toISOString())?.toISOString(), d.toISOString());
    assert.equal(toDateAny(d.getTime())?.getTime(), d.getTime());
    assert.equal(
      toDateAny({ toDate: () => d })?.toISOString(),
      d.toISOString(),
    );
    assert.equal(toDateAny(null), null);
    assert.equal(toDateAny("invalid"), null);
  });
});

describe("resolveEffectivePlanAccess — precedência", () => {
  it("6. root lifetime retorna root_lifetime", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u1",
      email: "masterpalm26@gmail.com",
      userData: baseUser({ currentPlanId: "free_limited" }),
    });
    assert.equal(r.accessSource, "root_lifetime");
    assert.equal(r.effectivePlanId, "lifetime");
    assert.equal(r.effectiveStatus, "active");
  });

  it("7. courtesyGrant temporária válida vence assinatura paga", () => {
    const end = future();
    const r = resolveEffectivePlanAccess({
      uid: "u2",
      email: "cliente@test.com",
      userData: baseUser({
        currentPlanId: "basic_monthly",
        currentPeriodEnd: end,
        status: "active",
      }),
      courtesyGrant: {
        active: true,
        planId: "intermediate_monthly",
        type: "temporary",
        expiresAt: end,
        reason: "Cortesia comercial",
        grantedByEmail: "masterpalm26@gmail.com",
      },
    });
    assert.equal(r.accessSource, "manual_courtesy");
    assert.equal(r.effectivePlanId, "intermediate_monthly");
    assert.equal(r.contractedPlanId, "basic_monthly");
    assert.equal(r.effectiveStatus, "courtesy_active");
  });

  it("8. courtesyGrant vencida não eleva acesso", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u3",
      email: "cliente@test.com",
      userData: baseUser({
        currentPlanId: "basic_monthly",
        currentPeriodEnd: future(),
        status: "active",
      }),
      courtesyGrant: {
        active: true,
        planId: "intermediate_monthly",
        type: "temporary",
        expiresAt: past(),
      },
    });
    assert.notEqual(r.accessSource, "manual_courtesy");
    assert.equal(r.effectivePlanId, "basic_monthly");
  });

  it("9. manual_grant lifetime ativo é reconhecido", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u4",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "pro_monthly",
        manual_grant: { type: "lifetime" },
      }),
    });
    assert.equal(r.accessSource, "manual_grant_legacy");
    assert.equal(r.effectivePlanId, "pro_monthly");
  });

  it("10. manual_grant until expirado não eleva acesso", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u5",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "intermediate_monthly",
        currentPeriodEnd: past(),
        manual_grant: { type: "until", untilAt: past() },
      }),
    });
    assert.notEqual(r.accessSource, "manual_grant_legacy");
  });

  it("11. manualOverride válido eleva acesso", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u6",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "free_limited",
        manualOverride: { enabled: true, planId: "pro_monthly" },
      }),
    });
    assert.equal(r.accessSource, "manual_override_legacy");
    assert.equal(r.effectivePlanId, "pro_monthly");
    assert.equal(r.contractedPlanId, "free_limited");
  });

  it("12. assinatura paga ativa retorna plano contratado", () => {
    const end = future();
    const r = resolveEffectivePlanAccess({
      uid: "u7",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "basic_monthly",
        currentPeriodEnd: end,
        status: "active",
      }),
    });
    assert.equal(r.accessSource, "paid_subscription");
    assert.equal(r.effectivePlanId, "basic_monthly");
    assert.equal(r.effectiveStatus, "active");
  });

  it("13. cancelAtPeriodEnd mantém plano até currentPeriodEnd", () => {
    const end = future();
    const r = resolveEffectivePlanAccess({
      uid: "u8",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "basic_monthly",
        currentPeriodEnd: end,
        cancelAtPeriodEnd: true,
        status: "active",
      }),
    });
    assert.equal(r.effectiveStatus, "cancel_scheduled");
    assert.equal(r.effectivePlanId, "basic_monthly");
    assert.equal(r.renewal.cancelAtPeriodEnd, true);
    assert.equal(r.renewal.active, false);
  });

  it("14. plano pago após vencimento cai para free_limited", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u9",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "basic_monthly",
        currentPeriodEnd: past(),
        status: "active",
      }),
    });
    assert.equal(r.effectivePlanId, "free_limited");
    assert.equal(r.accessSource, "free_limited");
    assert.equal(r.effectiveStatus, "free_limited");
  });

  it("15. trial ativo é reconhecido", () => {
    const end = future();
    const r = resolveEffectivePlanAccess({
      uid: "u10",
      email: "a@test.com",
      userData: baseUser({
        currentPlanId: "free_trial_30d",
        trialing: true,
        currentPeriodEnd: end,
      }),
    });
    assert.equal(r.accessSource, "trial");
    assert.equal(r.effectivePlanId, "free_trial_30d");
    assert.equal(r.trial.active, true);
  });

  it("9. courtesy permanente válida eleva plano", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u_perm",
      email: "cliente@test.com",
      userData: baseUser({ currentPlanId: "free_limited" }),
      courtesyGrant: {
        active: true,
        planId: "pro_monthly",
        type: "permanent",
        expiresAt: null,
        reason: "Parceria",
      },
    });
    assert.equal(r.accessSource, "manual_courtesy");
    assert.equal(r.effectivePlanId, "pro_monthly");
    assert.equal(r.courtesy.permanent, true);
  });

  it("10. blocked_reason administrativo não é ultrapassado por cortesia", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u_block",
      email: "cliente@test.com",
      userData: baseUser({
        status: "blocked",
        blocked_reason: "admin: conta suspensa",
        currentPlanId: "free_limited",
      }),
      courtesyGrant: {
        active: true,
        planId: "pro_monthly",
        type: "permanent",
      },
    });
    assert.equal(r.accessSource, "blocked");
    assert.equal(r.effectiveStatus, "blocked");
    assert.notEqual(r.effectivePlanId, "pro_monthly");
  });

  it("16. planId inválido em manualOverride não eleva acesso", () => {
    const r = resolveEffectivePlanAccess({
      uid: "u11",
      email: "a@test.com",
      userData: baseUser({
        manualOverride: { enabled: true, planId: "plano_inexistente_xyz" },
      }),
    });
    assert.notEqual(r.accessSource, "manual_override_legacy");
  });

  it("17. providerSubscriptionId nunca aparece completo", () => {
    const longId = "2548a2747031404f86a1339ca1e4e3d6";
    const r = resolveEffectivePlanAccess({
      uid: "u12",
      email: "a@test.com",
      userData: baseUser({
        providerSubscriptionId: longId,
        billingSource: "mp_subscription",
      }),
    });
    assert.notEqual(r.subscription.maskedProviderSubscriptionId, longId);
    assert.ok(r.subscription.maskedProviderSubscriptionId.includes("…"));
    assert.equal(maskProviderSubscriptionIdForLog(longId), "2548…e3d6");
  });
});

describe("normalizePlanId", () => {
  it("normaliza aliases legados", () => {
    assert.equal(normalizePlanId("mensal"), "pro_monthly");
    assert.equal(normalizePlanId("basic"), "basic_monthly");
  });
});
