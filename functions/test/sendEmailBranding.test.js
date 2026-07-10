/**
 * EMAILBRAND — sendEmail resolve nome da loja server-side.
 * node --test functions/test/sendEmailBranding.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const indexSrc = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "..", "index.js"),
  "utf8",
);

describe("sendEmail branding", () => {
  it("EMAILBRAND-1: usa lojaId para resolver displayName", () => {
    assert.match(indexSrc, /body\.lojaId/);
    assert.match(indexSrc, /lojaData\.nome \|\| lojaData\.name/);
    assert.match(indexSrc, /from: `"?\$\{displayName\}"? <\$\{smtpUser\}>`/);
  });

  it("EMAILBRAND-2: fallback MasterPalm", () => {
    assert.match(indexSrc, /let displayName = "MasterPalm"/);
  });

  it("EMAILBRAND-3: não aceita fromName do cliente", () => {
    assert.doesNotMatch(indexSrc, /body\.fromName/);
    assert.doesNotMatch(indexSrc, /body\.displayName/);
  });
});
