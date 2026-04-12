/**
 * Helpers de assinatura recorrente (sem emulator).
 * node --test test/mpPlanRecurring.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  inferPeriodEndFromPreapproval,
  mergePendingPreapprovalPatch,
  parseExternalReferenceMpRecurring,
} from "../src/mpPlanRecurring.js";

describe("parseExternalReferenceMpRecurring", () => {
  it("parseia mprec|uid|plan", () => {
    const r = parseExternalReferenceMpRecurring("mprec|abc123|pro_monthly");
    assert.equal(r.uid, "abc123");
    assert.equal(r.canonicalPlanId, "pro_monthly");
  });

  it("retorna null fora do formato", () => {
    assert.equal(parseExternalReferenceMpRecurring("uid|plan"), null);
    assert.equal(parseExternalReferenceMpRecurring(""), null);
  });
});

describe("mergePendingPreapprovalPatch", () => {
  it("sem email não define chave email (não apaga campo existente no merge)", () => {
    const p = mergePendingPreapprovalPatch({
      billingPatch: { provider: "mercado_pago", billingVersion: 2 },
      email: "",
      nowTs: "ts",
    });
    assert.equal(p.email, undefined);
    assert.equal(p.billingSource, "mp_preapproval_pending");
  });

  it("com email define lowercase", () => {
    const p = mergePendingPreapprovalPatch({
      billingPatch: { provider: "mercado_pago" },
      email: " A@Test.COM ",
      nowTs: "ts",
    });
    assert.equal(p.email, "a@test.com");
  });
});

describe("inferPeriodEndFromPreapproval", () => {
  it("usa next_payment_date quando presente", () => {
    const d = new Date("2030-06-15T12:00:00.000Z");
    const end = inferPeriodEndFromPreapproval(
      { next_payment_date: d.toISOString() },
      new Date("2025-01-01"),
    );
    assert.equal(end.toISOString(), d.toISOString());
  });

  it("aproxima por frequency mensal quando não há data", () => {
    const now = new Date("2025-03-10T12:00:00.000Z");
    const end = inferPeriodEndFromPreapproval(
      {
        auto_recurring: { frequency: 1, frequency_type: "months" },
      },
      now,
    );
    assert.equal(end.getMonth(), 3); // abril 0-based -> 3? March +1 = April -> month 3 in 0-index is April
    assert.equal(end.getFullYear(), 2025);
  });
});
