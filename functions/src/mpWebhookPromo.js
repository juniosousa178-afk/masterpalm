/**
 * Pós-pagamento promocional (campanha + número da sorte) para pedidos MP.
 *
 * FONTE OFICIAL (catálogo Mercado Pago): este módulo, chamado a partir de
 * processMpWebhook após pagamento aprovado + transação de estoque concluída.
 *
 * Idempotência: coleção _mp_webhook_promo_processed/{paymentId}
 * — claim atômico via create(); reentregas não duplicam participantes.
 *
 * Compatibilidade: schema de participantes alinhado a SorteioNumeroService /
 * CampaignEngine (numeroSorte 5 dígitos, pedidoId, clienteEmail, etc.).
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
export const PROMO_PROCESSED_COL = "_mp_webhook_promo_processed";

function logPromo(tag, msg, extra = {}) {
  console.log(`[PROMO-WEBHOOK] ${tag}`, msg, Object.keys(extra).length ? extra : "");
}

/** Estados finais já gravados — não reprocessar. */
function isTerminalPromoStatus(st) {
  return st === "done" || st === "no_active_campaign" || st === "skipped_no_new_participation";
}

/** Firestore: documento já existe (create em doc existente). */
function isAlreadyExistsError(e) {
  return !!(e && (e.code === 6 || e.code === "already-exists"));
}

function gerarNumeroSorte5() {
  return String(Math.floor(10000 + Math.random() * 90000));
}

/**
 * Carrega o documento do pedido em pre_pedidos, pedidos ou pedidos_pendentes.
 * @returns {{ ref: import("firebase-admin/firestore").DocumentReference, data: object } | null}
 */
export async function carregarPedidoParaPromo(db, lojaId, orderId) {
  const lid = String(lojaId);
  const oid = String(orderId);
  const base = db.collection(COLLECTION_LOJAS).doc(lid);

  const pre = await base.collection("pre_pedidos").doc(oid).get();
  if (pre.exists) return { ref: pre.ref, data: pre.data() || {} };

  const ped = await base.collection("pedidos").doc(oid).get();
  if (ped.exists) return { ref: ped.ref, data: ped.data() || {} };

  const pend = await base.collection("pedidos_pendentes").doc(oid).get();
  if (pend.exists) return { ref: pend.ref, data: pend.data() || {} };

  return null;
}

async function gerarNumeroUnico5Digitos(db, lojaId, campanhaId) {
  const partCol = db
    .collection(COLLECTION_LOJAS)
    .doc(String(lojaId))
    .collection("campanhas_sorteio")
    .doc(campanhaId)
    .collection("participantes");

  for (let t = 0; t < 35; t++) {
    const n = gerarNumeroSorte5();
    const q = await partCol.where("numeroSorte", "==", n).limit(1).get();
    if (q.empty) return n;
  }
  return String(Date.now() % 90000 + 10000);
}

/**
 * Registra participação em campanhas ativas + espelha numeroSorte no pedido.
 * Idempotente por paymentId (documento _mp_webhook_promo_processed).
 */
export async function registrarPromocaoPosPagamentoMp(db, { lojaId, orderId, paymentId, orderData, orderRef }) {
  const paymentKey = String(paymentId);
  const promoRef = db.collection(PROMO_PROCESSED_COL).doc(paymentKey);

  if (!lojaId || !orderId) {
    console.warn("[PROMO-SKIP] lojaId ou orderId ausente", { lojaId, orderId });
    return { ok: false, reason: "missing_ids" };
  }

  let ownLock = false;

  try {
    try {
      await promoRef.create({
        status: "processing",
        lojaId: String(lojaId),
        orderId: String(orderId),
        paymentId: paymentKey,
        lockAt: FieldValue.serverTimestamp(),
      });
      ownLock = true;
      logPromo("[PROMO-LOCK]", "acquired", { paymentId: paymentKey });
    } catch (e) {
      if (!isAlreadyExistsError(e)) throw e;
      const snap = await promoRef.get();
      const st = snap.exists ? snap.data()?.status : null;
      if (isTerminalPromoStatus(st)) {
        logPromo("[PROMO-IDEMPOTENTE]", "estado terminal existente", { paymentId: paymentKey, status: st });
        return { ok: true, skipped: true };
      }
      console.log("[PROMO-IDEMPOTENTE] lock já retido (outra instância ou retry em curso)", {
        paymentId: paymentKey,
        status: st,
      });
      return { ok: true, skipped: true };
    }

  const valor = Number(orderData.total ?? orderData.totalPedido ?? 0);
  const cliente = orderData.cliente || {};
  const clienteNome = String(cliente.nome || cliente.name || "Cliente").trim() || "Cliente";
  const clienteIdRaw = cliente.id || cliente.clienteId;
  const clienteId = clienteIdRaw != null && String(clienteIdRaw).trim() !== "" ? String(clienteIdRaw).trim() : null;
  const emailRaw = String(cliente.email || "").trim();
  const clienteEmail = emailRaw ? emailRaw.toLowerCase() : null;
  const clienteTelefone = String(cliente.telefone || cliente.phone || "").trim() || null;

  const agora = new Date();
  const campanhasSnap = await db
    .collection(COLLECTION_LOJAS)
    .doc(String(lojaId))
    .collection("campanhas_sorteio")
    .where("ativa", "==", true)
    .where("dataInicio", "<=", agora)
    .where("dataFim", ">=", agora)
    .get();

  if (campanhasSnap.empty) {
    logPromo("[PROMO-SKIP]", "nenhuma campanha ativa no período", { lojaId });
    await promoRef.set(
      {
        lojaId: String(lojaId),
        orderId: String(orderId),
        paymentId: paymentKey,
        processedAt: FieldValue.serverTimestamp(),
        status: "no_active_campaign",
      },
      { merge: true }
    );
    return { ok: true, skipped: false, campaigns: 0 };
  }

  const tsCompra = Timestamp.fromDate(agora);
  const batch = db.batch();
  let primeiroNumero = null;
  let escritas = 0;

  for (const campDoc of campanhasSnap.docs) {
    const cdata = campDoc.data() || {};
    const valorMinimo = Number(cdata.valorMinimo ?? cdata.valor_minimo ?? 0);
    if (valor < valorMinimo) {
      logPromo("[PROMO-SKIP]", "valor abaixo do mínimo da campanha", { campanhaId: campDoc.id, valor, valorMinimo });
      continue;
    }

    const dupP = await campDoc.ref.collection("participantes").where("pedidoId", "==", orderId).limit(1).get();
    if (!dupP.empty) {
      logPromo("[PROMO-IDEMPOTENTE]", "pedidoId já participa (pedidoId)", { campanhaId: campDoc.id, orderId });
      continue;
    }
    const dupV = await campDoc.ref.collection("participantes").where("vendaId", "==", orderId).limit(1).get();
    if (!dupV.empty) {
      logPromo("[PROMO-IDEMPOTENTE]", "orderId já em vendaId", { campanhaId: campDoc.id, orderId });
      continue;
    }

    const numeroSorte = await gerarNumeroUnico5Digitos(db, lojaId, campDoc.id);
    if (primeiroNumero == null) primeiroNumero = numeroSorte;

    const partRef = campDoc.ref.collection("participantes").doc();
    batch.set(partRef, {
      clienteId,
      clienteNome,
      nomeCliente: clienteNome,
      clienteEmail,
      clienteTelefone,
      valorCompra: valor,
      valorPedido: valor,
      dataCompra: tsCompra,
      dataParticipacao: FieldValue.serverTimestamp(),
      numeroSorte,
      criadoEm: FieldValue.serverTimestamp(),
      pedidoId: String(orderId),
      vendaId: String(orderId),
      sorteado: false,
      status: "valido",
      origem: "mp_webhook_promo",
      paymentId: paymentKey,
    });
    escritas++;
  }

  if (escritas === 0) {
    logPromo("[PROMO-SKIP]", "nenhuma escrita nova (mínimo ou pedidoId já em participantes)", {
      orderId,
    });
    await promoRef.set(
      {
        lojaId: String(lojaId),
        orderId: String(orderId),
        paymentId: paymentKey,
        processedAt: FieldValue.serverTimestamp(),
        status: "skipped_no_new_participation",
      },
      { merge: true }
    );
    return { ok: true, skipped: false, campaigns: 0 };
  }

  if (orderRef && primeiroNumero) {
    batch.set(
      orderRef,
      {
        numeroSorte: primeiroNumero,
        promoCampanhaRegistradoEm: FieldValue.serverTimestamp(),
        promoPaymentId: paymentKey,
      },
      { merge: true }
    );
  }

  batch.set(promoRef, {
    lojaId: String(lojaId),
    orderId: String(orderId),
    paymentId: paymentKey,
    processedAt: FieldValue.serverTimestamp(),
    status: "done",
    participantesEscritos: escritas,
    numeroSorteEspelho: primeiroNumero,
  });

    await batch.commit();
    logPromo("[PROMO-WEBHOOK]", "ok", { paymentId: paymentKey, orderId, escritas });
    return { ok: true, skipped: false, campaigns: escritas };
  } catch (e) {
    console.error("[PROMO-ERROR]", e && e.message, e);
    if (ownLock) {
      try {
        await promoRef.delete();
        logPromo("[PROMO-LOCK]", "released after error (retry permitido)", { paymentId: paymentKey });
      } catch (delErr) {
        console.error("[PROMO-ERROR] falha ao liberar lock", delErr && delErr.message);
      }
    }
    return { ok: false, error: String(e && e.message) };
  }
}

/**
 * Recuperação: paymentId já em _mp_webhook_processed mas promo pode não ter rodado.
 */
export async function registrarPromocaoPosPagamentoMpRecovery(db, { lojaId, orderId, paymentId }) {
  const loaded = await carregarPedidoParaPromo(db, lojaId, orderId);
  if (!loaded) {
    console.warn("[PROMO-SKIP] recovery: pedido não encontrado", { lojaId, orderId });
    return { ok: false, reason: "order_not_found" };
  }
  return registrarPromocaoPosPagamentoMp(db, {
    lojaId,
    orderId,
    paymentId,
    orderData: loaded.data,
    orderRef: loaded.ref,
  });
}
