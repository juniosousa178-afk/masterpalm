/**
 * Login 3× consecutivo — estabilidade R8.4.40 (sem cenários longos).
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { LOJA_ID, QA_BUILD_DIR, QA_SERVE_PORT, USER_EMAIL, USER_PASSWORD } from '../lib/constants.mjs';
import { assertEmulatorPreflight } from '../lib/emulator-preflight.mjs';
import {
  attachProductionNetworkGuard,
  getProductionRequestCount,
} from '../lib/env-guard.mjs';
import {
  attachConsoleCollector,
  fillLoginFields,
  resetAccessibilityState,
  submitLogin,
  waitForQaBootstrap,
  waitQaLabel,
} from '../lib/flutter-semantics.mjs';
import { serveStatic } from '../lib/serve-build.mjs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../..');

const LOGIN_TIMEOUT_MS = Number(process.env.LOGIN_TIMEOUT_MS || 180_000);
const RUNS = Number(process.env.LOGIN_STABILITY_RUNS || 3);

async function runLoginOnce(page, runIndex) {
  resetAccessibilityState();
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login?flutter-semantics`, {
    waitUntil: 'load',
    timeout: 120_000,
  });
  await waitForQaBootstrap(page, { timeout: LOGIN_TIMEOUT_MS });
  if (!(await page.getByLabel('login-email', { exact: true }).count())) {
    await page.getByRole('textbox', { name: /E-mail ou telefone/i }).first().waitFor({ timeout: 30_000 });
  }
  await fillLoginFields(page, USER_EMAIL, USER_PASSWORD, { skipBootstrap: true });
  await submitLogin(page);
  await waitQaLabel(page, 'app-authenticated', { timeout: LOGIN_TIMEOUT_MS });
  await waitQaLabel(page, 'company-loaded', { timeout: 60_000 });
  await waitQaLabel(page, 'navigation-ready', { timeout: 60_000 });
  await waitQaLabel(page, 'home-ready', { timeout: LOGIN_TIMEOUT_MS });
  const lojaVisible = await page.getByText(new RegExp(LOJA_ID, 'i')).count();
  if (!lojaVisible) throw new Error(`Run ${runIndex}: loja ${LOJA_ID} não visível`);
  console.log(`✓ Run ${runIndex}: login → home-ready`);
}

async function main() {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';
  await assertEmulatorPreflight();

  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');

  let passed = 0;
  for (let i = 1; i <= RUNS; i++) {
    const violations = [];
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      viewport: { width: 1400, height: 900 },
    });
    await context.clearCookies();
    const page = await context.newPage();
    attachProductionNetworkGuard(page, violations);
    attachConsoleCollector(page);

    try {
      await runLoginOnce(page, i);
      const prodCount = getProductionRequestCount();
      if (prodCount > 0) {
        throw new Error(`Run ${i}: rede produção count=${prodCount}`);
      }
      if (violations.length) throw new Error(`Run ${i}: violations=${violations.length}`);
      passed++;
    } finally {
      await browser.close();
    }
  }

  server.close();
  const ok = passed === RUNS;
  console.log(
    ok
      ? `WEB_BROWSER_UI_LOGIN_GREEN: ${passed}/${RUNS} runs`
      : `NO_GO_R8440_LOGIN_FOUNDATION_READY: ${passed}/${RUNS} runs`,
  );
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
