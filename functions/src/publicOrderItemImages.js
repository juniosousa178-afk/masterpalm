/**
 * Foto de cada item no espelho público do pedido (`lojas/{lojaId}/pedido_status_publico`).
 *
 * O pré-pedido é gravado pelo catálogo (cliente anônimo), então a imagem que vem do carrinho
 * não é confiável. A imagem publicada vem do produto publicado da mesma loja
 * (`lojas/{lojaId}/produtos/{productId}`, já público): a do carrinho só é aceita se for uma
 * das imagens desse produto; senão usa a capa do catálogo.
 *
 * É um snapshot: só é obtida enquanto o pedido é novo. Depois é copiada do espelho existente,
 * então editar ou apagar o produto não muda o pedido, e pedidos antigos continuam sem foto.
 */

export const PUBLIC_ORDER_ITEM_IMAGE_FIELD = "imagem";
export const PUBLIC_ORDER_ITEM_FIELDS = Object.freeze(["nome", "quantidade", PUBLIC_ORDER_ITEM_IMAGE_FIELD]);
export const PUBLIC_ORDER_IMAGE_DERIVATION_WINDOW_MS = 15 * 60 * 1000;

const MAX_IMAGE_URL_LENGTH = 2048;
const MAX_ITEMS = 50;
const MAX_PRODUCT_ID_LENGTH = 200;
const UNSAFE_URL_CHARS = /[\s"'<>\\`\u0000-\u001f\u007f]/;

/** URL https absoluta, sem credenciais nem caracteres de escape; senão "". */
export function sanitizePublicOrderImageUrl(value) {
  if (typeof value !== "string") return "";
  const url = value.trim();
  if (!url || url.length > MAX_IMAGE_URL_LENGTH || UNSAFE_URL_CHARS.test(url)) return "";
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return "";
  }
  if (parsed.protocol !== "https:" || !parsed.hostname || parsed.username || parsed.password) return "";
  return url;
}

/** ID de documento utilizável num único segmento de path (sem `/`, `.`/`..` ou `__x__`). */
export function isSafeProductDocId(value) {
  if (typeof value !== "string") return false;
  const id = value.trim();
  return id.length > 0
    && id.length <= MAX_PRODUCT_ID_LENGTH
    && id === value
    && !id.includes("/")
    && id !== "."
    && id !== ".."
    && !/^__.*__$/.test(id);
}

function looksLikeGeneratedThumbnail(url) {
  return url.toLowerCase().replaceAll("%2f", "/").replaceAll("%5c", "/").includes("/thumbnails/");
}

/**
 * Imagens do produto como o catálogo público as monta: `imagens` (ordem do cadastro) e
 * `imagem_principal ?? imageUrl`. A capa é a primeira de `imagens` que não seja thumbnail
 * gerada; sem lista, a principal.
 */
export function catalogProductImages(product) {
  const p = product && typeof product === "object" ? product : {};
  const imagens = Array.isArray(p.imagens)
    ? p.imagens.map((v) => (typeof v === "string" ? v.trim() : "")).filter(Boolean)
    : [];
  const principalRaw = p.imagem_principal ?? p.imageUrl ?? "";
  let principal = typeof principalRaw === "string" ? principalRaw.trim() : "";
  if (!principal && imagens.length > 0) principal = imagens[0];
  const lista = imagens.length > 0 ? imagens : principal ? [principal] : [];

  let cover = lista.find((u) => !looksLikeGeneratedThumbnail(u)) || lista[0] || "";
  if (!cover) cover = principal;

  const all = new Set([...lista, principal].filter(Boolean));
  return {cover, all};
}

/** Mesmo filtro de `buildPedidoStatusPublico`: só itens com nome entram em `itensResumo`. */
function publicItemSources(itens) {
  if (!Array.isArray(itens)) return [];
  return itens
    .map((item) => ({
      nome: item?.nome == null ? "" : String(item.nome).trim(),
      productId: item?.productId ?? item?.id ?? item?.produtosId,
      cartImage: item?.imagemSnapshot || item?.imagem || "",
    }))
    .filter((item) => item.nome.length > 0);
}

function pickTrustedImage(product, cartImage) {
  if (!product) return "";
  const {cover, all} = catalogProductImages(product);
  const fromCart = sanitizePublicOrderImageUrl(cartImage);
  if (fromCart && all.has(fromCart)) return fromCart;
  return sanitizePublicOrderImageUrl(cover);
}

function withImage(resumo, imagem) {
  const item = {nome: resumo.nome, quantidade: resumo.quantidade};
  if (imagem) item[PUBLIC_ORDER_ITEM_IMAGE_FIELD] = imagem;
  return item;
}

export function isOrderWithinImageWindow(dataCriacao, nowMs) {
  const createdMs = typeof dataCriacao?.toMillis === "function" ? dataCriacao.toMillis() : NaN;
  if (!Number.isFinite(createdMs)) return false;
  return nowMs - createdMs <= PUBLIC_ORDER_IMAGE_DERIVATION_WINDOW_MS;
}

/**
 * @param {object} args
 * @param {Array<{nome: string, quantidade: number}>} args.itensResumo - saída de `buildPedidoStatusPublico`
 * @param {Array<object>} args.itens - itens do pré-pedido
 * @param {Array<object>} [args.previousItensResumo] - `itensResumo` do espelho atual
 * @param {boolean} args.allowDerivation - pedido ainda é novo
 * @param {(ids: string[]) => Promise<Map<string, object>>} args.loadProducts - produtos publicados da loja do pedido
 * @returns {Promise<Array<object>>} itens com apenas `nome`, `quantidade` e, se houver, `imagem`
 */
export async function resolvePublicOrderItemImages({
  itensResumo,
  itens,
  previousItensResumo,
  allowDerivation,
  loadProducts,
}) {
  const resumo = Array.isArray(itensResumo) ? itensResumo : [];
  const sources = publicItemSources(itens);
  const aligned = resumo.length <= MAX_ITEMS
    && sources.length === resumo.length
    && sources.every((s, i) => s.nome === resumo[i]?.nome);
  if (!aligned) return resumo.map((r) => withImage(r, ""));

  const previous = Array.isArray(previousItensResumo) ? previousItensResumo : [];
  const images = resumo.map((r, i) => {
    const prev = previous[i];
    if (!prev || typeof prev !== "object") return "";
    if ((prev.nome == null ? "" : String(prev.nome).trim()) !== r.nome) return "";
    return sanitizePublicOrderImageUrl(prev[PUBLIC_ORDER_ITEM_IMAGE_FIELD]);
  });

  if (allowDerivation) {
    const pending = sources
      .map((s, i) => ({...s, i}))
      .filter((s) => !images[s.i] && isSafeProductDocId(s.productId));
    if (pending.length > 0) {
      const products = await loadProducts([...new Set(pending.map((s) => s.productId))]);
      for (const s of pending) {
        images[s.i] = pickTrustedImage(products.get(s.productId), s.cartImage);
      }
    }
  }

  return resumo.map((r, i) => withImage(r, images[i]));
}

/** Lê só `lojas/{lojaId}/produtos/{id}` da própria loja do pedido. */
export function publicCatalogProductLoader(db, lojaId) {
  return async (ids) => {
    const safe = ids.filter(isSafeProductDocId);
    const out = new Map();
    if (safe.length === 0) return out;
    const col = db.collection("lojas").doc(lojaId).collection("produtos");
    const snaps = await db.getAll(...safe.map((id) => col.doc(id)));
    for (const snap of snaps) {
      if (snap.exists) out.set(snap.id, snap.data() || {});
    }
    return out;
  };
}

/**
 * Itens do espelho com foto; em qualquer falha devolve os itens sem foto (a foto nunca
 * bloqueia o espelho).
 */
export async function withPublicOrderItemImages(db, {
  lojaId,
  pedidoData,
  itensResumo,
  mirrorRef,
  isNewOrder,
  nowMs = Date.now(),
}) {
  try {
    const current = await mirrorRef.get();
    const previousItensResumo = current.exists ? current.data()?.itensResumo : undefined;
    return await resolvePublicOrderItemImages({
      itensResumo,
      itens: pedidoData?.itens,
      previousItensResumo,
      allowDerivation: isNewOrder || isOrderWithinImageWindow(pedidoData?.dataCriacao, nowMs),
      loadProducts: publicCatalogProductLoader(db, lojaId),
    });
  } catch (e) {
    console.warn("[syncPedidoStatusPublico] imagens dos itens indisponíveis:", e?.code || e?.name || "erro");
    return (Array.isArray(itensResumo) ? itensResumo : []).map((r) => withImage(r, ""));
  }
}
