/**
 * Resolvedor de referência implícita (sem IA).
 * Usa state.lastProducts (FASE 4) para mapear:
 * - "o primeiro"  -> lastProducts[0]
 * - "o segundo"   -> lastProducts[1]
 * - "essa/esse"   -> lastProducts[0]
 *
 * Não lança erro; quando não resolve, retorna resolved=false.
 */

function normalizeText(text) {
  return String(text || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

/**
 * @param {string} messageText
 * @param {{ lastProducts?: Array<{id?:string, nome?:string, preco?:number}> }} state
 * @returns {{ resolved: boolean, product?: object, rewrittenQuery?: string }}
 */
export function resolveImplicitReference(messageText, state) {
  try {
    const lastProducts = state?.lastProducts;
    if (!Array.isArray(lastProducts) || lastProducts.length === 0) {
      return { resolved: false };
    }

    const text = normalizeText(messageText);

    // Prioridade: ordinal ("o primeiro", "o segundo")
    let idx = null;
    if (/\bo\s*primeiro\b/.test(text) || /\bprimeiro\b/.test(text)) {
      idx = 0;
    } else if (/\bo\s*segundo\b/.test(text) || /\bsegundo\b/.test(text)) {
      idx = 1;
    } else {
      // "essa/esse/esse ai/aí" e variações simples
      // Ex.: "quero essa", "quero esse ai", "me manda esse", "esse produto"
      if (/\bessa\b/.test(text) || /\besse\b/.test(text)) {
        idx = 0;
      }
      if (/\bme\s+manda\s+esse\b/.test(text) || /\bmanda\s+esse\b/.test(text)) {
        idx = 0;
      }
      if (/\besse\s+ai\b/.test(text)) {
        idx = 0;
      }
    }

    if (idx == null) return { resolved: false };
    if (idx < 0 || idx >= lastProducts.length) return { resolved: false };

    const product = lastProducts[idx] || lastProducts[0];
    if (!product) return { resolved: false };

    const rewrittenQuery = (product?.nome || product?.id || "").toString().trim();
    if (!rewrittenQuery) return { resolved: false };

    return { resolved: true, product, rewrittenQuery };
  } catch (e) {
    return { resolved: false };
  }
}

