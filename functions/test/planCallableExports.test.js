/**
 * Contrato de export Release A — sem carregar firebase admin/index.js.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const indexSrc = readFileSync(join(root, "index.js"), "utf8");

function exportedConsts(src) {
  const out = [];
  const re = /^export const (\w+)/gm;
  let m;
  while ((m = re.exec(src))) out.push(m[1]);
  return out;
}

describe("createPlanChangeSubscription export", () => {
  it("está exportado e resolve para runCreatePlanChangeSubscription", () => {
    const names = exportedConsts(indexSrc);
    assert.ok(names.includes("createPlanChangeSubscription"));
    assert.ok(names.includes("createPlanSubscription"));
    assert.ok(names.includes("planCreatePreferenceCall"));
    assert.ok(names.includes("planCreatePreference"));
    assert.equal(names.filter((n) => n === "createPlanChangeSubscription").length, 1);
    assert.match(
      indexSrc,
      /export const createPlanChangeSubscription = onCall/,
    );
    assert.match(indexSrc, /runCreatePlanChangeSubscription\(/);
    assert.match(
      indexSrc,
      /from "\.\/src\/mpPlanChange\.js"/,
    );
  });

  it("não remove exports billing existentes", () => {
    const names = exportedConsts(indexSrc);
    for (const n of [
      "planCreatePreference",
      "planCreatePreferenceCall",
      "planWebhook",
      "createPlanSubscription",
      "cancelPlanSubscription",
      "reactivatePlanSubscription",
      "syncPlanSubscription",
    ]) {
      assert.ok(names.includes(n), `missing ${n}`);
    }
    assert.match(indexSrc, /applyLegacyNonApprovedBillingWrite/);
    assert.equal(
      indexSrc.includes('status: checkoutStatus === "pending" ? "pending" : "inactive"'),
      false,
    );
  });
});
