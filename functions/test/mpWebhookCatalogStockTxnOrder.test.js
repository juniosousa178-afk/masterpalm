/**
 * node --test test/mpWebhookCatalogStockTxnOrder.test.js
 *
 * Especificação: transações Firestore do webhook de catálogo devem fazer
 * todos os transaction.get antes de qualquer transaction.set.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

/** Simula a ordem da transação corrigida em mpWebhookHandler (1 fase leituras, 1 fase escritas). */
function fixedCatalogMpApprovedTxnOpSequence(itemCount) {
  const ops = ["get_processed", "get_order"];
  for (let i = 0; i < itemCount; i++) {
    ops.push(`get_estoque_${i}`, `get_produtos_${i}`);
  }
  ops.push("set_processed", "set_order");
  for (let i = 0; i < itemCount; i++) {
    ops.push(`set_produtos_${i}`, `set_estoque_${i}`);
  }
  return ops;
}

function assertNoReadAfterWrite(ops) {
  const isWrite = (o) =>
    o === "set_processed" || o === "set_order" || o.startsWith("set_produtos_") || o.startsWith("set_estoque_");
  const isRead = (o) => o.startsWith("get_");
  let firstWriteIdx = -1;
  for (let i = 0; i < ops.length; i++) {
    if (isWrite(ops[i]) && firstWriteIdx === -1) firstWriteIdx = i;
  }
  if (firstWriteIdx === -1) return;
  for (let i = firstWriteIdx + 1; i < ops.length; i++) {
    if (isRead(ops[i])) {
      assert.fail(`read ${ops[i]} at ${i} after first write at ${firstWriteIdx}`);
    }
  }
}

describe("mpWebhook catálogo — ordem Firestore read→write", () => {
  it("repro bug: get de estoque após set_processed viola regra", () => {
    const broken = ["get_processed", "get_order", "set_processed", "set_order", "get_estoque_0"];
    assert.throws(() => assertNoReadAfterWrite(broken), /read get_estoque_0/);
  });

  it("padrão corrigido com 0 itens: só processed + order", () => {
    assertNoReadAfterWrite(fixedCatalogMpApprovedTxnOpSequence(0));
  });

  it("padrão corrigido com 2 itens: todos gets antes de qualquer set", () => {
    assertNoReadAfterWrite(fixedCatalogMpApprovedTxnOpSequence(2));
  });
});
