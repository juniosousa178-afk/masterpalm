/**
 * Destinos do link curto do catálogo (`/c/{short}` → `/loja/{slug}`) usados por redirectCatalogo.
 *
 * A base vem de WEB_BASE_URL (secret); só é aceita uma origem HTTPS, senão cai no app canônico.
 * O slug vem do índice/Firestore (nunca da URL) e é codificado como um único segmento de path.
 */

export const CATALOG_SHORTCUT_DEFAULT_BASE = "https://app.mastepalm.com.br";

/**
 * @param {unknown} raw - valor de WEB_BASE_URL
 * @returns {string} origem HTTPS sem barra final
 */
export function catalogShortcutBase(raw) {
  if (typeof raw !== "string" || !raw.trim()) return CATALOG_SHORTCUT_DEFAULT_BASE;
  let url;
  try {
    url = new URL(raw.trim());
  } catch (_) {
    return CATALOG_SHORTCUT_DEFAULT_BASE;
  }
  if (url.protocol !== "https:" || url.username || url.password) {
    return CATALOG_SHORTCUT_DEFAULT_BASE;
  }
  return url.origin;
}

/** Chave de busca no índice a partir de `req.path` (`/c/MinhaLoja` → `minhaloja`). */
export function catalogShortcutKey(rawPath) {
  return (String(rawPath || "").replace(/^\/c\/?/, "") || "").trim().toLowerCase();
}

export function catalogShortcutStoreUrl(base, slug) {
  return `${base}/loja/${encodeURIComponent(String(slug))}`;
}

export function catalogShortcutRootUrl(base) {
  return `${base}/`;
}
