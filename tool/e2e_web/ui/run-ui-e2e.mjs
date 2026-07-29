/**
 * Playwright — Web UI E2E isolado (R8.4.38)
 * Operações exclusivamente pela interface Flutter Web principal.
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

import {
  CLIENTE_ID,
  LOJA_ID,
  PEDIDO_REVENDA_VAZIO_ID,
  PROD_REVENDA_IDS,
  PROD_REVENDA_NOMES,
  PROD_SIMPLES_ID,
  PROD_SIMPLES_NOME,
  PROD_VAR_ID,
  PROD_VAR_NOME,
  QA_BUILD_DIR,
  QA_SERVE_PORT,
  USER_EMAIL,
  USER_PASSWORD,
  WAIT_1_MS,
  WAIT_5_MS,
} from '../lib/constants.mjs';
import { assertEmulatorPreflight } from '../lib/emulator-preflight.mjs';
import {
  attachProductionNetworkGuard,
  assertNoProductionViolations,
} from '../lib/env-guard.mjs';
import { serveStatic } from '../lib/serve-build.mjs';
import { readRevendaPedido, readStockProduct } from '../lib/stock-readback.mjs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');

const classifications = [];
const consoleErrors = [];
const networkErrors = [];

function classify(name, ok) {
  classifications.push({ name, ok });
  console.log(`${ok ? '✓' : '✗'} ${name}`);
}

async function waitMs(ms, label) {
  console.log(`… aguardando ${label} (${Math.round(ms / 1000)}s)`);
  await new Promise((r) => setTimeout(r, ms));
}

async function byLabel(page, label) {
  // Semantics QA expõe aria-label; fallback para texto visível Flutter.
  let loc = page.getByLabel(label, { exact: false });
  if (await loc.count() === 0) {
    loc = page.getByRole('textbox', { name: new RegExp(label, 'i') });
  }
  if (await loc.count() === 0 && label === 'login-submit') {
    loc = page.getByRole('button', { name: /entrar/i });
  }
  await loc.first().waitFor({ state: 'visible', timeout: 120_000 });
  return loc.first();
}

async function fillLabel(page, label, value) {
  if (label === 'login-email') {
    const el = page.getByRole('textbox', { name: /E-mail ou telefone/i });
    await el.click({ timeout: 120_000 });
    await el.fill('');
    await page.keyboard.type(value, { delay: 20 });
    return;
  }
  if (label === 'login-password') {
    const el = page.getByRole('textbox', { name: /^Senha$/i });
    await el.click({ timeout: 120_000 });
    await el.fill('');
    await page.keyboard.type(value, { delay: 20 });
    return;
  }
  const el = await byLabel(page, label);
  await el.fill(value, { timeout: 60_000 });
}

async function clickLabel(page, label) {
  if (label === 'login-submit') {
    await page.getByRole('button', { name: /login-submit|Entrar/i }).first().click({ timeout: 60_000 });
    return;
  }
  const el = await byLabel(page, label);
  await el.click({ timeout: 60_000 });
}

async function waitForFlutterApp(page) {
  const selectors = ['flt-glass-pane', 'flutter-view', 'canvas'];
  for (const sel of selectors) {
    try {
      await page.waitForSelector(sel, { timeout: 30_000 });
      return;
    } catch (_) {}
  }
  await page.getByText('Entrar', { exact: false }).first().waitFor({ timeout: 120_000 });
}

async function loginUi(page) {
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login`, { waitUntil: 'load', timeout: 120_000 });
  await waitForFlutterApp(page);
  await page.waitForTimeout(5000);
  await fillLabel(page, 'login-email', USER_EMAIL);
  await fillLabel(page, 'login-password', USER_PASSWORD);
  await clickLabel(page, 'login-submit');
  // SPA: rota pode permanecer /login; aguardar menu home.
  await page.getByRole('button', { name: /nav-estoque|Estoque/i }).first()
    .waitFor({ state: 'visible', timeout: 180_000 });
  await page.waitForTimeout(2000);
  classify('WEB_BROWSER_UI_LOGIN_GREEN', true);
}

async function openNav(page, navLabel) {
  await clickLabel(page, navLabel);
  await page.waitForTimeout(2000);
}

async function readUiStock(page, productKey) {
  const el = page.getByLabel(`product-stock-${productKey}`, { exact: false });
  await el.first().waitFor({ timeout: 60_000 });
  const val = await el.first().getAttribute('aria-valuetext');
  if (val) return Number(val);
  const text = await el.first().innerText();
  const m = text.match(/Qtd:\s*(\d+)/);
  return m ? Number(m[1]) : NaN;
}

async function simpleSaleFlow(page) {
  await openNav(page, 'nav-estoque');
  const stockBefore = await readUiStock(page, PROD_SIMPLES_ID);
  console.log(`Estoque UI inicial simples: ${stockBefore}`);

  await openNav(page, 'nav-vendas');
  await clickLabel(page, 'nav-new-sale');
  await page.waitForTimeout(2000);

  // Selecionar produto no dropdown (primeira linha)
  const dropdown = page.locator('[aria-label*="dropdown_produto"], [aria-label*="Produto"]').first();
  if (await dropdown.count()) {
    await dropdown.click();
    await page.getByText(PROD_SIMPLES_NOME, { exact: false }).first().click();
  } else {
    await page.getByText(PROD_SIMPLES_NOME, { exact: false }).first().click();
  }
  await page.waitForTimeout(1000);
  await clickLabel(page, 'sale-complete');
  await page.waitForTimeout(5000);

  await openNav(page, 'nav-estoque');
  const stockAfter = await readUiStock(page, PROD_SIMPLES_ID);
  const rb = await readStockProduct(PROD_SIMPLES_ID);
  console.log(JSON.stringify({ stockAfter, readback: rb }, null, 2));

  const ok = stockAfter === 9 && rb.quantidade === 9;
  classify('WEB_BROWSER_UI_SIMPLE_SALE_STOCK_GREEN', ok);
  return { stockAfter, rb };
}

async function assertStockPersists(page, expected) {
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(4000);
  const ui = await readUiStock(page, PROD_SIMPLES_ID);
  const rb = await readStockProduct(PROD_SIMPLES_ID);
  const ok = ui === expected && rb.quantidade === expected && rb.stockRevision >= 1;
  if (!ok) {
    console.error('Persistência falhou', { ui, rb, expected });
  }
  return ok;
}

async function runSuite(browser, runIndex) {
  console.log(`\n========== Execução UI E2E #${runIndex} ==========`);
  const violations = [];
  const context = await browser.newContext();
  const page = await context.newPage();
  attachProductionNetworkGuard(page, violations);

  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(String(err)));
  page.on('requestfailed', (req) => networkErrors.push(req.url()));

  try {
    await loginUi(page);
    const { stockAfter } = await simpleSaleFlow(page);

    let okT0 = await assertStockPersists(page, stockAfter);
    classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN_T0', okT0);

    await waitMs(WAIT_1_MS, 'T+1');
    let okT1 = await assertStockPersists(page, stockAfter);
    classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN_T1', okT1);

    await waitMs(WAIT_5_MS - WAIT_1_MS, 'T+5 total');
    let okT5 = await assertStockPersists(page, stockAfter);
    classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN', okT0 && okT1 && okT5);

    // Duas abas — estoque
    const pageB = await context.newPage();
    attachProductionNetworkGuard(pageB, violations);
    await pageB.goto(`http://127.0.0.1:${QA_SERVE_PORT}/home`, { waitUntil: 'load' });
    await pageB.waitForTimeout(3000);
    await openNav(pageB, 'nav-estoque');
    const uiB = await readUiStock(pageB, PROD_SIMPLES_ID);
    classify('WEB_BROWSER_UI_TWO_TABS_STALE_WRITE_GREEN', uiB === stockAfter);

    await pageB.close();
    assertNoProductionViolations(violations);
    return true;
  } catch (e) {
    console.error('Suite falhou:', e);
    return false;
  } finally {
    await context.close();
  }
}

async function main() {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';

  await assertEmulatorPreflight();

  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  if (!fs.existsSync(buildPath)) {
    console.error(`Build QA ausente: ${buildPath}. Execute scripts/build_web_qa_e2e.ps1`);
    process.exit(2);
  }

  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });

  const r1 = await runSuite(browser, 1);
  const { spawnSync } = await import('node:child_process');
  spawnSync(process.execPath, ['seed/seed.mjs'], {
    cwd: path.join(repoRoot, 'tool/e2e_web'),
    stdio: 'inherit',
    env: process.env,
  });
  const r2 = await runSuite(browser, 2);

  await browser.close();
  server.close();

  const allOk = r1 && r2 && classifications.every((c) => c.ok);
  console.log('\nClassificações:', JSON.stringify(classifications, null, 2));
  console.log(`WEB_BROWSER_UI_E2E_EXECUTED: ${allOk}`);
  process.exit(allOk ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
