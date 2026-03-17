/**
 * Índice order_loja_index: resolução orderId → lojaId sem iterar todas as lojas.
 * Coleção: order_loja_index (top-level). Doc ID = orderId. Campos: lojaId, origem, criadoEm.
 * Uso: findLojaIdByOrderId / resolveLojaIdByOrderId (fallback: varre pedidos e pre_pedidos por loja).
 */

import { FieldValue } from "firebase-admin/firestore";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const ORDER_LOJA_INDEX = "order_loja_index";

/**
 * Escreve entrada no índice (pedido → loja). Idempotente.
 */
export async function writeOrderLojaIndex(db, orderId, lojaId, origem = "pedidos") {
  if (!orderId || !lojaId) return;
  const ref = db.collection(ORDER_LOJA_INDEX).doc(String(orderId));
  await ref.set(
    {
      lojaId: String(lojaId),
      origem: origem === "pre_pedidos" ? "pre_pedidos" : "pedidos",
      criadoEm: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Lê lojaId do índice. Retorna null se não existir.
 */
export async function readOrderLojaIndex(db, orderId) {
  if (!orderId) return null;
  const snap = await db.collection(ORDER_LOJA_INDEX).doc(String(orderId)).get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  return d.lojaId || null;
}

/**
 * Resolve lojaId por orderId: primeiro consulta o índice; se não achar, varre
 * lojas/pedidos e lojas/pre_pedidos (fallback) e, ao encontrar, grava no índice.
 */
export async function resolveLojaIdByOrderId(db, orderId) {
  const cached = await readOrderLojaIndex(db, orderId);
  if (cached) return cached;

  const lojasSnap = await db.collection(COLLECTION_LOJAS).select().get();
  for (const l of lojasSnap.docs) {
    const ord = await db
      .collection(COLLECTION_LOJAS)
      .doc(l.id)
      .collection("pedidos")
      .doc(orderId)
      .get();
    if (ord.exists) {
      await writeOrderLojaIndex(db, orderId, l.id, "pedidos");
      return l.id;
    }
  }
  for (const l of lojasSnap.docs) {
    const preOrd = await db
      .collection(COLLECTION_LOJAS)
      .doc(l.id)
      .collection("pre_pedidos")
      .doc(orderId)
      .get();
    if (preOrd.exists) {
      await writeOrderLojaIndex(db, orderId, l.id, "pre_pedidos");
      return l.id;
    }
  }
  return null;
}
