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
});
