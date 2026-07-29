/**
 * Diagnóstico login → home (R8.4.40)
 * Captura URL, aria, estágios QA bootstrap, console, Auth state.
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { LOJA_ID, QA_BUILD_DIR, QA_SERVE_PORT, USER_EMAIL, USER_PASSWORD } from '../lib/constants.mjs';
import { assertEmulatorPreflight } from '../lib/emulator-preflight.mjs';
import { attachProductionNetworkGuard } from '../lib/env-guard.mjs';
import {
  attachConsoleCollector,
  collectVisibleLabels,
  fillLoginFields,
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

async function captureStage(page) {
  const labels = await collectVisibleLabels(page);
  const stage = labels.find((l) => l.startsWith('qa-bootstrap-stage-')) || null;
  const qaStage = labels.find((l) => l.startsWith('qa-bootstrap-') && !l.includes('stage')) || null;
  return { labels, stage, qaStage, url: page.url(), title: await page.title() };
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';

  const skipPreflight = process.env.SKIP_EMULATOR_PREFLIGHT === '1';
  if (!skipPreflight) await assertEmulatorPreflight();

  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();
  const violations = [];
  attachProductionNetworkGuard(page, violations);
  attachConsoleCollector(page);

  const report = {
    steps: [],
    console: [],
    networkErrors: [],
    violations: [],
    loginTimeoutMs: LOGIN_TIMEOUT_MS,
  };
  page.on('requestfailed', (r) =>
    report.networkErrors.push({ url: r.url(), err: r.failure()?.errorText }),
  );
  page.on('response', (r) => {
    if (r.status() >= 400) report.networkErrors.push({ url: r.url(), status: r.status() });
  });

  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login`, {
    waitUntil: 'load',
    timeout: 120_000,
  });
  await waitForFlutterShell(page);
  report.steps.push({ phase: 'shell', ms: Date.now() - t0, ...(await captureStage(page)) });

  try {
    await waitForQaBootstrap(page, { timeout: LOGIN_TIMEOUT_MS });
    report.steps.push({ phase: 'bootstrap-ready', ms: Date.now() - t0, ...(await captureStage(page)) });
    if (!(await isLoginScreenReady(page))) {
      await waitQaLabel(page, 'login-email', { timeout: 30_000 }).catch(() => {});
    }
    report.steps.push({ phase: 'login-visible', ms: Date.now() - t0, ...(await captureStage(page)) });
  } catch (e) {
    report.bootstrapError = String(e);
    report.steps.push({ phase: 'bootstrap-timeout', ms: Date.now() - t0, ...(await captureStage(page)) });
  }

  try {
    await fillLoginFields(page, USER_EMAIL, USER_PASSWORD, { skipBootstrap: true });
    await submitLogin(page);
    report.steps.push({ phase: 'after-submit', ms: Date.now() - t0, ...(await captureStage(page)) });
  } catch (e) {
    report.loginFillError = String(e);
  }

  for (const sec of [3, 8, 15, 30, 60, 90, 120]) {
    if (Date.now() - t0 > LOGIN_TIMEOUT_MS) break;
    await page.waitForTimeout(Math.min(sec * 1000, LOGIN_TIMEOUT_MS));
    const snap = await captureStage(page);
    report.steps.push({ phase: `t+${sec}s`, ms: Date.now() - t0, ...snap });
    if (snap.labels.includes('home-ready')) break;
  }

  try {
    const authRes = await fetch(
      'http://127.0.0.1:9199/identitytoolkit.googleapis.com/v1/accounts:lookup?key=fake-api-key',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: [USER_EMAIL] }),
      },
    );
    report.authEmulator = await authRes.json();
  } catch (e) {
    report.authEmulator = { error: String(e) };
  }

  report.console = page._qaConsoleErrors || [];
  report.violations = violations;
  report.lojaEsperada = LOJA_ID;
  const homeOk = report.steps.some((s) => s.labels?.includes('home-ready'));
  report.classification = homeOk
    ? 'WEB_BROWSER_UI_LOGIN_GREEN: home-ready alcançado'
    : report.bootstrapError
      ? `WEB_QA_BOOTSTRAP_FAILS_CLOSED: ${report.bootstrapError}`
      : 'LOGIN_HOME_TIMEOUT: home-ready ausente — verificar router/plano/store context';

  const tracePath = path.join(outDir, `diagnose-login-${Date.now()}.json`);
  fs.writeFileSync(tracePath, JSON.stringify(report, null, 2));
  const shotPath = path.join(outDir, `diagnose-login-${Date.now()}.png`);
  await page.screenshot({ path: shotPath, fullPage: true }).catch(() => {});

  console.log(report.classification);
  console.log('Relatório:', tracePath);

  await browser.close();
  server.close();
  process.exit(homeOk ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
