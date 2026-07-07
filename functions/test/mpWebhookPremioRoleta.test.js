/**
 * CUPMP-1…10 — ativação idempotente de premioRoleta/cupom pós-MP.
 * node --test functions/test/mpWebhookPremioRoleta.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  PREMIO_ROLETA_PROCESSED_COL,
  ativarPremioRoletaPosPagamentoMp,
  buildCupomPerfilPayload,
  parsePremioRoletaForActivation,
  shouldSkipCupomRegression,
} from "../src/mpWebhookPremioRoleta.js";

function pathKey(parts) {
  return parts.join("/");
}

function createLojaMockDb(initial = {}) {
  const store = new Map(Object.entries(initial));
  const locks = new Set();

  function docRef(parts) {
    const key = pathKey(parts);
    return {
      async get() {
        const data = store.get(key);
        return { exists: data != null, data: () => (data == null ? undefined : { ...data }) };
      },
      async set(data, opts = {}) {
        const prev = store.get(key) || {};
        store.set(key, opts.merge ? { ...prev, ...data } : { ...data });
      },
      async create(data) {
        if (store.has(key) || locks.has(key)) {
          const err = new Error("already exists");
          err.code = 6;
          throw err;
        }
        locks.add(key);
        store.set(key, { ...data });
      },
      async delete() {
        store.delete(key);
        locks.delete(key);
      },
      collection(name) {
        return collectionRef([...parts, name]);
      },
    };
  }

  function collectionRef(parts) {
    return {
      doc(id) {
        return docRef([...parts, id]);
      },
    };
  }

  return {
    store,
    collection(name) {
      return collectionRef([name]);
    },
  };
}

const baseOrder = () => ({
  cliente: { email: "cliente@test.com", nome: "Cliente" },
  premioRoleta: {
    codigo: "CUPOM10",
    tipo: "desconto",
    valor: 10,
    descricao: "10% OFF",
    status: "pendente",
    valido: false,
  },
});

describe("parsePremioRoletaForActivation", () => {
  it("CUPMP-6 sem premioRoleta → skip", () => {
    const r = parsePremioRoletaForActivation({});
    assert.equal(r.action, "skip");
    assert.equal(r.reason, "no_premio");
  });

  it("CUPMP-7 código ausente → skip", () => {
    const r = parsePremioRoletaForActivation({
      cliente: { email: "a@b.com" },
      premioRoleta: { tipo: "desconto", status: "pendente" },
    });
    assert.equal(r.action, "skip");
    assert.equal(r.reason, "sem_codigo");
  });

  it("CUPMP-5 email ausente → skip sem quebrar fluxo", () => {
    const r = parsePremioRoletaForActivation({
      cliente: {},
      premioRoleta: { tipo: "desconto", codigo: "X", status: "pendente" },
    });
    assert.equal(r.action, "skip");
    assert.equal(r.reason, "sem_email");
  });
});

describe("shouldSkipCupomRegression", () => {
  it("CUPMP-4 cupom usado não regride", () => {
    assert.equal(shouldSkipCupomRegression({ usado: true }), true);
    assert.equal(shouldSkipCupomRegression({ usado: false, ativo: true }), false);
  });
});

describe("ativarPremioRoletaPosPagamentoMp", () => {
  it("CUPMP-1 ativa cupom pendente no perfil e no pedido", async () => {
    const db = createLojaMockDb();
    const orderRef = db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp1");

    const r = await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp1",
      paymentId: "pay-1",
      orderData: baseOrder(),
      orderRef,
    });

    assert.equal(r.ok, true);
    assert.equal(r.skipped, false);

    const cupomKey = "lojas/loja1/clientes_catalogo/cliente@test.com/cupons/CUPOM10";
    const cupom = db.store.get(cupomKey);
    assert.equal(cupom.ativo, true);
    assert.equal(cupom.usado, false);
    assert.equal(cupom.codigo, "CUPOM10");

    const pedido = db.store.get("lojas/loja1/pre_pedidos/pp1");
    assert.equal(pedido["premioRoleta.status"], "ativo");
    assert.equal(pedido["premioRoleta.valido"], true);
  });

  it("CUPMP-2 retry mesmo paymentId não duplica cupom", async () => {
    const db = createLojaMockDb();
    const orderRef = db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp1");
    const args = {
      lojaId: "loja1",
      orderId: "pp1",
      paymentId: "pay-dup",
      orderData: baseOrder(),
      orderRef,
    };

    const r1 = await ativarPremioRoletaPosPagamentoMp(db, args);
    const r2 = await ativarPremioRoletaPosPagamentoMp(db, args);
    assert.equal(r1.ok, true);
    assert.equal(r2.ok, true);
    assert.equal(r2.skipped, true);

    const cupomKey = "lojas/loja1/clientes_catalogo/cliente@test.com/cupons/CUPOM10";
    assert.ok(db.store.has(cupomKey));
  });

  it("CUPMP-3 cupom já ativo permanece (merge idempotente)", async () => {
    const cupomKey = "lojas/loja1/clientes_catalogo/cliente@test.com/cupons/CUPOM10";
    const db = createLojaMockDb({
      [cupomKey]: { codigo: "CUPOM10", ativo: true, usado: false },
    });
    const orderRef = db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp1");

    const r = await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp1",
      paymentId: "pay-3",
      orderData: baseOrder(),
      orderRef,
    });
    assert.equal(r.ok, true);
    assert.equal(db.store.get(cupomKey).ativo, true);
  });

  it("CUPMP-4 cupom usado não é reativado", async () => {
    const cupomKey = "lojas/loja1/clientes_catalogo/cliente@test.com/cupons/CUPOM10";
    const db = createLojaMockDb({
      [cupomKey]: { codigo: "CUPOM10", ativo: false, usado: true },
    });
    const orderRef = db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp1");

    const r = await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp1",
      paymentId: "pay-4",
      orderData: baseOrder(),
      orderRef,
    });
    assert.equal(r.skipped, true);
    assert.equal(r.reason, "cupom_usado");
    assert.equal(db.store.get(cupomKey).usado, true);
  });

  it("CUPMP-8 pedidos diferentes → cupons independentes", async () => {
    const db = createLojaMockDb();
    const orderA = {
      ...baseOrder(),
      premioRoleta: { ...baseOrder().premioRoleta, codigo: "A1" },
    };
    const orderB = {
      ...baseOrder(),
      premioRoleta: { ...baseOrder().premioRoleta, codigo: "B2" },
    };

    await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp-a",
      paymentId: "pay-a",
      orderData: orderA,
      orderRef: db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp-a"),
    });
    await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp-b",
      paymentId: "pay-b",
      orderData: orderB,
      orderRef: db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp-b"),
    });

    assert.ok(db.store.has("lojas/loja1/clientes_catalogo/cliente@test.com/cupons/A1"));
    assert.ok(db.store.has("lojas/loja1/clientes_catalogo/cliente@test.com/cupons/B2"));
  });

  it("CUPMP-10 lock por paymentId criado", async () => {
    const db = createLojaMockDb();
    const orderRef = db.collection("lojas").doc("loja1").collection("pre_pedidos").doc("pp1");
    await ativarPremioRoletaPosPagamentoMp(db, {
      lojaId: "loja1",
      orderId: "pp1",
      paymentId: "pay-10",
      orderData: baseOrder(),
      orderRef,
    });
    const lockKey = `${PREMIO_ROLETA_PROCESSED_COL}/pay-10`;
    assert.ok(db.store.has(lockKey));
    assert.equal(db.store.get(lockKey).status, "done");
  });
});

describe("buildCupomPerfilPayload", () => {
  it("payload alinhado ao perfil catálogo", () => {
    const p = buildCupomPerfilPayload({
      premio: { valor: 15, descricao: "15% OFF" },
      codigo: "ABC",
      tipo: "desconto",
    });
    assert.equal(p.codigo, "ABC");
    assert.equal(p.ativo, true);
    assert.equal(p.origem, "roleta_sorte");
    assert.equal(p.usado, false);
  });
});

describe("contrato estrutural mpWebhookHandler", () => {
  it("processMpWebhook chama ativarPremioRoletaPosPagamentoMp", () => {
    const dir = dirname(fileURLToPath(import.meta.url));
    const src = readFileSync(join(dir, "../src/mpWebhookHandler.js"), "utf8");
    assert.match(src, /ativarPremioRoletaPosPagamentoMp/);
    assert.match(src, /ativarPremioRoletaPosPagamentoMpRecovery/);
  });
});
