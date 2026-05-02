/**
 * Fase 0 — modelo oficial Mercado Pago do catálogo público (multi-loja).
 *
 * - OAuth central (app MasterPalm): mp_connection_kind = oauth, catalog_token_validated = true no callback.
 * - Token manual (app própria do lojista): mp_connection_kind = manual, exige webhook_secret por loja
 *   para o mpWebhook validar x-signature, e catalog_token_validated após validação remota real no app.
 *
 * Planos MasterPalm: fluxo separado (planWebhook + token plataforma) — não usar este módulo lá.
 */

export const MP_CONN_OAUTH = "oauth";
export const MP_CONN_MANUAL = "manual";

/** @param {Record<string, unknown>} paymentsRaw — doc lojas/.../config/payments */
export function inferMpConnectionKind(paymentsRaw) {
  const mp = paymentsRaw && typeof paymentsRaw.mp === "object" ? paymentsRaw.mp : {};
  const explicit = String(mp.mp_connection_kind || "").trim().toLowerCase();
  if (explicit === MP_CONN_OAUTH) return MP_CONN_OAUTH;
  if (explicit === MP_CONN_MANUAL) return MP_CONN_MANUAL;
  const rt = mp.refresh_token;
  if (rt != null && String(rt).trim().length > 0) return MP_CONN_OAUTH;
  return MP_CONN_MANUAL;
}

/**
 * Política para mpCatalogPayment / createPreference (pedido catálogo).
 * @param {Record<string, unknown>} paymentsRaw
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {{ ok: true, catalogKind: 'catalog_oauth_payment'|'catalog_manual_token_payment' } | { ok: false, code: string, reason: string }}
 */
export function assertCatalogMpPaymentAllowed(paymentsRaw, env = process.env) {
  const mode = String(env.CATALOG_MP_MODE || "dual").trim().toLowerCase();
  const kind = inferMpConnectionKind(paymentsRaw || {});
  const mp = paymentsRaw && typeof paymentsRaw.mp === "object" ? paymentsRaw.mp : {};

  if (mode === "oauth_only" && kind !== MP_CONN_OAUTH) {
    return {
      ok: false,
      code: "CATALOG_MP_OAUTH_ONLY",
      reason: "oauth_only_mode_requires_oauth_connection",
    };
  }

  if (kind === MP_CONN_OAUTH) {
    const hasRefresh = mp.refresh_token != null && String(mp.refresh_token).trim().length > 0;
    const validated = mp.catalog_token_validated === true || hasRefresh;
    if (!validated) {
      return {
        ok: false,
        code: "CATALOG_MP_OAUTH_INCOMPLETE",
        reason: "oauth_missing_validation_or_refresh",
      };
    }
    return { ok: true, catalogKind: "catalog_oauth_payment" };
  }

  const ws = String(mp.webhook_secret || "").trim();
  if (ws.length < 16) {
    return {
      ok: false,
      code: "CATALOG_MP_WEBHOOK_SECRET_REQUIRED",
      reason: "webhook_store_secret_missing",
    };
  }

  if (mp.catalog_token_validated !== true) {
    return {
      ok: false,
      code: "CATALOG_MP_MANUAL_TOKEN_UNVALIDATED",
      reason: "manual_token_not_remotely_validated",
    };
  }

  return { ok: true, catalogKind: "catalog_manual_token_payment" };
}
