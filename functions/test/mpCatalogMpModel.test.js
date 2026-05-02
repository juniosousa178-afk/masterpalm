/**
 * Modelo MP catálogo (Fase 0)
 * node --test functions/test/mpCatalogMpModel.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  assertCatalogMpPaymentAllowed,
  inferMpConnectionKind,
  MP_CONN_MANUAL,
  MP_CONN_OAUTH,
} from "../src/mpCatalogMpModel.js";

describe("inferMpConnectionKind", () => {
  it("honra mp_connection_kind explícito", () => {
    assert.equal(inferMpConnectionKind({ mp: { mp_connection_kind: "oauth" } }), MP_CONN_OAUTH);
    assert.equal(inferMpConnectionKind({ mp: { mp_connection_kind: "manual" } }), MP_CONN_MANUAL);
  });

  it("refresh_token sem kind explícito => oauth", () => {
    assert.equal(inferMpConnectionKind({ mp: { refresh_token: "rt" } }), MP_CONN_OAUTH);
  });

  it("sem refresh => manual", () => {
    assert.equal(inferMpConnectionKind({ mp: { access_token: "x" } }), MP_CONN_MANUAL);
  });
});

describe("assertCatalogMpPaymentAllowed", () => {
  it("oauth com refresh ok", () => {
    const r = assertCatalogMpPaymentAllowed(
      { mp: { refresh_token: "abc", access_token: "t" } },
      {},
    );
    assert.equal(r.ok, true);
    assert.equal(r.catalogKind, "catalog_oauth_payment");
  });

  it("oauth com catalog_token_validated ok (kind explícito)", () => {
    const r = assertCatalogMpPaymentAllowed(
      {
        mp: {
          mp_connection_kind: "oauth",
          catalog_token_validated: true,
          access_token: "t",
        },
      },
      {},
    );
    assert.equal(r.ok, true);
  });

  it("manual exige webhook_secret e validação", () => {
    const r = assertCatalogMpPaymentAllowed(
      { mp: { access_token: "t", mp_connection_kind: "manual", catalog_token_validated: true } },
      {},
    );
    assert.equal(r.ok, false);
    assert.equal(r.code, "CATALOG_MP_WEBHOOK_SECRET_REQUIRED");
  });

  it("manual completo ok", () => {
    const r = assertCatalogMpPaymentAllowed(
      {
        mp: {
          access_token: "t",
          mp_connection_kind: "manual",
          webhook_secret: "1234567890123456",
          catalog_token_validated: true,
        },
      },
      {},
    );
    assert.equal(r.ok, true);
    assert.equal(r.catalogKind, "catalog_manual_token_payment");
  });

  it("CATALOG_MP_MODE=oauth_only rejeita manual", () => {
    const r = assertCatalogMpPaymentAllowed(
      {
        mp: {
          mp_connection_kind: "manual",
          webhook_secret: "1234567890123456",
          catalog_token_validated: true,
        },
      },
      { CATALOG_MP_MODE: "oauth_only" },
    );
    assert.equal(r.ok, false);
    assert.equal(r.code, "CATALOG_MP_OAUTH_ONLY");
  });
});
