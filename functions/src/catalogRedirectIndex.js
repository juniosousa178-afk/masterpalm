/**
 * Índice catalog_redirect_index: resolução short (linkCurto/slug) → loja/slug sem iterar todas as lojas.
 * Coleção: catalog_redirect_index (top-level). Doc ID = short normalizado (lowercase). Campos: lojaId, slug.
 * Uso: redirectCatalogo (/c/:short → /loja/:slug).
 */

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const CATALOG_REDIRECT_INDEX = "catalog_redirect_index";

function normalizeShort(s) {
  return (s || "").toString().trim().toLowerCase();
}

/**
 * Retorna { lojaId, slug } para o short dado, ou null se não existir no índice.
 */
export async function getRedirectTarget(db, short) {
  const key = normalizeShort(short);
  if (!key) return null;
  const snap = await db.collection(CATALOG_REDIRECT_INDEX).doc(key).get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  return { lojaId: d.lojaId || null, slug: (d.slug || "").toString().trim() || null };
}

/**
 * Sincroniza um documento de loja no índice: escreve entradas para linkCurto e slug
 * (ambos como doc ID normalizado) apontando para { lojaId, slug }.
 */
export async function syncCatalogRedirectIndex(db, lojaId, lojaData = {}) {
  const slug = (lojaData.slug || lojaId || "").toString().trim();
  const linkCurto = (lojaData.linkCurto || "").toString().trim();
  const slugDisplay = slug || lojaId;

  const batch = db.batch();
  const keyLink = normalizeShort(linkCurto);
  const keySlug = normalizeShort(slug);
  const payload = { lojaId: String(lojaId), slug: slugDisplay };

  if (keyLink) {
    batch.set(db.collection(CATALOG_REDIRECT_INDEX).doc(keyLink), payload, { merge: true });
  }
  if (keySlug && keySlug !== keyLink) {
    batch.set(db.collection(CATALOG_REDIRECT_INDEX).doc(keySlug), payload, { merge: true });
  }
  if (keyLink || keySlug) {
    await batch.commit();
  }
}
