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
 * Normaliza total BRL para `transaction_amount` no PIX do catálogo (centavos = `orderTotalToCents`).
 */
export function normalizeBrlTransactionAmountForMpPix(total) {
  const n = Number(total);
  if (!Number.isFinite(n)) {
    return { ok: false, code: "PIX_AMOUNT_INVALID" };
  }
  const cents = orderTotalToCents(n);
  if (cents == null || cents < 1) {
    return { ok: false, code: "PIX_AMOUNT_INVALID" };
  }
  const transactionAmount = cents / 100;
  return { ok: true, transactionAmount, cents };
}

/**
 * Heurística para mensagens/códigos do provedor MP ligados a valor/amount/transaction_amount.
 */
export function mpCatalogPixProviderErrorIsAmountRelated(message) {
  const s = String(message ?? "").toLowerCase();
  if (!s.trim()) return false;
  if (s.includes("transaction_amount") || s.includes("transaction amount")) {
    return true;
  }
  if (s.includes("amount_mismatch") || s.includes("amount mismatch")) {
    return true;
  }
  if (/\bvalor\b/.test(s) && (s.includes("invalid") || s.includes("inválido") || s.includes("invalido"))) {
    return true;
  }
  return false;
}

/**
 * Resolve pedido do catálogo (mesma ordem do mpWebhook): pedidos → pre_pedidos → pedidos_pendentes.
 */
/**
 * Extrai nome/e-mail/CPF/telefone do pedido ou pré-pedido do catálogo (campo aninhado [cliente]).
 * Usado pelo Mercado Pago (PIX / Checkout Pro) para montar [payer] válido.
 */
export function extractCatalogOrderBuyer(order) {
  if (!order || typeof order !== "object") {
    return { name: "", email: "", cpf: "", telefone: "" };
  }
  const c =
    order.cliente && typeof order.cliente === "object" && !Array.isArray(order.cliente)
      ? order.cliente
      : {};
  const name = String(c.nome ?? order.customerName ?? order.nomeCliente ?? "").trim();
  const email = String(c.email ?? order.clienteEmail ?? order.email ?? "").trim();
  const cpf = String(c.cpf ?? order.cpf ?? "").trim();
  const telefone = String(
    c.telefone ?? c.whatsapp ?? order.telefone ?? order.telefoneContato ?? "",
  ).trim();
  return { name, email, cpf, telefone };
}

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

/**
 * Mapeia `pedido.pagamento` (catálogo) para campos da venda em estoque_vendas.
 * Fallback: payment_method_id / payment_type_id do MP quando o pedido não tiver pagamento.
 */
export function mapCatalogOrderPagamentoToVendaFields(pagamento, total, payment) {
  const totalN = Number(total) || 0;
  let pagamentoStr = String(pagamento ?? "").trim();
  if (!pagamentoStr && payment && typeof payment === "object") {
    const pm = String(payment.payment_method_id ?? "").toLowerCase();
    const pt = String(payment.payment_type_id ?? "").toLowerCase();
    if (pm === "pix" || pt === "bank_transfer") pagamentoStr = "PIX";
    else if (pt === "credit_card" || pt === "debit_card") pagamentoStr = "Cartão";
  }
  const upper = pagamentoStr.toUpperCase();
  let pagamentoPix = 0;
  let pagamentoCartao = 0;
  let pagamentoDinheiro = 0;
  let formasPagamento = pagamentoStr || "Mercado Pago";

  if (upper === "PIX" || (upper.includes("PIX") && !upper.includes("CART"))) {
    pagamentoPix = totalN;
    formasPagamento = pagamentoStr || "PIX";
  } else if (
    upper.includes("CART") ||
    upper.includes("CARTÃO") ||
    upper === "MERCADO PAGO" ||
    upper.includes("MERCADO PAGO")
  ) {
    pagamentoCartao = totalN;
    formasPagamento = pagamentoStr || "Cartão";
  } else if (upper.includes("DINHEIRO")) {
    pagamentoDinheiro = totalN;
    formasPagamento = pagamentoStr || "Dinheiro";
  } else if (payment && String(payment.payment_method_id ?? "").toLowerCase() === "pix") {
    pagamentoPix = totalN;
    formasPagamento = "PIX";
  } else if (pagamentoStr) {
    pagamentoPix = totalN;
    formasPagamento = pagamentoStr;
  } else {
    pagamentoCartao = totalN;
    formasPagamento = "Mercado Pago";
  }

  return { formasPagamento, pagamentoPix, pagamentoCartao, pagamentoDinheiro };
}

/**
 * Resolve docId em estoque_produtos (productId/id ou consulta por slug).
 * Itens sem ID resolvível são omitidos (logados pelo caller).
 */
export async function resolveCatalogStockItemDocIds(db, lojaId, items) {
  const lid = String(lojaId);
  const out = [];
  for (const it of items || []) {
    let pId = String(it.productId ?? it.produtosId ?? it.id ?? "").trim();
    if (!pId) {
      const slug = String(it.slug ?? "").trim();
      if (slug) {
        try {
          const q = await db
            .collection(COLLECTION_LOJAS)
            .doc(lid)
            .collection("estoque_produtos")
            .where("slug", "==", slug)
            .limit(2)
            .get();
          if (q.size === 1) {
            pId = q.docs[0].id;
          } else if (q.size > 1) {
            console.warn(`[mpWebhook] slug duplicado em estoque_produtos: ${slug}`);
          }
        } catch (e) {
          console.warn("[mpWebhook] resolve slug estoque:", e && e.message);
        }
      }
    }
    if (!pId) {
      console.warn(
        "[mpWebhook] item sem productId resolvível:",
        (it.nome ?? it.name ?? "").toString(),
      );
      continue;
    }
    out.push({ ...it, __resolvedDocId: pId });
  }
  return out;
}
