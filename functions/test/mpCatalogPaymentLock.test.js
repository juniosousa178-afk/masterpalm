/**
 * Trava transacional mpCatalogPayment — estado puro + simulação de serialização.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  evaluateMpCatalogPaymentLockState,
  MP_CATALOG_LOCK_MS,
} from "../src/mpCatalogPaymentLock.js";

const TTL_MS = 10 * 60 * 1000;

function ts(ms) {
  return { toMillis: () => ms };
}

/** Simula duas “requisições” aplicadas em sequência ao mesmo documento (como uma transação Firestore serializa). */
function applyAcquireOrReuse(doc, nowMs) {
  const d = { ...doc };
  const decision = evaluateMpCatalogPaymentLockState(d, nowMs, TTL_MS);
  if (decision.kind === "reuse") {
    return { doc: d, outcome: "reuse", result: decision.result };
  }
  if (decision.kind === "busy") {
    return { doc: d, outcome: "busy" };
  }
  const lockExpiry = nowMs + MP_CATALOG_LOCK_MS;
  return {
    doc: {
      ...d,
      mpCreating: true,
      mpLockUntil: ts(lockExpiry),
    },
    outcome: "acquired",
  };
}

describe("evaluateMpCatalogPaymentLockState", () => {
  const t0 = 1_700_000_000_000;

  it("reutiliza resultado recente (idempotência)", () => {
    const doc = {
      result: { id: "pay_1" },
      createdAt: ts(t0),
    };
    const r = evaluateMpCatalogPaymentLockState(doc, t0 + 1000, TTL_MS);
    assert.equal(r.kind, "reuse");
    assert.deepEqual(r.result, { id: "pay_1" });
  });

  it("após TTL do resultado, permite acquire", () => {
    const doc = {
      result: { id: "old" },
      createdAt: ts(t0),
    };
    const r = evaluateMpCatalogPaymentLockState(doc, t0 + TTL_MS + 1, TTL_MS);
    assert.equal(r.kind, "acquire");
  });

  it("trava ativa sem resultado final → busy", () => {
    const doc = {
      mpCreating: true,
      mpLockUntil: ts(t0 + 30_000),
    };
    const r = evaluateMpCatalogPaymentLockState(doc, t0 + 10_000, TTL_MS);
    assert.equal(r.kind, "busy");
  });

  it("trava expirada → acquire (não deixa pedido preso)", () => {
    const doc = {
      mpCreating: true,
      mpLockUntil: ts(t0 + 1000),
    };
    const r = evaluateMpCatalogPaymentLockState(doc, t0 + MP_CATALOG_LOCK_MS, TTL_MS);
    assert.equal(r.kind, "acquire");
  });
});

describe("simulação concorrência (mesmo estado, serializado)", () => {
  const t0 = 1_700_000_000_000;

  it("duas tentativas no mesmo instante: primeira acquire, segunda busy", () => {
    let doc = {};
    const a = applyAcquireOrReuse(doc, t0);
    assert.equal(a.outcome, "acquired");
    const b = applyAcquireOrReuse(a.doc, t0);
    assert.equal(b.outcome, "busy");
  });

  it("segunda chamada reaproveita resultado quando já persistido", () => {
    let doc = {
      result: { id: "pref_1" },
      createdAt: ts(t0),
    };
    const a = applyAcquireOrReuse(doc, t0 + 500);
    assert.equal(a.outcome, "reuse");
    assert.equal(a.result.id, "pref_1");
  });

  it("após falha simulada (release), novo acquire é possível no mesmo doc base", () => {
    let doc = {};
    const a = applyAcquireOrReuse(doc, t0);
    assert.equal(a.outcome, "acquired");
    // releaseMpCatalogPaymentLock limparia mpCreating/mpLockUntil
    const released = {
      ...a.doc,
      mpCreating: false,
      mpLockUntil: undefined,
    };
    const b = applyAcquireOrReuse(released, t0 + 100);
    assert.equal(b.outcome, "acquired");
  });
});
