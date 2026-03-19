/**
 * Estado persistido da conversa WhatsApp por loja + remetente (FASE 3).
 * Camada opcional: falha ou estado ausente/expirado não impede resposta.
 * Nunca lança erro que derrube o webhook.
 */

import { FieldValue } from "firebase-admin/firestore";

const TTL_MS = 24 * 60 * 60 * 1000; // 24h
const COLLECTION_NAME = "whatsapp_conversations";

/**
 * Chave do documento: remetente (número). Sanitizado para Firestore.
 * @param {string|number} from
 * @returns {string}
 */
function docIdFrom(from) {
  if (from == null) return "";
  const s = String(from).trim();
  return s.replace(/[^0-9a-zA-Z_.-]/g, "_").slice(0, 128) || "unknown";
}

/**
 * Carrega estado por lojaId + from. Retorna null se inexistente, expirado, inválido ou erro.
 * @param {function} getDb
 * @param {string} lojaId
 * @param {string} from
 * @returns {Promise<{ lastIntent: string, lastQuery?: string, lastUpdatedAt: object } | null>}
 */
export async function loadState(getDb, lojaId, from) {
  if (!lojaId || !from) return null;
  const docId = docIdFrom(from);
  if (!docId || docId === "unknown") return null;
  try {
    const db = getDb();
    const ref = db.collection("lojas").doc(lojaId).collection(COLLECTION_NAME).doc(docId);
    const snap = await ref.get();
    if (!snap.exists) return null;
    const data = snap.data();
    if (!data || typeof data !== "object") return null;
    const lastUpdatedAt = data.lastUpdatedAt;
    if (lastUpdatedAt) {
      const ts = lastUpdatedAt.toMillis ? lastUpdatedAt.toMillis() : (lastUpdatedAt.seconds || 0) * 1000;
      if (Date.now() - ts > TTL_MS) return null;
    }
    return {
      lastIntent: typeof data.lastIntent === "string" ? data.lastIntent : "",
      lastQuery: typeof data.lastQuery === "string" && data.lastQuery.trim() ? data.lastQuery.trim() : undefined,
      lastProducts: Array.isArray(data.lastProducts)
        ? data.lastProducts
            .slice(0, 5)
            .map((p) => ({
              id: typeof p?.id === "string" ? p.id : undefined,
              nome: typeof p?.nome === "string" ? p.nome : undefined,
              preco: typeof p?.preco === "number" ? p.preco : undefined,
            }))
            .filter((p) => Boolean(p.id || p.nome))
        : undefined,
      lastSelectedProduct: data.lastSelectedProduct && typeof data.lastSelectedProduct === "object"
        ? {
            id: typeof data.lastSelectedProduct.id === "string" ? data.lastSelectedProduct.id : undefined,
            nome: typeof data.lastSelectedProduct.nome === "string" ? data.lastSelectedProduct.nome : undefined,
            preco: typeof data.lastSelectedProduct.preco === "number" ? data.lastSelectedProduct.preco : undefined,
          }
        : undefined,
      lastUpdatedAt: data.lastUpdatedAt,
    };
  } catch (err) {
    console.warn("[conversationStateStore] loadState:", err?.message || err);
    return null;
  }
}

/**
 * Salva estado. Não lança; em erro apenas loga.
 * @param {function} getDb
 * @param {string} lojaId
 * @param {string} from
 * @param {{ lastIntent: string, lastQuery?: string | null }} state
 */
export async function saveState(getDb, lojaId, from, state) {
  if (!lojaId || !from) return;
  const docId = docIdFrom(from);
  if (!docId || docId === "unknown") return;
  if (!state || typeof state.lastIntent !== "string") return;
  try {
    const db = getDb();
    const ref = db.collection("lojas").doc(lojaId).collection(COLLECTION_NAME).doc(docId);
    const update = {
      lastIntent: state.lastIntent,
      lastQuery: state.lastQuery && state.lastQuery.trim() ? state.lastQuery.trim().slice(0, 120) : null,
      lastUpdatedAt: FieldValue.serverTimestamp(),
    };

    if (Array.isArray(state.lastProducts)) {
      update.lastProducts = state.lastProducts
        .slice(0, 5)
        .map((p) => ({
          id: typeof p?.id === "string" ? p.id : undefined,
          nome: typeof p?.nome === "string" ? p.nome : undefined,
          preco: typeof p?.preco === "number" ? p.preco : undefined,
        }))
        .filter((p) => Boolean(p.id || p.nome));
    }

    if (state.lastSelectedProduct && typeof state.lastSelectedProduct === "object") {
      update.lastSelectedProduct = {
        id: typeof state.lastSelectedProduct.id === "string" ? state.lastSelectedProduct.id : undefined,
        nome: typeof state.lastSelectedProduct.nome === "string" ? state.lastSelectedProduct.nome : undefined,
        preco: typeof state.lastSelectedProduct.preco === "number" ? state.lastSelectedProduct.preco : undefined,
      };
    }

    await ref.set(update, { merge: true });
  } catch (err) {
    console.warn("[conversationStateStore] saveState:", err?.message || err);
  }
}
