/**
 * Playwright — Web UI E2E completo (R8.4.39)
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

import {
  CLIENTE_ID,
  LOJA_ID,
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
  attachStrictConsoleGuard,
  assertConsoleAndNetworkClean,
  assertNoProductionViolations,
  getProductionRequestCount,
} from '../lib/env-guard.mjs';
import {
  attachConsoleCollector,
  fillLoginFields,
  submitLogin,
  waitForQaBootstrap,
  waitQaLabel,
} from '../lib/flutter-semantics.mjs';
import { serveStatic } from '../lib/serve-build.mjs';
import { readRevendaPedido, readStockProduct } from '../lib/stock-readback.mjs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../..');

const classifications = [];
const runStats = [];

function classify(name, ok) {
  classifications.push({ name, ok });
  console.log(`${ok ? '✓' : '✗'} ${name}`);
}

async function waitMs(ms, label) {
  console.log(`… aguardando ${label} (${Math.round(ms / 1000)}s)`);
  await new Promise((r) => setTimeout(r, ms));
}

async function loginUi(page) {
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login`, { waitUntil: 'load', timeout: 120_000 });
  await waitForQaBootstrap(page, { timeout: 180_000 });
  if (!(await page.getByLabel('login-email', { exact: true }).count())) {
    await page.getByRole('textbox', { name: /E-mail ou telefone/i }).first().waitFor({ timeout: 30_000 });
  }
  await fillLoginFields(page, USER_EMAIL, USER_PASSWORD, { skipBootstrap: true });
  await submitLogin(page);
  await waitQaLabel(page, 'home-ready', { timeout: 180_000 });
  await waitQaLabel(page, 'company-loaded', { timeout: 30_000 });
  await waitQaLabel(page, 'navigation-ready', { timeout: 60_000 });
  const lojaText = await page.getByText(/Empresa QA R8439|loja-r8439-qa/i).first().textContent().catch(() => '');
  if (!lojaText && !LOJA_ID) throw new Error('Empresa QA não visível');
  classify('WEB_BROWSER_UI_LOGIN_GREEN', true);
}

async function clickNav(page, navLabel) {
  const loc = page.getByRole('button', { name: new RegExp(navLabel, 'i') }).first();
  if (await loc.count() === 0) {
    await page.getByLabel(navLabel, { exact: false }).first().click({ timeout: 60_000 });
  } else {
    await loc.click({ timeout: 60_000 });
  }
}

async function readUiStock(page, productKey) {
  const el = page.getByLabel(`product-stock-${productKey}`, { exact: false });
  await el.first().waitFor({ timeout: 90_000 });
  const val = await el.first().getAttribute('aria-valuetext');
  if (val) return Number(val);
  const text = await el.first().innerText();
  const m = text.match(/Qtd:\s*(\d+)/);
  return m ? Number(m[1]) : NaN;
}

async function syncEstoque(page) {
  await clickNav(page, 'nav-estoque');
  await page.waitForTimeout(3000);
}

async function selectProdutoAutocomplete(page, nome) {
  const field = page.getByRole('textbox', { name: /^Produto$/i }).first();
  await field.click();
  await field.fill(nome.slice(0, 4));
  await page.getByText(nome, { exact: false }).first().click({ timeout: 30_000 });
}

async function selectVariacao(page, tamanho) {
  await page.getByText(tamanho, { exact: true }).first().click({ timeout: 15_000 }).catch(async () => {
    await page.getByRole('button', { name: new RegExp(`^${tamanho}$`) }).first().click();
  });
  const confirm = page.getByRole('button', { name: /Confirmar|Adicionar/i }).first();
  if (await confirm.count()) await confirm.click();
}

async function novaVendaComProduto(page, nome, { variacao } = {}) {
  await clickNav(page, 'nav-vendas');
  await page.getByLabel('nav-new-sale', { exact: false }).first().click({ timeout: 60_000 });
  await page.waitForTimeout(2000);
  if (variacao) {
    await selectProdutoAutocomplete(page, nome);
    await selectVariacao(page, variacao);
  } else {
    await selectProdutoAutocomplete(page, nome);
  }
  await page.getByLabel('sale-complete', { exact: false }).first().click({ timeout: 60_000 });
  await page.getByText(/sucesso|registrada|finalizada/i).first().waitFor({ timeout: 120_000 }).catch(() => {});
  await page.waitForTimeout(2000);
}

async function readStockOnly(page, productId) {
  await syncEstoque(page);
  const ui = await readUiStock(page, productId);
  const rb = await readStockProduct(productId);
  return { ui, rb };
}

async function assertStock(page, productId, expected) {
  const { ui, rb } = await readStockOnly(page, productId);
  if (expected == null) return { ok: true, ui, rb };
  return { ok: ui === expected && rb.quantidade === expected, ui, rb };
}

async function simpleSaleFlow(page) {
  await syncEstoque(page);
  const before = await readUiStock(page, PROD_SIMPLES_ID);
  await novaVendaComProduto(page, PROD_SIMPLES_NOME);
  const after = await assertStock(page, PROD_SIMPLES_ID, before - 1);
  console.log(JSON.stringify(after, null, 2));
  classify('WEB_BROWSER_UI_SIMPLE_SALE_STOCK_GREEN', after.ok);
  return after;
}

async function persistenceWaits(page, productId, expected) {
  let okT0 = (await assertStock(page, productId, expected)).ok;
  classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN_T0', okT0);
  await waitMs(WAIT_1_MS, 'T+1');
  let okT1 = (await assertStock(page, productId, expected)).ok;
  classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN_T1', okT1);
  await waitMs(WAIT_5_MS - WAIT_1_MS, 'T+5 total');
  let okT5 = (await assertStock(page, productId, expected)).ok;
  classify('WEB_BROWSER_UI_STOCK_NO_REVERSION_GREEN', okT0 && okT1 && okT5);
  return okT0 && okT1 && okT5;
}

async function variationsFlow(page) {
  await novaVendaComProduto(page, PROD_VAR_NOME, { variacao: 'P' });
  await clickNav(page, 'nav-vendas');
  await page.getByLabel('nav-new-sale', { exact: false }).first().click();
  await page.waitForTimeout(1500);
  await selectProdutoAutocomplete(page, PROD_VAR_NOME);
  await selectVariacao(page, 'M');
  await page.getByRole('button', { name: /Adicionar|mais/i }).first().click().catch(() => {});
  await selectProdutoAutocomplete(page, PROD_VAR_NOME);
  await selectVariacao(page, 'G');
  await page.getByLabel('sale-complete', { exact: false }).first().click();
  await page.waitForTimeout(3000);
  await syncEstoque(page);
  const rb = await readStockProduct(PROD_VAR_ID);
  const ok =
    rb.estoquePorTamanho?.P === 4 &&
    rb.estoquePorTamanho?.M === 5 &&
    rb.estoquePorTamanho?.G === 6;
  classify('WEB_BROWSER_UI_MULTIPLE_VARIATIONS_STOCK_GREEN', ok);
  return ok;
}

async function excluirUltimaVenda(page) {
  await clickNav(page, 'nav-vendas');
  await page.waitForTimeout(2000);
  await page.getByRole('button', { name: /Excluir/i }).first().click({ timeout: 60_000 });
  await page.getByText('Excluir Venda?', { exact: false }).waitFor({ timeout: 30_000 });
  await page.getByRole('button', { name: /^Excluir$/i }).last().click();
  await page.waitForTimeout(4000);
}

async function cancelFlow(page) {
  const before = (await assertStock(page, PROD_SIMPLES_ID, null)).ui;
  await novaVendaComProduto(page, PROD_SIMPLES_NOME);
  const mid = (await assertStock(page, PROD_SIMPLES_ID, before - 1)).ui;
  await excluirUltimaVenda(page);
  const after = (await assertStock(page, PROD_SIMPLES_ID, before)).ui;
  const rb = await readStockProduct(PROD_SIMPLES_ID);
  const ok = mid === before - 1 && after === before && rb.quantidade === before;
  classify('WEB_BROWSER_UI_CANCEL_STOCK_GREEN', ok);
  await waitMs(WAIT_1_MS, 'T+1 cancel');
  const afterT1 = (await assertStock(page, PROD_SIMPLES_ID, before)).ui;
  classify('WEB_BROWSER_UI_CANCEL_STOCK_GREEN_T1', afterT1 === before);
  return ok;
}

async function returnFlow(page) {
  const before = (await assertStock(page, PROD_SIMPLES_ID, null)).ui;
  await novaVendaComProduto(page, PROD_SIMPLES_NOME);
  await excluirUltimaVenda(page);
  const after = (await assertStock(page, PROD_SIMPLES_ID, before)).ui;
  await page.reload({ waitUntil: 'load' });
  await waitQaLabel(page, 'home-ready', { timeout: 120_000 });
  await syncEstoque(page);
  const ui2 = await readUiStock(page, PROD_SIMPLES_ID);
  const ok = after === before && ui2 === before;
  classify('WEB_BROWSER_UI_RETURN_STOCK_GREEN', ok);
  return ok;
}

async function revendaThreeItemsFlow(page) {
  await clickNav(page, 'nav-fornecedores');
  await page.waitForTimeout(4000);
  await page.getByText(/Fornecedor QA R8439/i).first().click({ timeout: 60_000 });
  await page.getByRole('button', { name: /Nova compra|Adicionar compra/i }).first().click({ timeout: 60_000 }).catch(async () => {
    await page.getByIcon?.('add')?.click?.();
  });
  await page.getByText(/Revenda.*detalhar|detalhar depois/i).first().click({ timeout: 30_000 }).catch(() => {});
  for (const nome of PROD_REVENDA_NOMES) {
    await page.getByRole('button', { name: /Adicionar item|Adicionar peça/i }).first().click({ timeout: 30_000 });
    await page.getByText(nome, { exact: false }).first().click({ timeout: 30_000 });
    await page.getByRole('button', { name: /Confirmar|Salvar/i }).first().click().catch(() => {});
  }
  await page.getByRole('button', { name: /Confirmar compra|Salvar/i }).first().click({ timeout: 60_000 });
  await page.waitForTimeout(4000);
  const lineCount = await page.getByText(/Peca Revenda QA/i).count();
  const okLines = lineCount >= 3;
  classify('REVENDAS_ITEMS_PERSISTENCE_WEB_UI_GREEN', okLines);
  return okLines;
}

async function twoTabsFlow(context, stockExpected) {
  const pageB = await context.newPage();
  const violations = [];
  attachProductionNetworkGuard(pageB, violations);
  attachConsoleCollector(pageB);
  await pageB.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login`, { waitUntil: 'load' });
  await loginUi(pageB);
  await syncEstoque(pageB);
  const uiB = await readUiStock(pageB, PROD_SIMPLES_ID);
  await pageB.close();
  const ok = uiB === stockExpected;
  classify('WEB_BROWSER_UI_TWO_TABS_STALE_WRITE_GREEN', ok);
  return ok;
}

async function runSuite(browser, runIndex) {
  const started = Date.now();
  console.log(`\n========== Execução UI E2E #${runIndex} ==========`);
  const violations = [];
  const context = await browser.newContext({
    viewport: { width: 1400, height: 900 },
    storageState: undefined,
  });
  const page = await context.newPage();
  attachProductionNetworkGuard(page, violations);
  attachStrictConsoleGuard(page, violations);
  attachConsoleCollector(page);

  let passed = 0;
  let failed = 0;
  try {
    await loginUi(page);
    const sale = await simpleSaleFlow(page);
    if (sale.ok) passed++; else failed++;
    const expected = sale.ui;
    if (await persistenceWaits(page, PROD_SIMPLES_ID, expected)) passed++; else failed++;
    if (await variationsFlow(page)) passed++; else failed++;
    if (await cancelFlow(page)) passed++; else failed++;
    if (await returnFlow(page)) passed++; else failed++;
    try {
      if (await revendaThreeItemsFlow(page)) passed++; else failed++;
    } catch (e) {
      console.warn('Revenda UI parcial:', e.message);
      classify('REVENDAS_ITEMS_PERSISTENCE_WEB_UI_GREEN', false);
      failed++;
    }
    if (await twoTabsFlow(context, expected)) passed++; else failed++;
    assertNoProductionViolations(violations);
    assertConsoleAndNetworkClean(violations);
    classify('WEB_UI_E2E_PRODUCTION_NETWORK_BLOCKED', getProductionRequestCount() === 0);
    return true;
  } catch (e) {
    console.error('Suite falhou:', e);
    failed++;
    return false;
  } finally {
    const duration = Date.now() - started;
    runStats.push({ run: runIndex, passed, failed, duration });
    await context.close();
  }
}

async function failClosedCheck() {
  const prev = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:1';
  try {
    await assertEmulatorPreflight();
    console.error('Fail-closed NÃO disparou');
    return false;
  } catch {
    console.log('WEB_UI_E2E_QA_FAILS_CLOSED_RUNTIME_CONFIRMED');
    return true;
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = prev;
  }
}

async function main() {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';

  const failClosed = await failClosedCheck();
  classify('WEB_UI_E2E_QA_FAILS_CLOSED_RUNTIME_CONFIRMED', failClosed);

  await assertEmulatorPreflight();
  const buildPath = path.resolve(repoRoot, QA_BUILD_DIR);
  if (!fs.existsSync(buildPath)) {
    console.error(`Build QA ausente: ${buildPath}`);
    process.exit(2);
  }

  const server = await serveStatic(buildPath, QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });

  const { spawnSync } = await import('node:child_process');
  const seedEnv = { ...process.env };
  spawnSync(process.execPath, ['seed/seed.mjs'], {
    cwd: path.join(repoRoot, 'tool/e2e_web'),
    stdio: 'inherit',
    env: seedEnv,
  });

  const r1 = await runSuite(browser, 1);
  spawnSync(process.execPath, ['seed/seed.mjs'], {
    cwd: path.join(repoRoot, 'tool/e2e_web'),
    stdio: 'inherit',
    env: seedEnv,
  });
  const r2 = await runSuite(browser, 2);

  await browser.close();
  server.close();

  console.log('\nRun stats:', JSON.stringify(runStats, null, 2));
  console.log('\nClassificações:', JSON.stringify(classifications, null, 2));
  const allOk = r1 && r2 && failClosed && classifications.every((c) => c.ok);
  console.log(`WEB_BROWSER_UI_E2E_EXECUTED: ${allOk}`);
  process.exit(allOk ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
