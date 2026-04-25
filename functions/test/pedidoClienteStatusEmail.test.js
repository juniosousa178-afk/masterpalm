import test from "node:test";
import assert from "node:assert/strict";
import {
  freteExigeRastreio,
  getMeaningfulChangedKeys,
  statusToTemplateKey,
  resolveEnviadoSendPlan,
  pickTipoEntregaEnvio,
  classificarEntregaEnvio,
  inferirCategoriaEntrega,
} from "../src/pedidoClienteStatusEmail.js";

test("freteExigeRastreio: retirada na loja não exige", () => {
  assert.equal(
    freteExigeRastreio({ frete: { tipo: "retirada", nome: "Retirar na loja" } }),
    false,
  );
});

test("freteExigeRastreio: combinar com vendedor não exige", () => {
  assert.equal(
    freteExigeRastreio({ frete: { tipo: "outro", nome: "Combinar com vendedor" } }),
    false,
  );
});

test("freteExigeRastreio: correios exige", () => {
  assert.equal(
    freteExigeRastreio({ frete: { tipo: "correios", nome: "PAC" } }),
    true,
  );
});

test("statusToTemplateKey: embalando → em_preparacao", () => {
  assert.equal(statusToTemplateKey("embalando"), "em_preparacao");
});

test("getMeaningfulChangedKeys ignora campos de controle de e-mail", () => {
  const a = { status: "enviado", x: 1 };
  const b = {
    status: "enviado",
    x: 1,
    emailsStatusEnviados: { recebido: true },
    dataAtualizacao: 99,
  };
  assert.deepEqual(getMeaningfulChangedKeys(a, b), []);
});

test("pickTipoEntregaEnvio: local e rastreio", () => {
  assert.equal(pickTipoEntregaEnvio({ tipoEntregaEnvio: "local" }), "local");
  assert.equal(pickTipoEntregaEnvio({ tipoEntregaEnvio: "rastreio" }), "rastreio");
});

test("resolveEnviadoSendPlan: local imediato", () => {
  const p = resolveEnviadoSendPlan({ tipoEntregaEnvio: "local" });
  assert.deepEqual(p, { action: "send", variant: "local" });
});

test("resolveEnviadoSendPlan: rastreio sem código adia", () => {
  const p = resolveEnviadoSendPlan({ tipoEntregaEnvio: "rastreio" });
  assert.equal(p.action, "defer");
});

test("resolveEnviadoSendPlan: rastreio com código envia", () => {
  const p = resolveEnviadoSendPlan({
    tipoEntregaEnvio: "rastreio",
    codigoRastreio: "BR123",
  });
  assert.deepEqual(p, { action: "send", variant: "rastreio", codigo: "BR123" });
});

test("resolveEnviadoSendPlan: retirada explícita (sem rua)", () => {
  const p = resolveEnviadoSendPlan({ tipoEntregaEnvio: "retirada" });
  assert.deepEqual(p, { action: "send", variant: "retirada" });
});

test("classificarEntregaEnvio: explícito retirada vence inferência", () => {
  assert.equal(
    classificarEntregaEnvio({
      tipoEntregaEnvio: "retirada",
      codigoRastreio: "XX1",
    }),
    "retirada_ou_combinar",
  );
});

test("inferir: motoboy → local", () => {
  assert.equal(
    inferirCategoriaEntrega({ frete: { nome: "Entrega local — motoboy" } }),
    "local",
  );
});

test("inferir: retirada na loja (sem código)", () => {
  assert.equal(
    inferirCategoriaEntrega({ frete: { tipo: "retirada", nome: "Loja" } }),
    "retirada_ou_combinar",
  );
});

test("inferir: código presente → transportadora", () => {
  assert.equal(
    inferirCategoriaEntrega({ codigoRastreio: "BR9", frete: { nome: "retirada" } }),
    "transportadora",
  );
});
