/**
 * node --test test/mpCatalogPixAmount.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  normalizeBrlTransactionAmountForMpPix,
  mpCatalogPixProviderErrorIsAmountRelated,
  orderTotalToCents,
} from "../src/catalogMpOrderHelpers.js";

describe("normalizeBrlTransactionAmountForMpPix", () => {
  it("10.999 → transaction_amount 11.00 (centavos alinhados ao webhook)", () => {
    const r = normalizeBrlTransactionAmountForMpPix(10.999);
    assert.equal(r.ok, true);
    assert.equal(r.transactionAmount, 11);
    assert.equal(r.cents, 1100);
    assert.equal(orderTotalToCents(r.transactionAmount), orderTotalToCents(10.999));
  });

  it("33.333333 → 33.33", () => {
    const r = normalizeBrlTransactionAmountForMpPix(33.333333);
    assert.equal(r.ok, true);
    assert.equal(r.transactionAmount, 33.33);
    assert.equal(r.cents, 3333);
  });

  it("0 → rejeita (centavos < 1)", () => {
    const r = normalizeBrlTransactionAmountForMpPix(0);
    assert.equal(r.ok, false);
    assert.equal(r.code, "PIX_AMOUNT_INVALID");
  });

  it("NaN → rejeita", () => {
    const r = normalizeBrlTransactionAmountForMpPix(Number.NaN);
    assert.equal(r.ok, false);
    assert.equal(r.code, "PIX_AMOUNT_INVALID");
  });

  it("0.01 → aceita 1 centavo", () => {
    const r = normalizeBrlTransactionAmountForMpPix(0.01);
    assert.equal(r.ok, true);
    assert.equal(r.cents, 1);
    assert.equal(r.transactionAmount, 0.01);
  });

  it("valores inteiros e com 2 casas passam inalterados", () => {
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(100), { ok: true, transactionAmount: 100, cents: 10000 });
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(59.9), { ok: true, transactionAmount: 59.9, cents: 5990 });
  });

  it("artefato de ponto flutuante (0.1 + 0.2) → 0.3", () => {
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(0.1 + 0.2), { ok: true, transactionAmount: 0.3, cents: 30 });
  });

  it("meio centavo segue Math.round(n * 100 + EPSILON) sobre o double", () => {
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(33.335), { ok: true, transactionAmount: 33.34, cents: 3334 });
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(2.675), { ok: true, transactionAmount: 2.68, cents: 268 });
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(1.005), { ok: true, transactionAmount: 1, cents: 100 });
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix(0.005), { ok: true, transactionAmount: 0.01, cents: 1 });
  });

  it("total em string numérica é aceito; vírgula decimal não", () => {
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix("25.50"), { ok: true, transactionAmount: 25.5, cents: 2550 });
    assert.deepEqual(normalizeBrlTransactionAmountForMpPix("12,50"), { ok: false, code: "PIX_AMOUNT_INVALID" });
  });

  it("abaixo de 1 centavo, negativo, infinito e vazio → rejeita", () => {
    for (const v of [0.004, -5, Infinity, null, undefined, ""]) {
      assert.deepEqual(normalizeBrlTransactionAmountForMpPix(v), { ok: false, code: "PIX_AMOUNT_INVALID" }, String(v));
    }
  });
});

describe("mpCatalogPixProviderErrorIsAmountRelated", () => {
  it("Invalid transaction_amount → true", () => {
    assert.equal(
      mpCatalogPixProviderErrorIsAmountRelated("Invalid transaction_amount"),
      true,
    );
  });

  it("texto genérico sem amount → false", () => {
    assert.equal(mpCatalogPixProviderErrorIsAmountRelated("payer invalid"), false);
  });

  it("transaction amount / amount mismatch, sem diferenciar maiúsculas", () => {
    for (const s of [
      "Transaction Amount must be positive",
      "invalid_transaction_amount",
      "AMOUNT_MISMATCH",
      "amount mismatch detected",
    ]) {
      assert.equal(mpCatalogPixProviderErrorIsAmountRelated(s), true, s);
    }
  });

  it("palavra 'valor' só conta junto de inválido/invalid", () => {
    assert.equal(mpCatalogPixProviderErrorIsAmountRelated("Valor inválido"), true);
    assert.equal(mpCatalogPixProviderErrorIsAmountRelated("valor invalido"), true);
    assert.equal(mpCatalogPixProviderErrorIsAmountRelated("VALOR INVALID"), true);
    assert.equal(mpCatalogPixProviderErrorIsAmountRelated("valores inválidos"), false);
  });

  it("erros sem relação com valor e entradas vazias → false", () => {
    for (const s of ["bad_request", "amount invalid", "", "   ", null, undefined]) {
      assert.equal(mpCatalogPixProviderErrorIsAmountRelated(s), false, String(s));
    }
  });
});
