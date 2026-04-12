/**
 * Máscaras de auditoria (sem emulator).
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  maskEmailForAudit,
  maskUidForAudit,
} from "../src/planSupportRead.js";

describe("maskEmailForAudit", () => {
  it("mascara local e mantém domínio", () => {
    assert.equal(maskEmailForAudit("joao@exemplo.com"), "j***@exemplo.com");
  });

  it("null para inválido", () => {
    assert.equal(maskEmailForAudit(""), null);
    assert.equal(maskEmailForAudit("nope"), null);
  });
});

describe("maskUidForAudit", () => {
  it("encurta UID longo", () => {
    const u = "abcdefghijklmnopqrstuvwxyz12";
    const m = maskUidForAudit(u);
    assert.ok(m.includes("…"));
    assert.ok(m.startsWith("abcdef"));
  });
});
