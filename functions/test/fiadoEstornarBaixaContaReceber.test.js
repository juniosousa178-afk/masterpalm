/**
 * 040B3 — testes locais do backend confiável de estorno (sem deploy, sem produção).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  applyEstornoBaixaToReceivable,
  canAccessLojaFinanceiroServerSide,
  executeEstornarBaixaContaReceber,
  handleEstornarBaixaContaReceber,
  parseTrustedRefundInput,
  TrustedRefundError,
} from "../src/fiadoEstornarBaixaContaReceber.js";

function createMemoryDb(seed = {}) {
  const docs = new Map(Object.entries(seed));
  let txLock = Promise.resolve();

  function refFromPath(path) {
    return {
      path,
      async get() {
        const data = docs.get(path);
        return {
          exists: data !== undefined,
          data: () => (data !== undefined ? { ...data } : undefined),
        };
      },
      async set(data, opts) {
        const prev = docs.get(path) || {};
        docs.set(path, opts?.merge ? { ...prev, ...data } : { ...data });
      },
    };
  }

  function collection(name, prefix = "") {
    return {
      doc(id) {
        const path = prefix ? `${prefix}/${name}/${id}` : `${name}/${id}`;
        return {
          ...refFromPath(path),
          collection(sub) {
            return collection(sub, path);
          },
        };
      },
    };
  }

  return {
    docs,
    collection: (name) => collection(name),
    async runTransaction(fn) {
      const run = txLock.then(async () => {
        const pending = [];
        const tx = {
          async get(ref) {
            return ref.get();
          },
          set(ref, data, opts) {
            pending.push(() => ref.set(data, opts));
          },
        };
        const result = await fn(tx);
        for (const apply of pending) {
          await apply();
        }
        return result;
      });
      txLock = run.catch(() => {});
      return run;
    },
  };
}

function paidReceivable({ lojaId = "loja-a", baixaId = "bx-1", valor = 100 } = {}) {
  return {
    lojaId,
    vendaIdFirebase: "venda-1",
    valorOriginal: valor,
    valorPago: valor,
    saldoAtual: 0,
    valor: 0,
    status: "paga",
    pago: true,
    historicoPagamentos: [
      { baixaId, valor, estornada: false, forma: "Pix" },
    ],
  };
}

describe("parseTrustedRefundInput", () => {
  it("aceita só o contrato mínimo e ignora estado financeiro do cliente", () => {
    const input = parseTrustedRefundInput({
      lojaId: "loja-a",
      contaReceberId: "cr_venda-1_p1",
      baixaId: "bx-1",
      saldo: 999,
      pago: false,
      valor: 50,
      status: "pendente",
      lastWriteOrigin: "estorno_baixa",
    });
    assert.deepEqual(input, {
      lojaId: "loja-a",
      contaReceberId: "cr_venda-1_p1",
      baixaId: "bx-1",
    });
  });

  it("rejeita input incompleto", () => {
    assert.throws(
      () => parseTrustedRefundInput({ lojaId: "loja-a" }),
      (e) => e instanceof TrustedRefundError && e.code === "invalid-argument",
    );
  });
});

describe("applyEstornoBaixaToReceivable", () => {
  it("reabre saldo da baixa e é idempotente na mesma baixaId", () => {
    const paid = paidReceivable();
    const first = applyEstornoBaixaToReceivable(paid, "bx-1", { nowIso: "2026-09-05T00:00:00.000Z" });
    assert.equal(first.kind, "applied");
    assert.equal(first.data.pago, false);
    assert.equal(first.data.status, "pendente");
    assert.equal(first.data.saldoAtual, 100);
    assert.equal(first.data.valorPago, 0);
    assert.equal(first.data.historicoPagamentos[0].estornada, true);

    const second = applyEstornoBaixaToReceivable(first.data, "bx-1");
    assert.equal(second.kind, "idempotent");
    assert.equal(second.data.saldoAtual, 100);
  });

  it("não inventa estorno se a baixa não existe", () => {
    const paid = paidReceivable();
    const r = applyEstornoBaixaToReceivable(paid, "bx-inexistente");
    assert.equal(r.kind, "baixa_missing");
  });
});

describe("canAccessLojaFinanceiroServerSide", () => {
  it("owner da loja tem acesso; loja cruzada não", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-b": { ownerUid: "uid-b" },
    });
    const okA = await canAccessLojaFinanceiroServerSide({
      db,
      lojaId: "loja-a",
      uid: "uid-a",
      email: "a@x.com",
    });
    const okB = await canAccessLojaFinanceiroServerSide({
      db,
      lojaId: "loja-b",
      uid: "uid-a",
      email: "a@x.com",
    });
    assert.equal(okA, true);
    assert.equal(okB, false);
  });
});

describe("handleEstornarBaixaContaReceber", () => {
  it("happy path autorizado", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-a/contas_receber/cr_venda-1_p1": paidReceivable(),
    });
    const result = await handleEstornarBaixaContaReceber({
      db,
      auth: { uid: "uid-a", token: { email: "a@x.com" } },
      data: { lojaId: "loja-a", contaReceberId: "cr_venda-1_p1", baixaId: "bx-1" },
    });
    assert.equal(result.ok, true);
    assert.equal(result.idempotent, false);
    assert.equal(result.pago, false);
    assert.equal(result.saldoAtual, 100);
    const stored = db.docs.get("lojas/loja-a/contas_receber/cr_venda-1_p1");
    assert.equal(stored.pago, false);
    assert.equal(stored.lastWriteOrigin, "trusted_refund_fn");
    assert.equal(db.docs.has("lojas/loja-a/lancamentos_financeiros"), false);
  });

  it("unauthenticated DENY", async () => {
    const db = createMemoryDb();
    await assert.rejects(
      () =>
        handleEstornarBaixaContaReceber({
          db,
          auth: null,
          data: { lojaId: "loja-a", contaReceberId: "cr_1", baixaId: "bx-1" },
        }),
      (e) => e instanceof TrustedRefundError && e.code === "unauthenticated",
    );
  });

  it("cross-store DENY", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-b": { ownerUid: "uid-b" },
      "lojas/loja-b/contas_receber/cr_venda-1_p1": paidReceivable({ lojaId: "loja-b" }),
    });
    await assert.rejects(
      () =>
        handleEstornarBaixaContaReceber({
          db,
          auth: { uid: "uid-a", token: { email: "a@x.com" } },
          data: { lojaId: "loja-b", contaReceberId: "cr_venda-1_p1", baixaId: "bx-1" },
        }),
      (e) => e instanceof TrustedRefundError && e.code === "permission-denied",
    );
    const stored = db.docs.get("lojas/loja-b/contas_receber/cr_venda-1_p1");
    assert.equal(stored.pago, true);
  });

  it("CR inexistente fail-closed", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
    });
    await assert.rejects(
      () =>
        handleEstornarBaixaContaReceber({
          db,
          auth: { uid: "uid-a", token: { email: "a@x.com" } },
          data: { lojaId: "loja-a", contaReceberId: "cr_missing", baixaId: "bx-1" },
        }),
      (e) => e instanceof TrustedRefundError && e.code === "not-found",
    );
  });

  it("dupla requisição não multiplica saldo", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-a/contas_receber/cr_venda-1_p1": paidReceivable(),
    });
    const payload = {
      db,
      auth: { uid: "uid-a", token: { email: "a@x.com" } },
      data: { lojaId: "loja-a", contaReceberId: "cr_venda-1_p1", baixaId: "bx-1" },
    };
    const a = await handleEstornarBaixaContaReceber(payload);
    const b = await handleEstornarBaixaContaReceber(payload);
    assert.equal(a.ok, true);
    assert.equal(b.ok, true);
    assert.equal(b.idempotent, true);
    const stored = db.docs.get("lojas/loja-a/contas_receber/cr_venda-1_p1");
    assert.equal(stored.saldoAtual, 100);
    assert.equal(stored.valorPago, 0);
  });

  it("concorrente termina consistente e sem saldo duplicado", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-a/contas_receber/cr_venda-1_p1": paidReceivable(),
    });
    const payload = {
      db,
      auth: { uid: "uid-a", token: { email: "a@x.com" } },
      data: { lojaId: "loja-a", contaReceberId: "cr_venda-1_p1", baixaId: "bx-1" },
    };
    const [a, b] = await Promise.all([
      handleEstornarBaixaContaReceber(payload),
      handleEstornarBaixaContaReceber(payload),
    ]);
    assert.equal(a.ok && b.ok, true);
    const stored = db.docs.get("lojas/loja-a/contas_receber/cr_venda-1_p1");
    assert.equal(stored.saldoAtual, 100);
    assert.equal(stored.valorPago, 0);
    assert.equal(stored.historicoPagamentos[0].estornada, true);
  });

  it("não confia em estado financeiro enviado pelo cliente", async () => {
    const db = createMemoryDb({
      "lojas/loja-a": { ownerUid: "uid-a" },
      "lojas/loja-a/contas_receber/cr_venda-1_p1": paidReceivable({ valor: 80 }),
    });
    const result = await handleEstornarBaixaContaReceber({
      db,
      auth: { uid: "uid-a", token: { email: "a@x.com" } },
      data: {
        lojaId: "loja-a",
        contaReceberId: "cr_venda-1_p1",
        baixaId: "bx-1",
        saldo: 1,
        pago: false,
        valor: 1,
        status: "pendente",
      },
    });
    assert.equal(result.saldoAtual, 80);
  });
});

describe("executeEstornarBaixaContaReceber isolation", () => {
  it("doc.lojaId divergente do path é bloqueado", async () => {
    const db = createMemoryDb({
      "lojas/loja-a/contas_receber/cr_x_p1": paidReceivable({ lojaId: "loja-b" }),
    });
    await assert.rejects(
      () =>
        executeEstornarBaixaContaReceber({
          db,
          lojaId: "loja-a",
          contaReceberId: "cr_x_p1",
          baixaId: "bx-1",
        }),
      (e) => e instanceof TrustedRefundError && e.code === "permission-denied",
    );
  });
});
