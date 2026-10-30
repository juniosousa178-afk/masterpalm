import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SKIP_DIRS = new Set(["node_modules", ".git", "test"]);

function sourceFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return SKIP_DIRS.has(name) ? [] : sourceFiles(p);
    return /\.(c|m)?js$/.test(name) ? [p] : [];
  });
}

function codeLines(path) {
  return readFileSync(path, "utf8")
    .split(/\r?\n/)
    .map((line, i) => ({ n: i + 1, line }))
    .filter(({ line }) => !/^\s*(\/\/|\*|\/\*)/.test(line));
}

const legacyAccess = /\bfunctions\s*\.\s*config\s*\(|CLOUD_RUNTIME_CONFIG|\.runtimeconfig\.json/;

test("todos os codebases de Functions recusam o Runtime Config legado no deploy", () => {
  const cfg = JSON.parse(readFileSync(join(repoRoot, "firebase.json"), "utf8"));
  const codebases = Array.isArray(cfg.functions) ? cfg.functions : [cfg.functions];
  assert.ok(codebases.length > 0);
  for (const cb of codebases) {
    assert.equal(cb.disallowLegacyRuntimeConfig, true, `codebase ${cb.codebase ?? cb.source}`);
  }
});

test("nenhum código de Functions lê functions.config() nem o Runtime Config legado", () => {
  const offenders = [];
  for (const source of ["functions", "main"]) {
    for (const file of sourceFiles(join(repoRoot, source))) {
      for (const { n, line } of codeLines(file)) {
        if (legacyAccess.test(line)) offenders.push(`${relative(repoRoot, file)}:${n}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});

test("credenciais SMTP dos módulos legados vêm do Secret Manager", () => {
  const pos = readFileSync(join(repoRoot, "functions/src/posPagamento.js"), "utf8");
  assert.match(pos, /defineSecret\("SMTP_EMAIL"\)/);
  assert.match(pos, /defineSecret\("SMTP_PASSWORD"\)/);
  assert.match(pos, /secrets: \[S_SMTP_EMAIL, S_SMTP_PASSWORD\]/);

  const cupom = readFileSync(join(repoRoot, "functions/gerarCupomNumeroSorte.js"), "utf8");
  assert.match(cupom, /defineSecret\('SMTP_EMAIL'\)/);
  assert.match(cupom, /defineSecret\('SMTP_PASSWORD'\)/);
  assert.match(cupom, /runWith\(\{ secrets: \[SMTP_EMAIL, SMTP_PASSWORD\] \}\)/);
  assert.doesNotMatch(cupom, /EMAIL_USER|EMAIL_PASS/);
});
