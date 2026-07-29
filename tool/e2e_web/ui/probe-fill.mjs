import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { QA_BUILD_DIR, QA_SERVE_PORT, USER_EMAIL, USER_PASSWORD } from '../lib/constants.mjs';
import { ensureFlutterAccessibility, fillLoginFields, submitLogin, waitForQaBootstrap } from '../lib/flutter-semantics.mjs';
import { serveStatic } from '../lib/serve-build.mjs';

const require = createRequire(import.meta.url);
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

async function signInDirect() {
  const res = await fetch(
    'http://127.0.0.1:9199/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: USER_EMAIL, password: USER_PASSWORD, returnSecureToken: true }),
    },
  );
  return res.json();
}

async function main() {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';
  const server = await serveStatic(path.resolve(repoRoot, QA_BUILD_DIR), QA_SERVE_PORT);
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
  page.on('console', (msg) => {
    if (msg.text().includes('LOGIN')) console.log('PAGE:', msg.text());
  });
  await page.goto(`http://127.0.0.1:${QA_SERVE_PORT}/login`);
  await waitForQaBootstrap(page);
  await fillLoginFields(page, USER_EMAIL, USER_PASSWORD, { skipBootstrap: true });
  const text = await page.locator('input[type="text"]').first().inputValue();
  const pass = await page.locator('input[type="password"]').first().inputValue();
  console.log('dom', { text, pass });
  await submitLogin(page);
  await page.waitForTimeout(20000);
  console.log('url', page.url());
  console.log('labels', (await page.locator('body').ariaSnapshot()).slice(0, 600));
  console.log('direct signin', await signInDirect());
  await browser.close();
  server.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
