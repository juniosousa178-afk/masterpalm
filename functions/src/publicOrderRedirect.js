/**
 * Links de pedido enviados pelo WhatsApp até a 1.0.140 usavam `/c/{lojaId}?pedido={pedidoId}`.
 * `/c/` é o link curto do catálogo (redirect que descarta a query), então esses links nunca
 * abriam o pedido. Aqui eles passam a abrir a página pública do pedido.
 *
 * O destino é fixo (sem open redirect) e não consulta dados: a página só lê
 * `lojas/{lojaId}/pedido_status_publico/{pedidoId}`, exigindo o par exato.
 */

export const APP_ORDER_BASE = "https://app.mastepalm.com.br";

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * @param {string} rawPath - `req.path` (ex.: `/c/nathy-pratas-e-folheados`)
 * @param {Record<string, unknown>} query - `req.query`
 * @returns {string|null} URL da página pública do pedido, ou null se não for link de pedido válido.
 */
export function legacyOrderRedirectTarget(rawPath, query) {
  const pedidoRaw = query ? query.pedido : undefined;
  if (typeof pedidoRaw !== "string") return null;
  const pedidoId = pedidoRaw.trim();
  if (!ID_PATTERN.test(pedidoId)) return null;

  const segments = String(rawPath || "").replace(/^\/c\/?/, "").split("/").filter(Boolean);
  if (segments.length !== 1) return null;
  let lojaId;
  try {
    lojaId = decodeURIComponent(segments[0]).trim();
  } catch (_) {
    return null;
  }
  if (!ID_PATTERN.test(lojaId)) return null;

  const url = new URL(`/pedido/${pedidoId}`, APP_ORDER_BASE);
  url.searchParams.set("loja", lojaId);
  return url.toString();
}
