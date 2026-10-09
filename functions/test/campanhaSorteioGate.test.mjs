/**
 * P0 Nathy — gate de campanha no servidor (mpWebhookPromo / gerarCupomNumeroSorte).
 */
import test from "node:test";
import assert from "node:assert/strict";
import { avaliarCampanhas, campanhaElegivel } from "../src/campanhaSorteioGate.js";

const LOJA = "loja-a";
const agora = new Date("2026-10-09T12:00:00Z");
const dia = 24 * 3600 * 1000;

function camp(over = {}) {
  return {
    ativa: true,
    status: "aberta",
    dataInicio: new Date(agora.getTime() - dia),
    dataFim: new Date(agora.getTime() + dia),
    ...over,
  };
}

const avaliar = (list) =>
  avaliarCampanhas(list.map((data, i) => ({ id: `c${i}`, data })), { lojaId: LOJA, agora });

test("sem campanha → nenhuma", () => {
  assert.equal(avaliar([]).status, "nenhuma");
});

test("uma válida → ativa", () => {
  const r = avaliar([camp()]);
  assert.equal(r.status, "ativa");
  assert.equal(r.campanha.id, "c0");
});

test("status encerrado com ativa=true → nenhuma", () => {
  for (const status of ["sorteada", "finalizada", "pausada", "cancelada", "encerrada"]) {
    assert.equal(avaliar([camp({ status })]).status, "nenhuma", status);
  }
});

test("ativa=false → nenhuma", () => {
  assert.equal(avaliar([camp({ ativa: false })]).status, "nenhuma");
});

test("expirada, futura e sem datas → nenhuma", () => {
  assert.equal(avaliar([camp({ dataFim: new Date(agora.getTime() - 1) })]).status, "nenhuma");
  assert.equal(avaliar([camp({ dataInicio: new Date(agora.getTime() + 1) })]).status, "nenhuma");
  assert.equal(avaliar([camp({ dataInicio: null, dataFim: null })]).status, "nenhuma");
});

test("excluída ou de outra loja → nenhuma", () => {
  assert.equal(avaliar([camp({ excluida: true })]).status, "nenhuma");
  assert.equal(avaliar([camp({ lojaId: "loja-b" })]).status, "nenhuma");
  assert.equal(campanhaElegivel(camp({ lojaId: LOJA }), { lojaId: LOJA, agora }), true);
});

test("duas válidas → ambígua (sem sorteio)", () => {
  assert.equal(avaliar([camp(), camp()]).status, "ambigua");
});

test("Timestamp-like (toDate) aceito", () => {
  const ts = (d) => ({ toDate: () => d });
  const r = avaliar([
    camp({ dataInicio: ts(new Date(agora.getTime() - dia)), dataFim: ts(new Date(agora.getTime() + dia)) }),
  ]);
  assert.equal(r.status, "ativa");
});
