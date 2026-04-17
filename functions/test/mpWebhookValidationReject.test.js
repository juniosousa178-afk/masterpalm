/**
 * Registro sanitizado de falha de validação do webhook MP (Firestore helpers).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { persistWebhookValidationReject } from "../src/mpWebhookHandler.js";

describe("persistWebhookValidationReject", () => {
  it("persiste apenas campos esperados (sem raw / PII extra)", async () => {
    let lastSet = null;
    const mockDb = {
      collection: () => ({
        doc: () => ({
          get: async () => ({ exists: false }),
          set: async (data, opts) => {
            lastSet = { data, opts };
          },
        }),
      }),
    };

    await persistWebhookValidationReject(mockDb, {
      paymentId: "123",
      lojaId: "lojaA",
      orderId: "ord1",
      externalReference: "ord1",
      validationReason: "amount_mismatch",
      paymentStatus: "approved",
      paymentMethod: "pix",
      amountExpectedCents: 5000,
      amountReceivedCents: 100,
      currencyId: null,
    });

    assert.equal(lastSet.opts.merge, true);
    assert.equal(lastSet.data.validationReason, "amount_mismatch");
    assert.equal(lastSet.data.lojaId, "lojaA");
    assert.equal(lastSet.data.orderId, "ord1");
    assert.equal(lastSet.data.paymentId, "123");
    assert.equal(lastSet.data.amountExpectedCents, 5000);
    assert.equal(lastSet.data.amountReceivedCents, 100);
    assert.equal(lastSet.data.raw, undefined);
    assert.equal(lastSet.data.payer, undefined);
    assert.equal(lastSet.data.metadataLojaId, undefined);
  });
});
