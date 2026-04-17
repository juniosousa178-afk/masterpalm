/**
 * Política de token MP da loja (sem fallback global em fluxos pedido/catálogo).
 * node --test (Node 20+)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  isAcceptableLojaMpAccessToken,
  resolveStrictLojaMpAccessToken,
} from "../src/mpLojaTokenPolicy.js";

describe("isAcceptableLojaMpAccessToken", () => {
  it("aceita APP_USR- com comprimento mínimo", () => {
    const t = `APP_USR-${"x".repeat(20)}`;
    assert.equal(t.length >= 24, true);
    assert.equal(isAcceptableLojaMpAccessToken(t), true);
  });

  it("rejeita APP_USR- muito curto (critério antigo length>10 era frouxo)", () => {
    assert.equal(isAcceptableLojaMpAccessToken("APP_USR-abc"), false);
  });

  it("rejeita string genérica curta", () => {
    assert.equal(isAcceptableLojaMpAccessToken("not-a-real-mp-token"), false);
  });

  it("aceita token longo sem prefixo (legado raro)", () => {
    const long = "x".repeat(48);
    assert.equal(isAcceptableLojaMpAccessToken(long), true);
  });
});

describe("resolveStrictLojaMpAccessToken", () => {
  it("exige token da loja — missing", () => {
    const r = resolveStrictLojaMpAccessToken({ token: "" });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "missing");
    assert.equal(r.tokenLen, 0);
  });

  it("exige token da loja — invalid_format", () => {
    const r = resolveStrictLojaMpAccessToken({ token: "short" });
    assert.equal(r.ok, false);
    assert.equal(r.reason, "invalid_format");
  });

  it("retorna token normalizado quando válido", () => {
    const raw = `  APP_USR-${"y".repeat(30)}  `;
    const r = resolveStrictLojaMpAccessToken({ token: raw });
    assert.equal(r.ok, true);
    assert.equal(r.token, raw.trim());
  });

  it("não expõe fallback global (apenas estrutura ok/token)", () => {
    const r = resolveStrictLojaMpAccessToken({
      token: `APP_USR-${"z".repeat(40)}`,
    });
    assert.equal(r.ok, true);
    assert.equal("fallback" in r, false);
  });
});
