/**
 * R8.4.43 — Fase C (reload), perfil limpo e isolamento por origin.
 * Playwright: observação externa apenas — não autentica.
 */
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  attachAuthEmulatorRequestCollector,
  collectVisibleLabels,
  ensureFlutterAccessibility,
  hasQaLabel,
  waitQaLabel,
} from '../lib/flutter-semantics.mjs';
import { EMPRESA_NOME } from '../lib/constants.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const mode = process.argv[2] || 'reload';
const profileDir = process.env.R8443_CHROME_PROFILE || '';
const origin = process.env.R8443_WEB_ORIGIN || 'http://127.0.0.1:8811';
const negativeProfile =
  process.env.R8443_NEGATIVE_PROFILE ||
  path.join(process.env.TEMP || '/tmp', 'masterpalm-r8443-negative-profile');
const isolationOrigin =
  process.env.R8443_ISOLATION_ORIGIN || 'http://127.0.0.1:8812';

const PRODUCTION_HOSTS = [
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'masterpalm-58c46.firebaseapp.com',
  'firestore.googleapis.com',
];

function attachProductionGuard(page) {
  const hits = [];
  page.on('request', (req) => {
    try {
      const u = new URL(req.url());
      if (PRODUCTION_HOSTS.some((h) => u.hostname.includes(h))) {
        hits.push({ type: 'attempt', host: u.hostname, path: u.pathname });
      }
    } catch (_) {}
  });
  page.on('response', (res) => {
    try {
      const u = new URL(res.url());
      if (PRODUCTION_HOSTS.some((h) => u.hostname.includes(h))) {
        hits.push({
          type: 'completed',
          host: u.hostname,
          status: res.status(),
        });
      }
    } catch (_) {}
  });
  page._qaProductionHits = hits;
  return hits;
}

async function waitHomeReady(page, { timeout = 300_000 } = {}) {
  await ensureFlutterAccessibility(page);

  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const labels = await collectVisibleLabels(page);
    if (labels.includes('qa-bootstrap-error')) {
      throw new Error(`qa-bootstrap-error visível: ${labels.join(', ')}`);
    }
    if (labels.includes('home-ready')) break;
    await page.waitForTimeout(500);
  }

  if (!(await hasQaLabel(page, 'home-ready'))) {
    throw new Error('home-ready ausente após bootstrap');
  }
  const body = await page.locator('body').innerText().catch(() => '');
  if (!body.includes(EMPRESA_NOME)) {
    throw new Error(`empresa QA não visível: ${EMPRESA_NOME}`);
  }
}

async function waitLoginScreen(page, { timeout = 120_000 } = {}) {
  await ensureFlutterAccessibility(page);
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await hasQaLabel(page, 'login-email')) return;
    const body = await page.locator('body').innerText().catch(() => '');
    if (body.includes('login-email') || body.includes('Entrar')) return;
    await page.waitForTimeout(400);
  }
  throw new Error('LoginScreen não apareceu no tempo esperado');
}

async function launchPersistentChrome(profileDir) {
  return chromium.launchPersistentContext(profileDir, {
    headless: true,
    channel: 'chrome',
    args: ['--disable-extensions', '--headless=new'],
  });
}

function resolveChromeExe() {
  const candidates = [
    process.env.CHROME_EXECUTABLE,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    path.join(
      process.env.LOCALAPPDATA || '',
      'Google\\Chrome\\Application\\chrome.exe',
    ),
  ].filter(Boolean);
  for (const p of candidates) {
    try {
      if (p && fs.existsSync(p)) return p;
    } catch (_) {}
  }
  return null;
}

async function withChromeCdpSession(profileDir, origin, fn) {
  const chromeExe = resolveChromeExe();
  if (!chromeExe) throw new Error('Chrome.exe nao encontrado para Fase C');
  const debugPort = Number(process.env.R8443_CHROME_DEBUG_PORT || 9333);
  const chromeProc = spawn(
    chromeExe,
    [
      `--user-data-dir=${profileDir}`,
      `--remote-debugging-port=${debugPort}`,
      '--headless=new',
      '--disable-extensions',
      '--no-first-run',
      '--no-default-browser-check',
      origin,
    ],
    { stdio: 'ignore' },
  );
  await new Promise((r) => setTimeout(r, 4000));
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
  try {
    const context = browser.contexts()[0] || (await browser.newContext());
    const page = context.pages()[0] || (await context.newPage());
    await fn(page);
  } finally {
    await browser.close().catch(() => {});
    chromeProc.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 1500));
  }
}

async function runReload() {
  if (!profileDir) throw new Error('R8443_CHROME_PROFILE obrigatório');

  await withChromeCdpSession(profileDir, origin, async (page) => {
    const prodHits = attachProductionGuard(page);
    const authReqs = attachAuthEmulatorRequestCollector(page);

    await page.waitForLoadState('domcontentloaded', { timeout: 120_000 }).catch(() => {});
    await waitHomeReady(page);

    await page.reload({ waitUntil: 'domcontentloaded', timeout: 120_000 });
    await ensureFlutterAccessibility(page);
    await waitHomeReady(page);

    if (await hasQaLabel(page, 'login-email')) {
      throw new Error('login-email visivel apos reload');
    }

    const signIns = authReqs.filter((r) =>
      String(r.path || '').includes('signInWithPassword'),
    );
    console.log(
      JSON.stringify({
        WEB_REAL_RELOAD_AUTH_PERSISTENCE_GREEN: true,
        PHASE_C_SIGN_IN_WITH_PASSWORD_COUNT: signIns.length,
        PRODUCTION_REQUEST_ATTEMPTED_COUNT: prodHits.filter(
          (h) => h.type === 'attempt',
        ).length,
        PRODUCTION_REQUEST_COMPLETED_COUNT: prodHits.filter(
          (h) => h.type === 'completed',
        ).length,
      }),
    );
  });
  process.exit(0);
}

async function runCleanProfile() {
  const context = await launchPersistentChrome(negativeProfile);
  const page = context.pages()[0] || (await context.newPage());
  attachProductionGuard(page);

  try {
    await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: 120_000 });
    await waitLoginScreen(page);
    if (await hasQaLabel(page, 'home-ready')) {
      throw new Error('home-ready não deveria aparecer em perfil limpo');
    }
    console.log(JSON.stringify({ WEB_CLEAN_PROFILE_REQUIRES_LOGIN: true }));
    process.exit(0);
  } finally {
    await context.close();
  }
}

async function runOriginIsolation() {
  const context = await launchPersistentChrome(negativeProfile);
  const page = context.pages()[0] || (await context.newPage());
  attachProductionGuard(page);

  try {
    await page.goto(isolationOrigin, {
      waitUntil: 'domcontentloaded',
      timeout: 120_000,
    });
    await waitLoginScreen(page);
    if (await hasQaLabel(page, 'home-ready')) {
      throw new Error('home-ready não deveria herdar sessão de outro origin');
    }
    console.log(
      JSON.stringify({ WEB_AUTH_STORAGE_ORIGIN_ISOLATION_CONFIRMED: true }),
    );
    process.exit(0);
  } finally {
    await context.close();
  }
}

const runners = {
  reload: runReload,
  'clean-profile': runCleanProfile,
  'origin-isolation': runOriginIsolation,
};

const fn = runners[mode];
if (!fn) {
  console.error(`modo desconhecido: ${mode}`);
  process.exit(1);
}
fn().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
