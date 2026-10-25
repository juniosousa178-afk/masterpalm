import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { isForbiddenPath, scanRepo, scanText } from "../../tools/security/check_tracked_secrets.mjs";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const b64 = (n) => crypto.randomBytes(n).toString("base64");
const classes = (findings) => findings.map((f) => f.classification).sort();

test("nome de export do Firebase Auth é proibido em qualquer pasta", () => {
  for (const p of ["users_export.json", "backup/users_export_2026.json", "firebase-auth-export.json", "tools/auth_users.json"]) {
    assert.equal(isForbiddenPath(p), true, p);
  }
  for (const p of ["lib/services/auth_service.dart", "functions/src/exportUsersCsv.js", "test/auth_users_test.dart"]) {
    assert.equal(isForbiddenPath(p), false, p);
  }
});

test("estrutura de export (localId + passwordHash/salt) é detectada com qualquer nome", () => {
  const hash = b64(64);
  const doc = JSON.stringify({ users: [{ localId: b64(21), email: "pessoa@example.test", passwordHash: hash, salt: b64(12) }] }, null, 1);
  const findings = scanText("docs/backup.json", doc);
  assert.deepEqual(classes(findings), ["AUTH_EXPORT_STRUCTURE"]);
  assert.ok(!JSON.stringify(findings).includes(hash));
});

test("parâmetros de hash do Firebase são detectados", () => {
  const text = `hash_config {\n  algorithm: SCRYPT,\n  base64_signer_key: ${b64(64)},\n  base64_salt_separator: ${b64(2)},\n  rounds: 8,\n  mem_cost: 14,\n}`;
  assert.deepEqual(classes(scanText("notes.md", text)), ["AUTH_HASH_PARAMETERS"]);
});

test("senha literal em script que cria usuário é detectada fora de testes", () => {
  const literal = b64(15).replace(/[^A-Za-z0-9]/g, "x");
  const script = `const EMAIL = process.env.E;\nconst SENHA = "${literal}";\nawait auth.createUser({ email: EMAIL, password: SENHA });\n`;
  const findings = scanText("functions/scripts/criar_conta.js", script);
  assert.deepEqual(classes(findings), ["HARDCODED_AUTH_PASSWORD"]);
  assert.equal(findings[0].line, 2);
  assert.ok(!JSON.stringify(findings).includes(literal));
  assert.deepEqual(scanText("functions/test/criar_conta.test.js", script), []);
});

test("script de conta de revisão lê a senha de fora do repositório", () => {
  const src = readFileSync(join(repoRoot, "functions", "scripts", "criar_usuario_teste.js"), "utf8");
  assert.deepEqual(scanText("functions/scripts/criar_usuario_teste.js", src), []);
  assert.match(src, /REVIEW_ACCOUNT_PASSWORD_FILE/);
  assert.doesNotMatch(src, /console\.log\([^)]*SENHA/);
});

test("tokens com formato conhecido são detectados", () => {
  const mp = `APP_USR-${"1".repeat(16)}-${"2".repeat(6)}-${crypto.randomBytes(16).toString("hex")}-${"3".repeat(9)}`;
  assert.deepEqual(classes(scanText("functions/.env", `MP_ACCESS_TOKEN=${mp}\n`)), ["MERCADO_PAGO_ACCESS_TOKEN"]);
  const sa = JSON.stringify({ type: "service_account", private_key: `-----BEGIN PRIVATE KEY-----\n${b64(1200)}\n-----END PRIVATE KEY-----\n` });
  assert.ok(classes(scanText("sa.json", sa)).includes("SERVICE_ACCOUNT_KEY"));
});

test("fixture curta de chave privada não é tratada como chave real", () => {
  const sa = JSON.stringify({ type: "service_account", private_key: "-----BEGIN PRIVATE KEY-----\nMIIfake\n-----END PRIVATE KEY-----\n" });
  assert.deepEqual(scanText("tools/qa_bot/fixture.json", sa), []);
});

test("nenhum arquivo rastreado do repositório tem export de Auth ou credencial", () => {
  const findings = scanRepo(repoRoot);
  assert.deepEqual(findings.map((f) => `${f.path} [${f.classification}]`), []);
});
