import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { HttpsError } from "firebase-functions/v2/https";

import {
  avaliarGiroRoleta,
  normalizePremiosRoleta,
  runGirarRoletaCatalogo,
} from "../src/roletaCatalogo.js";

describe("normalizePremiosRoleta", () => {
  it("normaliza desconto_percentual para desconto", () => {
    const premios = normalizePremiosRoleta([
      { label: "10% OFF", tipo: "desconto_percentual", valor: 10 },
    ]);

    assert.equal(premios[0].tipo, "desconto");
    assert.equal(premios[0].diasValidade, 30);
    assert.equal(premios[0].ativo, true);
  });
});

describe("avaliarGiroRoleta", () => {
  it("bloqueia quando totalCarrinho está abaixo do valor mínimo", () => {
    const resultado = avaliarGiroRoleta({
      config: {
        ativa: true,
        valorMinimo: 100,
        premios: [{ label: "Tente novamente", tipo: "nenhum", ativo: true }],
      },
      totalCarrinho: 50,
    });

    assert.equal(resultado.ok, false);
    assert.equal(resultado.status, "below_minimum");
  });

  it("premia quando a frequência é atingida e incrementa quantidade usada", () => {
    const resultado = avaliarGiroRoleta({
      config: {
        ativa: true,
        valorMinimo: 10,
        frequenciaPremio: 3,
        vendasDesdePremio: 2,
        totalVendas: 10,
        premios: [
          { label: "10% OFF", tipo: "desconto", valor: 10, ativo: true, quantidadeMaxima: 5, quantidadeUsada: 1 },
          { label: "Tente novamente", tipo: "nenhum", ativo: true },
        ],
      },
      totalCarrinho: 100,
    });

    assert.equal(resultado.ok, true);
    assert.equal(resultado.ganhou, true);
    assert.equal(resultado.premioIndex, 0);
    assert.equal(resultado.totalVendas, 11);
    assert.equal(resultado.vendasDesdePremio, 0);
    assert.equal(resultado.premios[0].quantidadeUsada, 2);
    assert.match(resultado.codigoCupomTemporario, /^[A-F0-9]{8}$/);
  });

  it("faz fallback seguro para 'nenhum' quando não há prêmio elegível", () => {
    const resultado = avaliarGiroRoleta({
      config: {
        ativa: true,
        valorMinimo: 0,
        frequenciaPremio: 1,
        vendasDesdePremio: 0,
        totalVendas: 4,
        premios: [
          { label: "Brinde esgotado", tipo: "brinde", ativo: true, quantidadeMaxima: 1, quantidadeUsada: 1 },
          { label: "Tente novamente", tipo: "nenhum", ativo: true },
        ],
      },
      totalCarrinho: 80,
    });

    assert.equal(resultado.ok, true);
    assert.equal(resultado.ganhou, false);
    assert.equal(resultado.premioIndex, 1);
    assert.equal(resultado.premio.tipo, "nenhum");
    assert.equal(resultado.vendasDesdePremio, 0);
  });
});

describe("runGirarRoletaCatalogo", () => {
  it("rejeita lojaId inválido", async () => {
    await assert.rejects(
      () => runGirarRoletaCatalogo({}, { lojaId: "..", totalCarrinho: 10 }),
      (err) => err instanceof HttpsError && err.code === "invalid-argument",
    );
  });
});
