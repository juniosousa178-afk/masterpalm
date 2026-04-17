/**
 * Política de token MP **da loja** (config/payments) em fluxos pedido/catálogo.
 * Não valida contra a API do MP (custo/latência); evita strings curtas que passavam em length>10
 * e impede fallback silencioso para MP_ACCESS_TOKEN global do projeto nesses fluxos.
 */

/** Formato típico de access token de produção MP. */
export function isAcceptableLojaMpAccessToken(raw) {
  const t = String(raw ?? "").trim();
  if (!t) return false;
  if (t.startsWith("APP_USR-")) {
    return t.length >= 24;
  }
  return t.length >= 48;
}

/**
 * Resolve token estrito para fluxos loja/pedido/catálogo — **sem** fallback global.
 * @param {{ token?: string|null }} lojaCfg — ex.: retorno de getLojaPaymentConfig
 * @returns {{ ok: true, token: string } | { ok: false, reason: 'missing'|'invalid_format', tokenLen: number }}
 */
export function resolveStrictLojaMpAccessToken(lojaCfg) {
  const t = String(lojaCfg?.token ?? "").trim();
  if (!t) {
    return { ok: false, reason: "missing", tokenLen: 0 };
  }
  if (!isAcceptableLojaMpAccessToken(t)) {
    return { ok: false, reason: "invalid_format", tokenLen: t.length };
  }
  return { ok: true, token: t };
}
