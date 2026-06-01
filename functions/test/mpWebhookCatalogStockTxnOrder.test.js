/**
 * node --test test/mpWebhookCatalogStockTxnOrder.test.js
 *
 * Transação Firestore do webhook catálogo: todas as leituras antes de escritas.
 * Idempotência e baixa de estoque (helpers puros + simulador de ordem de ops).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseCatalogOrderLineItemsForStock,
  computeCatalogStockDeductionPayloads,
  catalogMpApprovedTxnOpSequence,
  assertCatalogMpTxnNoReadAfterWrite,
} from "../src/mpWebhookHandler.js";

const NOW = { __type: "serverTimestamp" };

function simulateCatalogApprovedTxnOps(stockOps, { processedExists = false, orderPaid = false } = {}) {
  const ops = [];
  ops.push("get_processed");
  if (processedExists) return ops;

  ops.push("get_order");
  if (orderPaid) {
    ops.push("set_processed");
    return ops;
  }

  for (let i = 0; i < stockOps.length; i++) {
    ops.push(`get_estoque_${i}`, `get_produtos_${i}`);
  }
  ops.push("set_processed", "set_order");
  for (let i = 0; i < stockOps.length; i++) {
    ops.push(`set_produtos_${i}`, `set_estoque_${i}`);
  }
  return ops;
}

describe("mpWebhook catálogo — ordem Firestore read→write", () => {
  it("repro bug: get de estoque após set_processed viola regra", () => {
    const broken = ["get_processed", "get_order", "set_processed", "set_order", "get_estoque_0"];
    assert.throws(() => assertCatalogMpTxnNoReadAfterWrite(broken), /read get_estoque_0/);
  });

  it("padrão corrigido com 0 itens: só processed + order", () => {
    assertCatalogMpTxnNoReadAfterWrite(catalogMpApprovedTxnOpSequence(0));
  });

  it("padrão corrigido com 2 itens: todos gets antes de qualquer set", () => {
    assertCatalogMpTxnNoReadAfterWrite(catalogMpApprovedTxnOpSequence(2));
  });

  it("simulador de transação aprovada não faz read depois de write", () => {
    const lines = parseCatalogOrderLineItemsForStock([
      { id: "p1", quantidade: 1 },
      { id: "p2", quantidade: 2 },
    ]);
    const ops = simulateCatalogApprovedTxnOps(lines);
    assertCatalogMpTxnNoReadAfterWrite(ops);
    assert.deepEqual(ops, catalogMpApprovedTxnOpSequence(2));
  });

  it("marker processed existente: noop sem escritas de estoque", () => {
    const lines = parseCatalogOrderLineItemsForStock([{ id: "p1", quantidade: 1 }]);
    const ops = simulateCatalogApprovedTxnOps(lines, { processedExists: true });
    assert.deepEqual(ops, ["get_processed"]);
    assertCatalogMpTxnNoReadAfterWrite(ops);
  });

  it("pedido já pago concorrente: só marca processed, sem baixa estoque", () => {
    const lines = parseCatalogOrderLineItemsForStock([{ id: "p1", quantidade: 1 }]);
    const ops = simulateCatalogApprovedTxnOps(lines, { orderPaid: true });
    assert.deepEqual(ops, ["get_processed", "get_order", "set_processed"]);
    assertCatalogMpTxnNoReadAfterWrite(ops);
  });
});

describe("mpWebhook catálogo — baixa de estoque (helpers puros)", () => {
  it("parseCatalogOrderLineItemsForStock ignora qty inválida", () => {
    const lines = parseCatalogOrderLineItemsForStock([
      { id: "a", quantidade: 2 },
      { id: "b", quantidade: 0 },
      { slug: "c", qty: 1 },
    ]);
    assert.equal(lines.length, 2);
    assert.equal(lines[0].pId, "a");
    assert.equal(lines[1].pId, "c");
  });

  it("webhook aprovado deduz estoque simples uma vez", () => {
    const { updateProdutos, updateEstoque } = computeCatalogStockDeductionPayloads({
      qty: 2,
      tamanho: "",
      cor: "",
      temVariacao: false,
      data: { quantidade: 10, estoque: 10 },
      nowTs: NOW,
    });
    assert.equal(updateProdutos.quantidade, 8);
    assert.equal(updateEstoque.quantidade, 8);
  });

  it("retry do mesmo paymentId: processedExists evita segunda baixa", () => {
    const lines = parseCatalogOrderLineItemsForStock([{ id: "sku1", quantidade: 3 }]);
    const first = simulateCatalogApprovedTxnOps(lines);
    const retry = simulateCatalogApprovedTxnOps(lines, { processedExists: true });
    assert.ok(first.includes("set_estoque_0"));
    assert.ok(!retry.includes("set_estoque_0"));
  });

  it("pedido já pago retorna noop sem set_order nem estoque", () => {
    const lines = parseCatalogOrderLineItemsForStock([{ id: "x", quantidade: 1 }]);
    const ops = simulateCatalogApprovedTxnOps(lines, { orderPaid: true });
    assert.ok(!ops.includes("set_order"));
    assert.ok(!ops.some((o) => o.startsWith("set_estoque_")));
  });

  it("estoque insuficiente não gera valor negativo (transação atômica)", () => {
    const { updateProdutos } = computeCatalogStockDeductionPayloads({
      qty: 99,
      tamanho: "",
      cor: "",
      temVariacao: false,
      data: { quantidade: 2 },
      nowTs: NOW,
    });
    assert.equal(updateProdutos.quantidade, 0);
    assert.equal(updateProdutos.ativo, false);
  });

  it("variação tamanho/cor deduz corretamente", () => {
    const { updateProdutos } = computeCatalogStockDeductionPayloads({
      qty: 1,
      tamanho: "M",
      cor: "Prata",
      temVariacao: true,
      data: {
        variacoes: { M: { Prata: 5, Ouro: 2 } },
      },
      nowTs: NOW,
    });
    assert.equal(updateProdutos.variacoes.M.Prata, 4);
    assert.equal(updateProdutos.quantidade, 6);
  });
});

describe("mpWebhook catálogo — planWebhook intocado", () => {
  it("helpers exportados são só do catálogo mpWebhookHandler", () => {
    assert.equal(typeof parseCatalogOrderLineItemsForStock, "function");
    assert.equal(typeof computeCatalogStockDeductionPayloads, "function");
    assert.equal(typeof catalogMpApprovedTxnOpSequence, "function");
  });
});
