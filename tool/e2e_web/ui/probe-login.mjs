import { createRequire } from 'node:module';
import { serveStatic } from '../lib/serve-build.mjs';
import { ensureFlutterAccessibility, fillLoginFields, submitLogin, waitForFlutterShell, waitQaLabel } from '../lib/flutter-semantics.mjs';
import { USER_EMAIL, USER_PASSWORD, QA_SERVE_PORT } from '../lib/constants.mjs';

const require = createRequire(import.meta.url);
const build = 'C:/Users/Pichau/AppData/Local/Temp/masterpalm-r8439-web-ui-e2e/build/web-qa-e2e';
const port = Number(process.env.R8438_UI_PORT || 8810);
const server = await serveStatic(build, port);
const { chromium } = require('playwright');
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'load', timeout: 120000 });
await waitForFlutterShell(page);
await page.waitForTimeout(15000);
const snap1 = await page.locator('body').ariaSnapshot();
console.log('before login', snap1.slice(0, 1200));
await fillLoginFields(page, USER_EMAIL, USER_PASSWORD);
await submitLogin(page);
try {
  await waitQaLabel(page, 'home-ready', { timeout: 180000 });
  console.log('HOME READY OK');
} catch (e) {
  console.error('FAIL', e.message);
}
await browser.close();
server.close();
