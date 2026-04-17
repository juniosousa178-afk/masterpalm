/**
 * Diagnóstico read-only MP por loja (alinhado a mpLojaTokenPolicy).
 * node --test (Node 20+)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  classifyLojaMpPaymentsData,
  effectiveMpTokenFromPaymentsData,
  publicKeyShape,
} from "../src/mpLojaPaymentsDiagnostics.js";

const validAppUsr = `APP_USR-${"x".repeat(30)}`;

describe("effectiveMpTokenFromPaymentsData", () => {
  it("prioriza mp.access_token e espelha getLojaPaymentConfig", () => {
    assert.equal(
      effectiveMpTokenFromPaymentsData({
        mp: { access_token: "a", token: "b" },
      }),
      "a",
    );
  });

  it("cai em mp.token e legado mp_access_token", () => {
    assert.equal(
      effectiveMpTokenFromPaymentsData({ mp: { token: "t" } }),
      "t",
    );
    assert.equal(
      effectiveMpTokenFromPaymentsData({ mp_access_token: "leg" }),
      "leg",
    );
  });
});

describe("classifyLojaMpPaymentsData", () => {
  it("ok: token válido + identidade + pk_prefixed", () => {
    const r = classifyLojaMpPaymentsData({
      mp: {
        access_token: validAppUsr,
        connected: true,
        email: "a@b.com",
        user_id: "1",
        public_key: "pk_live_xxx",
      },
    });
    assert.equal(r.status, "ok_token_loja_valido");
    assert.equal(r.wouldFailMpLojaTokenRequired, false);
    assert.equal(r.tokenLen, validAppUsr.length);
  });

  it("missing_token", () => {
    const r = classifyLojaMpPaymentsData({ mp: { connected: false } });
    assert.equal(r.status, "missing_token");
    assert.equal(r.wouldFailMpLojaTokenRequired, true);
  });

  it("invalid_format", () => {
    const r = classifyLojaMpPaymentsData({
      mp: { access_token: "curto", connected: false },
    });
    assert.equal(r.status, "invalid_format");
    assert.equal(r.wouldFailMpLojaTokenRequired, true);
    assert.ok(r.tokenLen > 0);
  });

  it("connected_sem_token", () => {
    const r = classifyLojaMpPaymentsData({
      mp: { connected: true },
    });
    assert.equal(r.status, "connected_sem_token");
    assert.equal(r.wouldFailMpLojaTokenRequired, true);
  });

  it("token_presente_sem_identidade", () => {
    const r = classifyLojaMpPaymentsData({
      mp: {
        access_token: validAppUsr,
        connected: true,
      },
    });
    assert.equal(r.status, "token_presente_sem_identidade");
    assert.equal(r.wouldFailMpLojaTokenRequired, false);
  });

  it("saída de classify não inclui token bruto", () => {
    const r = classifyLojaMpPaymentsData({
      mp: { access_token: validAppUsr },
    });
    assert.equal(JSON.stringify(r).includes("APP_USR"), false);
    assert.equal(r.tokenLen > 0, true);
  });

  it("publicKeyShape", () => {
    assert.equal(publicKeyShape(null), "missing");
    assert.equal(publicKeyShape("pk_live_abc"), "pk_prefixed");
    assert.equal(publicKeyShape("APP_USR-x"), "looks_like_access_token");
  });

  it("estado_inconclusivo para entrada não-objeto", () => {
    const r = classifyLojaMpPaymentsData(null);
    assert.equal(r.status, "estado_inconclusivo");
    assert.equal(r.wouldFailMpLojaTokenRequired, true);
  });

  it("token_manual_sem_public_key_real quando pk parece access", () => {
    const r = classifyLojaMpPaymentsData({
      mp: {
        access_token: validAppUsr,
        connected: true,
        email: "x@y.com",
        public_key: "APP_USR-fake-as-pk",
      },
    });
    assert.equal(r.status, "token_manual_sem_public_key_real");
    assert.equal(r.wouldFailMpLojaTokenRequired, false);
  });
});
