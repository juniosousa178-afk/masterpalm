/**
 * Publicação da loja para cotação de frete pública.
 *
 * Só `published === false` é despublicação explícita: lojas publicadas pelo fluxo
 * atual têm `publishedAt` sem o booleano. Mesma semântica de `firestore.rules` e
 * de `assertStorePublishedForQuote` (SuperFrete).
 */
import { HttpsError } from "firebase-functions/v2/https";

export function isStoreExplicitlyUnpublished(data) {
  return data?.published === false;
}

export async function loadStoreForPublicQuote({ db, collectionLojas, storeId }) {
  const id = String(storeId ?? "").trim();
  if (!id) throw new HttpsError("invalid-argument", "Loja não informada.");
  const snap = await db.collection(collectionLojas).doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "Loja não encontrada.");
  const data = snap.data() ?? {};
  if (isStoreExplicitlyUnpublished(data)) {
    throw new HttpsError("failed-precondition", "Loja não publicada.");
  }
  return data;
}
