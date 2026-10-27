#!/usr/bin/env node
/**
 * Gate de predeploy das Functions (codebase default): resolve MP_PUBLIC_KEY com o próprio loader de dotenv
 * do firebase-tools e aborta (exit 2) se o hash não for o canônico do projeto, se a variável faltar ou se a
 * origem dos arquivos .env não puder ser determinada. Nunca imprime valores, só sha256 truncado.
 *
 * Origem confiável: functions/.env* rastreados no Git e sem alteração local (linha de release).
 * Pacote fora do Git (ex.: source baixado de uma revisão live): os .env* do pacote nunca são autoridade.
 * Com MP_RELEASE_ENV_DIR=<functions da linha de release>, os .env* do pacote são substituídos pelos da
 * release antes do empacotamento; sem essa variável, o deploy é abortado.
 *
 * Uso (predeploy do firebase.json): node "$PROJECT_DIR/tools/security/check_functions_deploy_env.mjs" "$RESOURCE_DIR"
 * Manual: GCLOUD_PROJECT=<id> node tools/security/check_functions_deploy_env.mjs functions
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, readFileSync, unlinkSync } from 'node:fs';
import { createRequire } from 'node:module';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const KEY = 'MP_PUBLIC_KEY';
/** Rotacionar a public key exige atualizar este hash junto com functions/.env. */
export const EXPECTED_HASHES = { 'masterpalm-58c46': '8392c58741d8e3a4' };

const require = createRequire(import.meta.url);
export const hash16 = (v) => createHash('sha256').update(String(v)).digest('hex').slice(0, 16);

/** Instalações do firebase-tools: a que o PATH resolve primeiro (a que roda o deploy) vem antes das locais. */
export function findLoaders({ pathEnv = process.env.PATH || '', extraDirs = [], explicit = process.env.FIREBASE_TOOLS_DIR } = {}) {
  const roots = [];
  if (explicit) roots.push(explicit);
  for (const d of pathEnv.split(delimiter).filter(Boolean)) {
    if (!['firebase', 'firebase.cmd'].some((b) => existsSync(join(d, b)))) continue;
    roots.push(join(d, '..', 'firebase-tools'), join(d, 'node_modules', 'firebase-tools'), join(d, '..', 'lib', 'node_modules', 'firebase-tools'));
  }
  for (const d of extraDirs) roots.push(join(d, 'node_modules', 'firebase-tools'));
  const seen = new Set();
  const loaders = [];
  for (const r of roots.map((x) => resolve(x))) {
    const envJs = join(r, 'lib', 'functions', 'env.js');
    if (seen.has(envJs) || !existsSync(envJs)) continue;
    seen.add(envJs);
    let version = 'unknown';
    try { version = JSON.parse(readFileSync(join(r, 'package.json'), 'utf8')).version; } catch { /* sem versão */ }
    loaders.push({ name: `firebase-tools@${version}`, path: envJs, env: require(envJs) });
  }
  return loaders;
}

/** Aliases do .firebaserc que apontam para o projeto (cada um pode carregar .env.<alias> no deploy). */
export function aliasesFor(projectId, firebasercDirs) {
  const out = new Set();
  for (const d of firebasercDirs) {
    const p = join(d, '.firebaserc');
    if (!existsSync(p)) continue;
    const projects = JSON.parse(readFileSync(p, 'utf8')).projects || {};
    for (const [alias, id] of Object.entries(projects)) if (id === projectId && alias !== projectId) out.add(alias);
  }
  return [...out].sort();
}

export const envFileNames = (projectId, aliases) => ['.env', `.env.${projectId}`, ...aliases.map((a) => `.env.${a}`)];

const git = (cwd, args) => execFileSync('git', args, { cwd, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' });

/** .env* existentes rastreados e sem alteração em relação ao HEAD; null se o diretório não está num work tree. */
export function gitTrust(functionsDir, names) {
  try {
    if (git(functionsDir, ['rev-parse', '--is-inside-work-tree']).trim() !== 'true') return null;
  } catch {
    return null;
  }
  const present = names.filter((n) => existsSync(join(functionsDir, n)));
  const problems = [];
  for (const n of present) {
    try { git(functionsDir, ['ls-files', '--error-unmatch', n]); } catch { problems.push(`${n}:UNTRACKED`); continue; }
    try { git(functionsDir, ['diff', '--quiet', 'HEAD', '--', n]); } catch { problems.push(`${n}:MODIFIED`); }
  }
  return { present, problems };
}

/** Substitui os .env* do pacote pelos da release (e remove os que a release não tem). */
export function syncReleaseEnv(packageDir, releaseDir, names) {
  const actions = [];
  for (const n of names) {
    const src = join(releaseDir, n);
    const dst = join(packageDir, n);
    if (existsSync(src)) { copyFileSync(src, dst); actions.push(`${n}:COPIED`); }
    else if (existsSync(dst)) { unlinkSync(dst); actions.push(`${n}:REMOVED`); }
  }
  return actions;
}

/** Resolve a variável com um loader e acha o último arquivo carregado que a define. */
export function resolveWith(loader, functionsDir, projectId, alias) {
  const envs = loader.env.loadUserEnvs({ functionsSource: functionsDir, projectDir: functionsDir, projectId, projectAlias: alias });
  if (!Object.prototype.hasOwnProperty.call(envs, KEY)) return { hash: null, origin: null };
  let origin = null;
  for (const n of envFileNames(projectId, alias ? [alias] : [])) {
    const p = join(functionsDir, n);
    if (existsSync(p) && Object.prototype.hasOwnProperty.call(loader.env.parse(readFileSync(p, 'utf8')).envs, KEY)) origin = n;
  }
  return { hash: hash16(envs[KEY]), origin };
}

export function runGate({ functionsDir, projectId, firebasercDirs = [], releaseDir = process.env.MP_RELEASE_ENV_DIR, loaders, expectedHashes = EXPECTED_HASHES }) {
  const fail = [];
  const info = { functionsDir, projectId };
  const expected = expectedHashes[projectId];
  if (!expected) return { ok: false, fail: [`NO_EXPECTED_HASH_FOR_PROJECT:${projectId}`], info };
  const aliases = aliasesFor(projectId, [...firebasercDirs, ...(releaseDir ? [dirname(resolve(releaseDir))] : [])]);
  const names = envFileNames(projectId, aliases);
  info.aliases = aliases;

  const trust = gitTrust(functionsDir, names);
  if (trust) {
    info.mode = 'release-line';
    fail.push(...trust.problems);
  } else {
    info.mode = 'package';
    if (!releaseDir) {
      fail.push('PACKAGE_ENV_NOT_TRUSTED:set MP_RELEASE_ENV_DIR to the release-line functions dir');
    } else {
      const rt = gitTrust(resolve(releaseDir), names);
      if (!rt) fail.push('RELEASE_ENV_DIR_NOT_IN_GIT');
      else if (rt.problems.length) fail.push(...rt.problems.map((p) => `release:${p}`));
      else info.synced = syncReleaseEnv(functionsDir, resolve(releaseDir), names);
    }
  }
  if (fail.length) return { ok: false, fail, info };

  if (!loaders.length) return { ok: false, fail: ['FIREBASE_TOOLS_LOADER_NOT_FOUND'], info };
  info.loaders = loaders.map((l) => l.name);
  info.resolved = {};
  for (const l of loaders) {
    for (const alias of [undefined, ...aliases]) {
      const label = `${l.name}${alias ? `/alias:${alias}` : ''}`;
      try {
        const r = resolveWith(l, functionsDir, projectId, alias);
        info.resolved[label] = r;
        if (!r.hash) fail.push(`${label}:MISSING`);
        else if (r.hash !== expected) fail.push(`${label}:HASH_MISMATCH:${r.hash}`);
        else if (!r.origin) fail.push(`${label}:ORIGIN_UNKNOWN`);
      } catch (e) {
        fail.push(`${label}:LOADER_ERROR:${String(e?.message || e).slice(0, 120)}`);
      }
    }
  }
  info.expected = expected;
  return { ok: fail.length === 0, fail, info };
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const functionsDir = resolve(process.argv[2] || process.env.RESOURCE_DIR || join(repoRoot, 'functions'));
  const projectId = process.env.GCLOUD_PROJECT || '';
  const projectDir = process.env.PROJECT_DIR ? resolve(process.env.PROJECT_DIR) : repoRoot;
  const loaders = findLoaders({ extraDirs: [functionsDir, projectDir] });
  const r = runGate({ functionsDir, projectId, firebasercDirs: [projectDir], loaders });
  const head = r.ok ? `FUNCTION_DEPLOY_ENV_GATE PASS RESOLVED_${KEY}_HASH=${r.info.expected}` : 'FUNCTION_DEPLOY_ENV_GATE FAIL — deploy abortado';
  console.log(head);
  console.log(`  project=${projectId || '(none)'} mode=${r.info.mode || '-'} aliases=${(r.info.aliases || []).join(',') || '-'} loaders=${(r.info.loaders || []).join(',') || '-'}`);
  if (r.info.synced) console.log(`  synced=${r.info.synced.join(',')}`);
  for (const [k, v] of Object.entries(r.info.resolved || {})) console.log(`  ${k} hash=${v.hash} origin=${v.origin}`);
  for (const f of r.fail) console.log(`  FAIL ${f}`);
  // 2, não 1: no Windows o cross-spawn do predeploy reporta exit 1 de comando de shell como ENOENT.
  process.exit(r.ok ? 0 : 2);
}
