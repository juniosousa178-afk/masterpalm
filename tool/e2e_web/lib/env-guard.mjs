/** Bloqueio de rede produção — Playwright (R8.4.38) */

import { BLOCKED_HOST_PATTERNS } from './constants.mjs';

export function attachProductionNetworkGuard(page, violations) {
  const onRequest = (req) => {
    const url = req.url().toLowerCase();
    for (const p of BLOCKED_HOST_PATTERNS) {
      if (url.includes(p.toLowerCase())) {
        violations.push({ type: 'production_network', url: req.url() });
      }
    }
  };
  page.on('request', onRequest);
  return () => page.off('request', onRequest);
}

export function assertNoProductionViolations(violations) {
  const prod = violations.filter((v) => v.type === 'production_network');
  if (prod.length > 0) {
    const msg = prod.map((v) => v.url).join(', ');
    throw new Error(`WEB_UI_E2E_PRODUCTION_NETWORK_BLOCKED: ${msg}`);
  }
}
