#!/usr/bin/env node
/**
 * Gate de segredos em arquivos rastreados pelo Git. Falha (exit 1) se encontrar:
 *  - exports do Firebase Auth (nome de arquivo ou estrutura localId + passwordHash/salt);
 *  - parâmetros de hash de senha do Firebase (signer key, salt separator);
 *  - chaves privadas, service accounts e tokens com formato conhecido;
 *  - senha literal em código que cria/atualiza/autentica usuários (fora de testes).
 * Só imprime caminho, linha e classificação; nunca o valor encontrado.
 *
 * Uso: node tools/security/check_tracked_secrets.mjs [repoRoot]
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_TEXT_BYTES = 8 * 1024 * 1024;
const BINARY_EXT = /\.(apk|aab|ipa|jar|so|dex|zip|7z|gz|tgz|rar|png|jpe?g|gif|webp|ico|bmp|ttf|otf|woff2?|pdf|mp3|mp4|mov|keystore|jks|p12|class|wasm)$/i;
const TEST_PATH = /(^|\/)(test|tests|__tests__|integration_test|e2e|goldens?)\/|_test\.dart$|\.test\.(c|m)?[jt]s$|\.spec\.(c|m)?[jt]s$/i;
const CODE_EXT = /\.(c|m)?[jt]s$|\.dart$|\.py$|\.ps1$|\.sh$/i;

const AUTH_EXPORT_NAME = /(^|\/)(users?_export[^/]*|[^/]*auth[_-]?(export|users)[^/]*)\.json$/i;
const B64 = '[A-Za-z0-9+/_-]{12,}={0,2}';
// Corpo mínimo de uma chave privada real (RSA 2048 ~1600 caracteres); fixtures sintéticas curtas não contam.
const KEY_BODY = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----(?:\\\\n|\\s)*[A-Za-z0-9+/=\\s\\\\n]{400,}-----END';

const CONTENT_RULES = [
  { id: 'AUTH_EXPORT_STRUCTURE', test: (t) => /"localId"\s*:/.test(t) && new RegExp(`"(passwordHash|passwordSalt|salt)"\\s*:\\s*"${B64}"`).test(t), line: /"(passwordHash|passwordSalt|salt)"\s*:/ },
  { id: 'AUTH_HASH_PARAMETERS', test: (t) => /\b(base64_signer_key|base64_salt_separator)\b\s*["']?\s*[:=]\s*["']?[A-Za-z0-9+/]{8,}/i.test(t) || /\b(signerKey|saltSeparator)["']?\s*[:=]\s*["'][A-Za-z0-9+/]{16,}={0,2}["']/.test(t), line: /signer|separator/i },
  { id: 'SERVICE_ACCOUNT_KEY', test: (t) => /"type"\s*:\s*"service_account"/.test(t) && new RegExp(`"private_key"\\s*:\\s*"${KEY_BODY}`).test(t), line: /"private_key"\s*:/ },
  { id: 'PRIVATE_KEY_BLOCK', test: (t) => new RegExp(KEY_BODY).test(t), line: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
  { id: 'MERCADO_PAGO_ACCESS_TOKEN', test: (t) => /\b(?:APP_USR|TEST)-\d{10,20}-\d{6}-[0-9a-f]{32}-\d{6,12}\b/.test(t), line: /\b(?:APP_USR|TEST)-\d{10,20}-\d{6}-[0-9a-f]{32}/ },
  { id: 'GITHUB_TOKEN', test: (t) => /\bgh[pousr]_[A-Za-z0-9]{36,}\b/.test(t), line: /\bgh[pousr]_[A-Za-z0-9]{36,}/ },
  { id: 'AWS_ACCESS_KEY', test: (t) => /\bAKIA[0-9A-Z]{16}\b/.test(t), line: /\bAKIA[0-9A-Z]{16}\b/ },
  { id: 'SLACK_TOKEN', test: (t) => /\bxox[baprs]-[A-Za-z0-9-]{10,}/.test(t), line: /\bxox[baprs]-/ },
  { id: 'STRIPE_LIVE_SECRET', test: (t) => /\bsk_live_[A-Za-z0-9]{20,}/.test(t), line: /\bsk_live_/ },
];

const AUTH_CALL = /\b(createUser|updateUser|signInWithEmailAndPassword|createUserWithEmailAndPassword|importUsers)\s*\(/;
const PASSWORD_LITERAL = /\b(senha|password|passwd|pwd)\w*["']?\s*[:=]\s*(["'`])([^"'`\s$]{6,})\2/gi;

function lineOf(text, re) {
  const lines = text.split(/\r?\n/);
  const i = lines.findIndex((l) => re.test(l));
  return i >= 0 ? i + 1 : null;
}

/** Caminho proibido independentemente do conteúdo. */
export function isForbiddenPath(relPath) {
  return AUTH_EXPORT_NAME.test(relPath.replace(/\\/g, '/'));
}

/** Achados num arquivo de texto: [{ path, line, classification }]. Nunca inclui o valor. */
export function scanText(relPath, text) {
  const path = relPath.replace(/\\/g, '/');
  const findings = [];
  if (isForbiddenPath(path)) findings.push({ path, line: null, classification: 'AUTH_EXPORT_FILENAME' });
  for (const rule of CONTENT_RULES) {
    if (rule.test(text)) findings.push({ path, line: lineOf(text, rule.line), classification: rule.id });
  }
  if (CODE_EXT.test(path) && !TEST_PATH.test(path) && AUTH_CALL.test(text)) {
    for (const m of text.matchAll(PASSWORD_LITERAL)) {
      const line = text.slice(0, m.index).split(/\r?\n/).length;
      findings.push({ path, line, classification: 'HARDCODED_AUTH_PASSWORD' });
    }
  }
  return findings;
}

/** Varre todos os arquivos rastreados de um repositório Git. */
export function scanRepo(repoRoot) {
  const out = execFileSync('git', ['ls-files', '-z'], { cwd: repoRoot, maxBuffer: 256 * 1024 * 1024 });
  const files = out.toString('utf8').split('\0').filter(Boolean);
  const findings = [];
  for (const rel of files) {
    if (isForbiddenPath(rel)) {
      findings.push({ path: rel, line: null, classification: 'AUTH_EXPORT_FILENAME' });
      continue;
    }
    if (BINARY_EXT.test(rel)) continue;
    const full = join(repoRoot, rel);
    let st;
    try { st = statSync(full); } catch { continue; }
    if (!st.isFile() || st.size > MAX_TEXT_BYTES) continue;
    const buf = readFileSync(full);
    if (buf.subarray(0, 8192).includes(0)) continue;
    findings.push(...scanText(rel, buf.toString('utf8')));
  }
  return findings;
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const root = resolve(process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..', '..'));
  const findings = scanRepo(root);
  if (findings.length === 0) {
    console.log('TRACKED_SECRETS_GATE PASS (0 findings)');
    process.exit(0);
  }
  console.log(`TRACKED_SECRETS_GATE FAIL (${findings.length} finding(s))`);
  for (const f of findings) console.log(`  ${f.path}${f.line ? `:${f.line}` : ''} [${f.classification}]`);
  process.exit(1);
}
