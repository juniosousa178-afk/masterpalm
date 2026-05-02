/**
 * Validação x-signature do mpWebhook (catálogo): secret da plataforma + secrets por loja (token manual / app própria).
 */

import { validateMercadoPagoWebhookSignature } from "./mercadoPagoWebhookSignature.js";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";

/**
 * @param {import('express').Request} req
 * @param {{ platformSecret: string, db: import('firebase-admin/firestore').Firestore, collectionLojas?: string }} opts
 * @returns {Promise<{ ok: true, matched: 'platform'|'store', lojaId?: string } | { ok: false, reason: string }>}
 */
export async function verifyMpCatalogWebhookSignatureOrStoreSecrets(req, opts) {
  const { platformSecret, db, collectionLojas = COLLECTION_LOJAS } = opts;
  const plat = String(platformSecret || "").trim();
  if (plat) {
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: plat });
    if (r.ok) {
      return { ok: true, matched: "platform" };
    }
  }

  const lojasSnap = await db.collection(collectionLojas).select().get();
  for (const doc of lojasSnap.docs) {
    const paySnap = await db
      .collection(collectionLojas)
      .doc(doc.id)
      .collection("config")
      .doc("payments")
      .get();
    if (!paySnap.exists) continue;
    const mp = paySnap.data()?.mp || {};
    const sec = String(mp.webhook_secret || "").trim();
    if (sec.length < 16) continue;
    const r = validateMercadoPagoWebhookSignature({ req, webhookSecret: sec });
    if (r.ok) {
      return { ok: true, matched: "store", lojaId: doc.id };
    }
  }

  return { ok: false, reason: "webhook_signature_invalid" };
}
