/** Bloqueio runtime de rede produção — Playwright (R8.4.39) */

import { BLOCKED_HOST_PATTERNS, NETWORK_ALLOWLIST, PRODUCTION_PROJECT_ID } from './constants.mjs';

let productionRequestCount = 0;

export function getProductionRequestCount() {
  return productionRequestCount;
}

function isEmulatorUrl(url) {
  const u = url.toLowerCase();
  return (
    u.includes('127.0.0.1') ||
    u.includes('localhost') ||
    u.includes(':8180') ||
    u.includes(':9199') ||
    u.includes('firebaseemulator') ||
    u.includes('/emulator/')
  );
}

function isAllowlisted(url, status) {
  for (const item of NETWORK_ALLOWLIST) {
    if (item.pattern.test(url)) {
      if (!item.statuses || item.statuses.includes(status)) return item;
    }
  }
  return null;
}

function isProductionUrl(url) {
  const u = url.toLowerCase();
  if (isEmulatorUrl(u)) return false;
  for (const p of BLOCKED_HOST_PATTERNS) {
    if (u.includes(p.toLowerCase())) return true;
  }
  if (u.includes('firebasestorage.googleapis.com') && u.includes(PRODUCTION_PROJECT_ID)) return true;
  if (u.includes('firestore.googleapis.com') && !isEmulatorUrl(u)) return true;
  if (u.includes('identitytoolkit.googleapis.com') && !isEmulatorUrl(u)) return true;
  if (u.includes('securetoken.googleapis.com')) return true;
  if (u.includes('firebaseremoteconfig.googleapis.com')) return true;
  if (u.includes('.cloudfunctions.net') && u.includes(PRODUCTION_PROJECT_ID)) return true;
  return false;
}

function maskUrl(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes(PRODUCTION_PROJECT_ID)) {
      return `${u.protocol}//[PRODUCTION_BLOCKED]${u.pathname}`;
    }
    return `${u.protocol}//${u.hostname}${u.pathname}`;
  } catch {
    return '[invalid-url]';
  }
}

export function attachProductionNetworkGuard(page, violations) {
  const handler = async (route) => {
    const url = route.request().url();
    if (isProductionUrl(url)) {
      productionRequestCount += 1;
      const masked = maskUrl(url);
      violations.push({ type: 'production_network', url, masked });
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  };

  page.route('**/*', handler);

  page.on('request', (req) => {
    const url = req.url();
    if (isProductionUrl(url)) {
      productionRequestCount += 1;
      violations.push({ type: 'production_network', url: maskUrl(url) });
    }
  });

  page.on('response', (res) => {
    const url = res.url();
    const status = res.status();
    if (status >= 400) {
      const allowed = isAllowlisted(url, status);
      if (!allowed) {
        violations.push({ type: 'http_error', url, status });
      }
    }
  });

  return () => page.unroute('**/*', handler);
}

export function assertNoProductionViolations(violations) {
  const prod = violations.filter((v) => v.type === 'production_network');
  if (prod.length > 0) {
    const msg = prod.map((v) => v.masked || v.url).join(', ');
    throw new Error(`WEB_UI_E2E_PRODUCTION_NETWORK_BLOCKED: ${msg}`);
  }
  console.log(`PRODUCTION_REQUEST_COUNT=${getProductionRequestCount()}`);
}

export function assertConsoleAndNetworkClean(violations) {
  const http = violations.filter((v) => v.type === 'http_error');
  const console = violations.filter((v) => v.type === 'console_error');
  const failed = violations.filter((v) => v.type === 'request_failed');
  if (http.length || console.length || failed.length) {
    throw new Error(
      `Console/rede não limpos: http=${http.length} console=${console.length} failed=${failed.length}`,
    );
  }
}

export function attachStrictConsoleGuard(page, violations) {
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      const text = msg.text();
      const allowed = NETWORK_ALLOWLIST.some((a) => a.pattern.test(text));
      if (!allowed) violations.push({ type: 'console_error', text });
    }
  });
  page.on('pageerror', (err) => {
    violations.push({ type: 'console_error', text: String(err) });
  });
  page.on('requestfailed', (req) => {
    const url = req.url();
    if (isProductionUrl(url)) return;
    const failure = req.failure();
    const allowed = NETWORK_ALLOWLIST.some((a) => a.pattern.test(url));
    if (!allowed) {
      violations.push({
        type: 'request_failed',
        url: maskUrl(url),
        error: failure?.errorText,
      });
    }
  });
}

export { isProductionUrl, isAllowlisted };
