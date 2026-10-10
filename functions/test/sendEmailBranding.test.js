/**
 * EMAILBRAND — sendEmail resolve nome da loja server-side.
 * node --test functions/test/sendEmailBranding.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const contractSrc = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "..", "src", "emailContracts.js"),
  "utf8",
);

describe("sendEmail branding", () => {
  it("EMAILBRAND-1: usa lojaId para resolver displayName", () => {
    assert.match(contractSrc, /storeDisplayName\(db, colLojas, lojaId\)/);
    assert.match(contractSrc, /d\.nome \|\| d\.name/);
    assert.match(contractSrc, /from: `"\$\{plan\.send\.lojaNome\}" <\$\{smtpUser\}>`/);
  });

  it("EMAILBRAND-2: fallback MasterPalm", () => {
    assert.match(contractSrc, /return "MasterPalm";/);
  });

  it("EMAILBRAND-3: não aceita fromName do cliente", () => {
    assert.doesNotMatch(contractSrc, /body\.fromName/);
    assert.doesNotMatch(contractSrc, /body\.displayName/);
  });
});
