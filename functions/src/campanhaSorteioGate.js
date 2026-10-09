/**
 * Gate autoritativo de campanha de sorteio (mesma regra do app:
 * lib/services/campanha_sorteio_gate.dart).
 *
 * Elegível: mesma loja, ativa === true, status aberta/ativa (ou ausente),
 * não excluída, dataInicio e dataFim obrigatórias, dataInicio <= agora <= dataFim.
 * Exatamente UMA elegível ⇒ sorteio; 0 ou >1 ⇒ sem sorteio.
 */

export const STATUS_PERMITIDOS = new Set(["aberta", "ativa", "active"]);

function asDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  if (typeof v === "string" && v.trim()) {
    const d = new Date(v.trim());
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function excluida(data) {
  return (
    data.excluida === true ||
    data.deleted === true ||
    data.isDeleted === true ||
    data.deletedAt != null ||
    data.excluidaEm != null
  );
}

export function campanhaElegivel(data, { lojaId, agora }) {
  if (!data || typeof data !== "object") return false;
  const lojaDoc = String(data.lojaId ?? "").trim();
  if (lojaDoc && lojaDoc !== String(lojaId).trim()) return false;
  if (data.ativa !== true) return false;
  if (data.status != null) {
    const s = String(data.status).trim().toLowerCase();
    if (!STATUS_PERMITIDOS.has(s)) return false;
  }
  if (excluida(data)) return false;
  const inicio = asDate(data.dataInicio);
  const fim = asDate(data.dataFim);
  if (!inicio || !fim) return false;
  return agora >= inicio && agora <= fim;
}

/**
 * @param {{id: string, data: object, ref?: any}[]} campanhas
 * @returns {{status: "ativa"|"nenhuma"|"ambigua", campanha?: {id: string, data: object, ref?: any}}}
 */
export function avaliarCampanhas(campanhas, { lojaId, agora }) {
  const elegiveis = campanhas.filter((c) => campanhaElegivel(c.data, { lojaId, agora }));
  if (elegiveis.length === 0) return { status: "nenhuma" };
  if (elegiveis.length > 1) return { status: "ambigua" };
  return { status: "ativa", campanha: elegiveis[0] };
}

/** Lê campanhas da loja e aplica o gate. Erro de leitura propaga (caller ⇒ sem sorteio). */
export async function resolverCampanhaAtiva(db, { colLojas = "lojas", lojaId, agora = new Date() }) {
  const snap = await db
    .collection(colLojas)
    .doc(String(lojaId))
    .collection("campanhas_sorteio")
    .limit(100)
    .get();
  const docs = snap.docs.map((d) => ({ id: d.id, data: d.data() || {}, ref: d.ref }));
  return avaliarCampanhas(docs, { lojaId, agora });
}
