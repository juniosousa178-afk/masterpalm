/**
 * Helper único — espera labels semânticos Flutter Web (R8.4.39).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ARTIFACT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../.artifacts');

export async function collectVisibleLabels(page) {
  try {
    const snap = await page.locator('body').ariaSnapshot();
    const labels = [];
    const re = /"([^"]+)"/g;
    let m;
    while ((m = re.exec(snap)) !== null) labels.push(m[1]);
    return [...new Set(labels)].slice(0, 80);
  } catch {
    return [];
  }
}

export async function waitQaLabel(page, label, { timeout = 120_000 } = {}) {
  const locator = page.getByLabel(label, { exact: true });
  const started = Date.now();
  try {
    await locator.first().waitFor({ state: 'attached', timeout });
    await locator.first().waitFor({ state: 'visible', timeout: Math.max(1000, timeout - (Date.now() - started)) });
    return locator.first();
  } catch (err) {
    const url = page.url();
    const labels = await collectVisibleLabels(page);
    const shotDir = ARTIFACT_DIR;
    fs.mkdirSync(shotDir, { recursive: true });
    const shot = path.join(shotDir, `timeout-${label}-${Date.now()}.png`);
    try {
      await page.screenshot({ path: shot, fullPage: true });
    } catch (_) {}
    const consoleTail = (page._qaConsoleErrors || []).slice(-8).join('\n');
    throw new Error(
      `Timeout aguardando label "${label}" (${timeout}ms)\n` +
        `URL: ${url}\n` +
        `Labels visíveis: ${labels.join(', ') || '(nenhum)'}\n` +
        `Screenshot: ${shot}\n` +
        (consoleTail ? `Console errors:\n${consoleTail}` : ''),
    );
  }
}

export function attachConsoleCollector(page) {
  page._qaConsoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') page._qaConsoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => page._qaConsoleErrors.push(String(err)));
}

export async function fillLoginFields(page, email, password) {
  await ensureFlutterAccessibility(page);
  await page.waitForTimeout(2000);
  let emailEl = page.getByRole('textbox', { name: /E-mail ou telefone/i });
  if ((await emailEl.count()) === 0) {
    emailEl = page.getByLabel('login-email', { exact: false });
  }
  await emailEl.first().click({ timeout: 120_000 });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(email, { delay: 20 });
  let passEl = page.getByRole('textbox', { name: /^Senha$/i });
  if ((await passEl.count()) === 0) {
    passEl = page.getByLabel('login-password', { exact: false });
  }
  await passEl.first().click({ timeout: 60_000 });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(password, { delay: 20 });
}

export async function submitLogin(page) {
  await page.getByRole('button', { name: /login-submit|Entrar/i }).first().click({ timeout: 60_000 });
}

export async function ensureFlutterAccessibility(page) {
  const btn = page.getByRole('button', { name: /Enable accessibility/i });
  if (await btn.count()) {
    await btn.first().click({ timeout: 10_000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

export async function waitForFlutterShell(page) {
  for (const sel of ['flt-glass-pane', 'flutter-view', 'canvas']) {
    try {
      await page.waitForSelector(sel, { timeout: 30_000 });
      await ensureFlutterAccessibility(page);
      return;
    } catch (_) {}
  }
  await page.getByText('Entrar', { exact: false }).first().waitFor({ timeout: 60_000 });
  await ensureFlutterAccessibility(page);
}
