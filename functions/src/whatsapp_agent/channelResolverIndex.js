/**
 * Resolução de loja por phone_number_id (WhatsApp) sem varredura em todas as lojas.
 * Usa collectionGroup em canais com filtro phone_number_id + enabled.
 * Requer índice Firestore: collection group "canais", campos phone_number_id (Asc), enabled (Asc).
 * Em caso de falha (índice ausente ou erro), o caller deve usar fallback findLojaByChannel.
 * Lote 1.
 */

/**
 * Resolve loja e config WhatsApp pelo phone_number_id.
 * @param {function} getDb - função que retorna instância Firestore (ex.: getDb do webhook)
 * @param {string} phoneNumberId - metadata.phone_number_id do webhook
 * @returns {Promise<{ lojaId: string, config: object } | null>}
 */
export async function resolveWhatsAppStoreByPhoneNumberId(getDb, phoneNumberId) {
  if (typeof phoneNumberId !== "string" || !phoneNumberId.trim()) {
    return null;
  }
  const id = phoneNumberId.trim();
  try {
    const db = getDb();
    const snapshot = await db
      .collectionGroup("canais")
      .where("phone_number_id", "==", id)
      .where("enabled", "==", true)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return null;
    }
    const doc = snapshot.docs[0];
    const lojaId = doc.ref.parent.parent?.id;
    if (!lojaId) {
      return null;
    }
    const data = doc.data();
    if (doc.id !== "whatsapp") {
      return null;
    }
    return { lojaId, config: data };
  } catch (err) {
    console.warn("[channelResolverIndex] fallback por erro:", err?.message || err);
    return null;
  }
}
