/**
 * Diagnóstico submit login → Auth Emulator (R8.4.41)
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { LOJA_ID, QA_BUILD_DIR, QA_SERVE_PORT, USER_EMAIL, USER_PASSWORD } from '../lib/constants.mjs';
import { assertEmulatorPreflight } from '../lib/emulator-preflight.mjs';
import { attachProductionNetworkGuard } from '../lib/env-guard.mjs';
import {
  attachAuthEmulatorRequestCollector,
  attachConsoleCollector,
  collectVisibleLabels,
  fillLoginFields,
  hasQaLabel,
  submitLogin,
  waitForFlutterShell,
  waitForQaBootstrap,
  waitQaLabel,
  isLoginScreenReady,
} from '../lib/flutter-semantics.mjs';
import { serveStatic } from '../lib/serve-build.mjs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../..');
const outDir = path.join(path.resolve(__dirname, '..'), '.artifacts');

const LOGIN_TIMEOUT_MS = Number(process.env.LOGIN_TIMEOUT_MS || 180_000);

function maskEmail(email) {
  const [local, domain] = email.split('@');
  if (!domain) return '(invalid)';
  const head = local.slice(0, 2);
  return `${head}***@${domain}`;
}

async function probeButton(page) {
  const btn = page.getByRole('button', { name: /entrar/i });
  const count = await btn.count();
  if (!count) return { present: false };
  const el = btn.first();
  const enabled = await el.isEnabled().catch(() => null);
  const focused = await el.evaluate((n) => document.activeElement === n).catch(() => null);
  return {
    present: true,
    count,
    role: 'button',
    label: 'Entrar',
    enabled,
    focused,
  };
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';

  if (process.env.SKIP_EMULATOR_PREFLIGHT !== '1') await assertEmulatorPreflight();

  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();
  const violations = [];
  attachProductionNetworkGuard(page, violations);
  attachConsoleCollector(page);
  const authRequests = attachAuthEmulatorRequestCollector(page);

  const report = {
    url: null,
    bootstrapReady: false,
    loginEmailPresent: false,
    loginPasswordPresent: false,
    emailMasked: maskEmail(USER_EMAIL),
    passwordNonEmpty: Boolean(USER_PASSWORD),
    button: null,
    submit: null,
    markers: {},
    authEmulatorRequests: [],
    classification: null,
    console: [],
    violations: [],
  };

  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login?flutter-semantics`, {
    waitUntil: 'load',
    timeout: 120_000,
  });
  await waitForFlutterShell(page);
  await waitForQaBootstrap(page, { timeout: LOGIN_TIMEOUT_MS });

  report.url = page.url();
  const labels0 = await collectVisibleLabels(page);
  report.bootstrapReady = labels0.some((l) => l.startsWith('qa-bootstrap-ready'));
  report.loginEmailPresent =
    labels0.includes('login-email') || (await isLoginScreenReady(page));
  report.loginPasswordPresent = labels0.includes('login-password');

  await fillLoginFields(page, USER_EMAIL, USER_PASSWORD, { skipBootstrap: true });
  report.button = await probeButton(page);

  report.submit = await submitLogin(page);
  await page.waitForTimeout(3000);

  const labels = await collectVisibleLabels(page);
  const markerKeys = [
    'qa-login-submit-dispatched',
    'qa-login-validation-passed',
    'qa-auth-request-started',
    'qa-auth-request-succeeded',
    'qa-auth-request-failed',
    'qa-app-authenticated',
    'app-authenticated',
    'company-loaded',
    'navigation-ready',
    'home-ready',
    'qa-home-ready',
  ];
  for (const k of markerKeys) report.markers[k] = labels.includes(k);

  report.authEmulatorRequests = authRequests;
  report.console = page._qaConsoleErrors || [];
  report.violations = violations;
  report.elapsedMs = Date.now() - t0;
  report.lojaEsperada = LOJA_ID;

  if (!report.markers['qa-login-submit-dispatched']) {
    report.classification = 'FLUTTER_LOGIN_SUBMIT_ACTION_NOT_DISPATCHED';
  } else if (!report.authEmulatorRequests.length) {
    report.classification = 'AUTH_REQUEST_NOT_STARTED';
  } else if (!report.markers['qa-auth-request-succeeded']) {
    report.classification = 'FLUTTER_LOGIN_SUBMIT_DISPATCHED_AUTH_FAILED';
  } else if (report.markers['home-ready'] || report.markers['qa-home-ready']) {
    report.classification = 'WEB_BROWSER_UI_LOGIN_GREEN';
  } else {
    report.classification = 'HOME_ROUTER_STALLED';
  }

  if (report.authEmulatorRequests.length) {
    report.authEmulatorClassification = 'AUTH_EMULATOR_SIGN_IN_REQUEST_CONFIRMED';
  }

  const tracePath = path.join(outDir, `diagnose-login-submit-${Date.now()}.json`);
  fs.writeFileSync(tracePath, JSON.stringify(report, null, 2));
  await page.screenshot({
    path: path.join(outDir, `diagnose-login-submit-${Date.now()}.png`),
    fullPage: true,
  }).catch(() => {});

  console.log(report.classification);
  console.log('Relatório:', tracePath);

  await browser.close();
  server.close();
  const ok =
    report.classification === 'WEB_BROWSER_UI_LOGIN_GREEN' ||
    report.classification === 'FLUTTER_LOGIN_SUBMIT_DISPATCHED';
  process.exit(ok && report.markers['qa-login-submit-dispatched'] ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
