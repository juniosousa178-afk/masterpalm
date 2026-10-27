import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { findLoaders, hash16, runGate } from "../../tools/security/check_functions_deploy_env.mjs";

const loaders = findLoaders({ extraDirs: [join(import.meta.dirname, "..")] });
const skip = loaders.length ? false : "firebase-tools não instalado (functions/node_modules ou FIREBASE_TOOLS_DIR)";
const PROJECT = "demo-gate";
const key = () => `APP_USR-${randomUUID()}`;

function repo(files, { rc } = {}) {
  const root = mkdtempSync(join(tmpdir(), "deploy-env-gate-"));
  const fn = join(root, "functions");
  mkdirSync(fn);
  for (const [name, body] of Object.entries(files)) writeFileSync(join(fn, name), body);
  if (rc) writeFileSync(join(root, ".firebaserc"), JSON.stringify({ projects: rc }));
  const git = (...a) => execFileSync("git", ["-c", "user.email=gate@example.test", "-c", "user.name=gate", ...a], { cwd: root, stdio: "ignore" });
  git("init", "-q");
  git("add", "-A");
  git("commit", "-q", "-m", "fixture");
  return { root, fn, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}
const gate = (fn, root, expected, extra = {}) =>
  runGate({ functionsDir: fn, projectId: PROJECT, firebasercDirs: [root], loaders, expectedHashes: { [PROJECT]: hash16(expected) }, releaseDir: undefined, ...extra });

test("release-line: .env rastreado com a chave esperada passa e informa a origem", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\nOTHER=1\n` });
  try {
    const out = gate(r.fn, r.root, k);
    assert.equal(out.ok, true, out.fail.join(";"));
    assert.equal(out.info.mode, "release-line");
    for (const v of Object.values(out.info.resolved)) assert.deepEqual(v, { hash: hash16(k), origin: ".env" });
    assert.ok(!JSON.stringify(out).includes(k), "valor nunca aparece no resultado");
  } finally { r.cleanup(); }
});

test("hash diferente aborta (chave pré-rotação no repo)", { skip }, () => {
  const old = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${old}\n` });
  try {
    const out = gate(r.fn, r.root, key());
    assert.equal(out.ok, false);
    assert.match(out.fail.join(";"), new RegExp(`HASH_MISMATCH:${hash16(old)}`));
  } finally { r.cleanup(); }
});

test("variável ausente aborta", { skip }, () => {
  const r = repo({ ".env": "OTHER=1\n" });
  try {
    const out = gate(r.fn, r.root, key());
    assert.equal(out.ok, false);
    assert.match(out.fail.join(";"), /MISSING/);
  } finally { r.cleanup(); }
});

test("override por .env.<projectId> é o que vale e é checado", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\n`, [`.env.${PROJECT}`]: `MP_PUBLIC_KEY=${key()}\n` });
  try {
    const out = gate(r.fn, r.root, k);
    assert.equal(out.ok, false);
    assert.match(out.fail.join(";"), /HASH_MISMATCH/);
  } finally { r.cleanup(); }
});

test("alias do .firebaserc com .env.<alias> divergente aborta", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\n`, ".env.prod": `MP_PUBLIC_KEY=${key()}\n` }, { rc: { default: PROJECT, prod: PROJECT } });
  try {
    const out = gate(r.fn, r.root, k);
    assert.equal(out.ok, false);
    assert.deepEqual(out.info.aliases, ["default", "prod"]);
    assert.match(out.fail.join(";"), /alias:prod:HASH_MISMATCH/);
    assert.doesNotMatch(out.fail.join(";"), /alias:default/);
  } finally { r.cleanup(); }
});

test("origem indeterminada: .env alterado localmente ou não rastreado aborta", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\n` });
  try {
    writeFileSync(join(r.fn, ".env"), `MP_PUBLIC_KEY=${k}\nX=1\n`);
    assert.match(gate(r.fn, r.root, k).fail.join(";"), /\.env:MODIFIED/);
    execFileSync("git", ["checkout", "--", "functions/.env"], { cwd: r.root, stdio: "ignore" });
    writeFileSync(join(r.fn, `.env.${PROJECT}`), `MP_PUBLIC_KEY=${k}\n`);
    assert.match(gate(r.fn, r.root, k).fail.join(";"), new RegExp(`\\.env\\.${PROJECT}:UNTRACKED`));
  } finally { r.cleanup(); }
});

test("pacote live fora do Git: sem MP_RELEASE_ENV_DIR o .env do pacote não é autoridade", { skip }, () => {
  const k = key();
  const pkg = mkdtempSync(join(tmpdir(), "deploy-env-pkg-"));
  try {
    writeFileSync(join(pkg, ".env"), `MP_PUBLIC_KEY=${k}\n`);
    const out = gate(pkg, pkg, k);
    assert.equal(out.ok, false);
    assert.equal(out.info.mode, "package");
    assert.match(out.fail.join(";"), /PACKAGE_ENV_NOT_TRUSTED/);
  } finally { rmSync(pkg, { recursive: true, force: true }); }
});

test("pacote live com chave antiga: .env* substituídos pelos da release antes de validar", { skip }, () => {
  const canonical = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${canonical}\nOTHER=release\n` });
  const pkg = mkdtempSync(join(tmpdir(), "deploy-env-pkg-"));
  try {
    writeFileSync(join(pkg, ".env"), `MP_PUBLIC_KEY=${key()}\nOTHER=old\n`);
    writeFileSync(join(pkg, `.env.${PROJECT}`), `MP_PUBLIC_KEY=${key()}\n`);
    const out = gate(pkg, pkg, canonical, { releaseDir: r.fn });
    assert.equal(out.ok, true, out.fail.join(";"));
    assert.deepEqual(out.info.synced, [".env:COPIED", `.env.${PROJECT}:REMOVED`]);
    assert.equal(readFileSync(join(pkg, ".env"), "utf8"), readFileSync(join(r.fn, ".env"), "utf8"));
    assert.equal(existsSync(join(pkg, `.env.${PROJECT}`)), false);
  } finally { rmSync(pkg, { recursive: true, force: true }); r.cleanup(); }
});

test("release dir com .env alterado não serve de autoridade", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\n` });
  const pkg = mkdtempSync(join(tmpdir(), "deploy-env-pkg-"));
  try {
    cpSync(join(r.fn, ".env"), join(pkg, ".env"));
    writeFileSync(join(r.fn, ".env"), `MP_PUBLIC_KEY=${key()}\n`);
    const out = gate(pkg, pkg, k, { releaseDir: r.fn });
    assert.equal(out.ok, false);
    assert.match(out.fail.join(";"), /release:\.env:MODIFIED/);
  } finally { rmSync(pkg, { recursive: true, force: true }); r.cleanup(); }
});

test("sem loader do firebase-tools ou projeto sem hash esperado: aborta", { skip }, () => {
  const k = key();
  const r = repo({ ".env": `MP_PUBLIC_KEY=${k}\n` });
  try {
    assert.deepEqual(gate(r.fn, r.root, k, { loaders: [] }).fail, ["FIREBASE_TOOLS_LOADER_NOT_FOUND"]);
    const other = runGate({ functionsDir: r.fn, projectId: "other-project", firebasercDirs: [r.root], loaders });
    assert.deepEqual(other.fail, ["NO_EXPECTED_HASH_FOR_PROJECT:other-project"]);
  } finally { r.cleanup(); }
});
