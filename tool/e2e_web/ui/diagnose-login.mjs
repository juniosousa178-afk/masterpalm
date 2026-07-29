/**
 * Diagnóstico login → home (R8.4.39)
 * Captura URL, aria, console, Auth state antes de aumentar timeouts.
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
} from '../lib/flutter-semantics.mjs';
import { serveStatic } from '../lib/serve-build.mjs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../..');
const outDir = path.join(path.resolve(__dirname, '..'), '.artifacts');

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';

  await assertEmulatorPreflight();

  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();
  const violations = [];
  attachProductionNetworkGuard(page, violations);
  attachConsoleCollector(page);

  const report = { steps: [], console: [], networkErrors: [], violations: [] };
  page.on('requestfailed', (r) => report.networkErrors.push({ url: r.url(), err: r.failure()?.errorText }));
  page.on('response', (r) => {
    if (r.status() >= 400) report.networkErrors.push({ url: r.url(), status: r.status() });
  });

  const urlBefore = `http://127.0.0.1:${QA_SERVE_PORT}/login`;
  await page.goto(urlBefore, { waitUntil: 'load', timeout: 120_000 });
  await waitForFlutterShell(page);
  report.steps.push({ phase: 'before_login', url: page.url(), labels: await collectVisibleLabels(page) });

  await fillLoginFields(page, USER_EMAIL, USER_PASSWORD);
  await submitLogin(page);

  for (const sec of [3, 8, 15, 30, 60]) {
    await page.waitForTimeout(sec * 1000);
    report.steps.push({
      phase: `t+${sec}s`,
      url: page.url(),
      labels: await collectVisibleLabels(page),
    });
    if (await page.getByLabel('home-ready', { exact: true }).count()) break;
  }

  // Auth emulator lookup
  try {
    const authRes = await fetch(
      `http://127.0.0.1:9199/identitytoolkit.googleapis.com/v1/accounts:lookup?key=fake-api-key`,
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
  report.classification = report.steps.some((s) => s.labels.includes('home-ready'))
    ? 'LOGIN_HOME_TIMEOUT_CAUSE_IDENTIFIED: home-ready alcançado após submit'
  : 'LOGIN_HOME_TIMEOUT_CAUSE_IDENTIFIED: home-ready ausente — verificar router/plano/store context';

  const outFile = path.join(outDir, `diagnose-login-${Date.now()}.json`);
  fs.writeFileSync(outFile, JSON.stringify(report, null, 2));
  console.log(report.classification);
  console.log('Relatório:', outFile);

  await browser.close();
  server.close();
  process.exit(report.classification.includes('home-ready alcançado') ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
