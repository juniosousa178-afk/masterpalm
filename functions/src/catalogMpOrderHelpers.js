/**
 * Catálogo Mercado Pago — helpers compartilhados (mpCatalogPayment + mpWebhook).
 * Fonte da verdade do valor: total persistido no pedido/pré-pedido.
 */

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";

/** Converte total em centavos (inteiro) para comparação segura. */
export function orderTotalToCents(total) {
  const n = Number(total);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100 + Number.EPSILON);
}

/**
 * Resolve pedido do catálogo (mesma ordem do mpWebhook): pedidos → pre_pedidos → pedidos_pendentes.
 */
export async function resolveCatalogOrderForMp(db, lojaId, orderId) {
  const lid = String(lojaId);
  const oid = String(orderId);
  const paths = [
    ["pedidos", false, false],
    ["pre_pedidos", true, false],
    ["pedidos_pendentes", false, true],
  ];
  for (const [sub, isPre, isPend] of paths) {
    const ref = db.collection(COLLECTION_LOJAS).doc(lid).collection(sub).doc(oid);
    const snap = await ref.get();
    if (snap.exists) {
      return {
        orderRef: ref,
        order: snap.data() || {},
        isPrePedido: isPre,
        isPedidoPendente: isPend,
        collection: sub,
      };
    }
  }
  return null;
}

export function isOrderPayableForMp(order) {
  if (!order || typeof order !== "object") return false;
  if (order.paidAt) return false;
  const st = String(order.status || "").toLowerCase();
  if (st === "cancelado" || st === "cancelled" || st === "canceled") return false;
  const sp = String(order.statusPagamento || "").toLowerCase();
  if (sp === "cancelado" || sp === "cancelada") return false;
  const total = Number(order.total);
  if (!Number.isFinite(total) || total < 0.01) return false;
  return true;
}

/**
 * Valida pagamento MP contra pedido (webhook). Exige igualdade exata em centavos.
 */
export function validateMpPaymentAgainstOrder({
  payment,
  expectedCents,
  resolvedLojaId,
  orderId,
}) {
  if (expectedCents == null) {
    return { ok: false, code: "order_total_invalid" };
  }
  const tid = payment.transaction_amount;
  const paidCents =
    typeof tid === "number"
      ? Math.round(tid * 100 + Number.EPSILON)
      : orderTotalToCents(tid);
  if (paidCents == null) {
    return { ok: false, code: "payment_amount_missing" };
  }
  if (paidCents !== expectedCents) {
    return {
      ok: false,
      code: "amount_mismatch",
      expectedCents,
      paidCents,
    };
  }
  const cur = payment.currency_id;
  if (cur != null && String(cur).toUpperCase() !== "BRL") {
    return { ok: false, code: "currency_mismatch", currency: cur };
  }
  const ext = payment.external_reference != null ? String(payment.external_reference) : "";
  if (ext && String(orderId) !== ext) {
    return { ok: false, code: "external_reference_mismatch", external_reference: ext, orderId: String(orderId) };
  }
  const metaLoja = payment.metadata && payment.metadata.lojaId;
  if (metaLoja != null && String(metaLoja) !== String(resolvedLojaId)) {
    return { ok: false, code: "loja_metadata_mismatch", metadataLojaId: String(metaLoja) };
  }
  return { ok: true };
}
