/**
 * Helper único — espera labels semânticos Flutter Web (R8.4.40).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ARTIFACT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../.artifacts');

export async function collectVisibleLabels(page) {
  const labels = new Set();
  try {
    const snap = await page.locator('body').ariaSnapshot();
    const re = /"([^"]+)"/g;
    let m;
    while ((m = re.exec(snap)) !== null) labels.add(m[1]);
  } catch (_) {}
  try {
    const nodes = await page.locator('[aria-label]').all();
    for (const n of nodes.slice(0, 40)) {
      const v = await n.getAttribute('aria-label');
      if (v) labels.add(v);
    }
  } catch (_) {}
  try {
    const flt = await page.locator('flt-semantics').all();
    for (const n of flt.slice(0, 40)) {
      const v = await n.getAttribute('aria-label');
      if (v) labels.add(v);
    }
  } catch (_) {}
  return [...labels].slice(0, 120);
}

export async function ensureFlutterAccessibility(page) {
  const clickEnable = async () => {
    const btn = page.getByRole('button', { name: /Enable accessibility/i });
    if (await btn.count()) {
      await btn.first().click({ timeout: 10_000, force: true }).catch(() => {});
      await page.waitForTimeout(600);
    }
    await page.evaluate(() => {
      const el =
        document.querySelector('[aria-label="Enable accessibility"]') ||
        document.querySelector('flt-semantics-placeholder');
      if (el && typeof el.click === 'function') el.click();
    }).catch(() => {});
    await page.waitForTimeout(400);
  };

  for (let i = 0; i < 4; i++) {
    await clickEnable();
    const labels = await collectVisibleLabels(page);
    if (labels.some((l) => l.includes('qa-bootstrap'))) return;
    const text = await page.locator('body').innerText().catch(() => '');
    if (text.includes('qa-bootstrap-stage-')) return;
  }
}

export async function waitQaLabel(page, label, { timeout = 120_000 } = {}) {
  await ensureFlutterAccessibility(page);
  const started = Date.now();
  const deadline = started + timeout;

  const tryFind = async () => {
    const byLabel = page.getByLabel(label, { exact: true });
    if (await byLabel.count()) return byLabel.first();
    const byAria = page.locator(`[aria-label="${label}"]`);
    if (await byAria.count()) return byAria.first();
    const byText = page.getByText(label, { exact: true });
    if (await byText.count()) return byText.first();
    return null;
  };

  while (Date.now() < deadline) {
    const el = await tryFind();
    if (el) {
      await el.waitFor({ state: 'visible', timeout: 2000 }).catch(() => {});
      return el;
    }
    await ensureFlutterAccessibility(page);
    await page.waitForTimeout(500);
  }

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

export function attachConsoleCollector(page) {
  page._qaConsoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') page._qaConsoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => page._qaConsoleErrors.push(String(err)));
}

export async function waitForFlutterShell(page) {
  for (const sel of ['flt-glass-pane', 'flutter-view', 'canvas']) {
    try {
      await page.waitForSelector(sel, { timeout: 45_000 });
      await ensureFlutterAccessibility(page);
      return;
    } catch (_) {}
  }
  await ensureFlutterAccessibility(page);
}

export async function isLoginScreenReady(page) {
  const labels = await collectVisibleLabels(page);
  if (labels.some((l) => l === 'login-email')) return true;
  if (labels.some((l) => /E-mail ou telefone/i.test(l))) return true;
  if (await page.getByRole('textbox', { name: /E-mail ou telefone/i }).count()) return true;
  return false;
}

export async function waitForQaBootstrap(page, { timeout = 180_000 } = {}) {
  await waitForFlutterShell(page);
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const labels = await collectVisibleLabels(page);
    if (labels.some((l) => l.startsWith('qa-bootstrap-ready'))) return;
    if (labels.some((l) => l.startsWith('qa-bootstrap-started'))) return;
    if (labels.some((l) => l.includes('qa-bootstrap-stage-'))) return;
    if (await isLoginScreenReady(page)) return;
    await ensureFlutterAccessibility(page);
    await page.waitForTimeout(400);
  }
  const labels = await collectVisibleLabels(page);
  throw new Error(
    `Timeout aguardando bootstrap QA (${timeout}ms). Labels: ${labels.join(', ') || '(nenhum)'}`,
  );
}

export async function fillLoginFields(page, email, password, { skipBootstrap = false } = {}) {
  if (!skipBootstrap) await waitForQaBootstrap(page);
  await ensureFlutterAccessibility(page);

  const textInput = page.locator('input[type="text"]').first();
  const passInput = page.locator('input[type="password"]').first();
  await textInput.waitFor({ state: 'attached', timeout: 60_000 });

  await textInput.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.insertText(email);
  await page.waitForTimeout(500);

  const passBox = page.getByRole('textbox', { name: /^Senha$/i });
  await passBox.first().click({ timeout: 30_000 });
  await page.waitForTimeout(200);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(password, { delay: 25 });
  await page.waitForTimeout(500);

  const passVal = await passInput.inputValue().catch(() => '');
  if (!passVal) {
    await passInput.click();
    await page.keyboard.type(password, { delay: 25 });
    await page.waitForTimeout(300);
  }
}

export async function submitLogin(page) {
  const triggered = await page.evaluate(() => {
    if (typeof globalThis.__mpQaE2eLogin === 'function') {
      globalThis.__mpQaE2eLogin();
      return true;
    }
    return false;
  }).catch(() => false);

  if (triggered) {
    await page.waitForTimeout(1500);
    return;
  }

  const passEl = page.getByRole('textbox', { name: /^Senha$/i });
  if (await passEl.count()) {
    await passEl.first().press('Enter');
    await page.waitForTimeout(1500);
    if (!page.url().includes('/login')) return;
  }
  const btn = page.getByRole('button', { name: /^Entrar$/i });
  const n = await btn.count();
  if (n > 0) {
    const box = await btn.last().boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await btn.last().click({ timeout: 60_000, force: true });
  }
}

export function resetAccessibilityState() {
  // noop — re-click é idempotente por run
}
