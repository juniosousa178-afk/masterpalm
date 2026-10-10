import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as adminNs from "firebase-admin";
import { getAuth } from "firebase-admin/auth";

const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");

function block(start, end) {
  const i = src.indexOf(start);
  const j = src.indexOf(end, i + start.length);
  assert.ok(i >= 0 && j > i, `block not found: ${start}`);
  return src.slice(i, j);
}

test("firebase-admin ESM namespace import has no auth(); modular getAuth is the supported API", () => {
  assert.equal(typeof adminNs.auth, "undefined");
  assert.equal(typeof getAuth, "function");
  assert.ok(src.includes('import { getAuth } from "firebase-admin/auth";'));
});

test("sendEmail verifies ID tokens through getAuth()", () => {
  const b = block("export const sendEmail = onRequest(", "export const getClienteCatalog");
  assert.ok(b.includes("verifyIdToken: (token) => getAuth().verifyIdToken(token)"));
  assert.doesNotMatch(b, /admin\s*\.\s*auth\s*\(/);
});

test("enviarEmailVerificacao generates the link through getAuth()", () => {
  const b = block("export const enviarEmailVerificacao = onCall(", "[enviarEmailVerificacao] error:");
  assert.ok(b.includes("getAuth().generateEmailVerificationLink(emailNorm)"));
  assert.doesNotMatch(b, /admin\s*\.?\s*auth\s*\(/);
});
