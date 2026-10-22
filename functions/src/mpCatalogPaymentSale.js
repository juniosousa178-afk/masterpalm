/**
 * Catálogo Mercado Pago → venda canônica (mpWebhook).
 * Funções puras: correlação pagamento↔pedido, estado de negócio do pedido e
 * montagem do comando `kind:'sale'` + `atomicPdvSale` executado como SERVER_PAYMENT_AUTH.
 */

import { orderTotalToCents } from "./catalogMpOrderHelpers.js";

export const MP_PAYMENT_SALE_PROTOCOL = "canonical_sale_v1";

/**
 * Instante de corte (UTC, ISO-8601 com `Z`) gravado uma única vez imediatamente antes do deploy.
 * Venda automática exige aprovação MP e criação do pedido >= corte; ausente/inválido → nenhuma venda automática.
 */
export const MP_CATALOG_AUTO_SALE_CUTOVER_ENV = "MP_CATALOG_AUTO_SALE_CUTOVER_UTC";

/** Reentregas fora desta janela não reenviam e-mail/WhatsApp/notificação pendentes. */
export const MP_POST_EFFECTS_RETRY_WINDOW_MS = 72 * 60 * 60 * 1000;

const CUTOVER_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
const OFFSET_DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/;

export function parseAutoSaleCutoverUtc(raw) {
  const s = String(raw ?? "").trim();
  if (!CUTOVER_RE.test(s)) return null;
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? ms : null;
}

/** Timestamp do Firestore (ou Date) → ms; strings/números não são aceitos como data de criação. */
export function timestampLikeToMs(v) {
  if (v == null) return null;
  if (typeof v.toMillis === "function") {
    const ms = v.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (v instanceof Date) {
    const ms = v.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/** Aprovação autoritativa: `date_approved` da API MP com fuso explícito e >= corte. */
export function evaluatePaymentCutover({ payment, cutoverMs }) {
  if (!Number.isFinite(cutoverMs)) return { ok: false, reason: "auto_sale_cutover_not_configured" };
  const approvedMs = paymentApprovedAtMs(payment);
  if (approvedMs == null) return { ok: false, reason: "payment_approval_time_invalid" };
  if (approvedMs < cutoverMs) return { ok: false, reason: "payment_approved_before_cutover" };
  return { ok: true, approvedMs };
}

const ORDER_CREATION_FIELDS = ["dataCriacao", "createdAt"];

/**
 * Criação do pedido: `createTime` do documento (servidor, imutável) e todo campo de criação
 * declarado (`dataCriacao`/`createdAt`) devem existir, ser Timestamp e ser >= corte.
 */
export function evaluateOrderCutover({ createTimeMs, order, cutoverMs }) {
  if (!Number.isFinite(cutoverMs)) return { ok: false, reason: "auto_sale_cutover_not_configured" };
  if (!Number.isFinite(createTimeMs)) return { ok: false, reason: "order_create_time_missing" };
  if (createTimeMs < cutoverMs) return { ok: false, reason: "order_created_before_cutover" };
  let declared = 0;
  for (const field of ORDER_CREATION_FIELDS) {
    const raw = order?.[field];
    if (raw == null) continue;
    declared++;
    const ms = timestampLikeToMs(raw);
    if (ms == null) return { ok: false, reason: "order_creation_time_invalid" };
    if (ms < cutoverMs) return { ok: false, reason: "order_created_before_cutover" };
  }
  if (declared === 0) return { ok: false, reason: "order_creation_time_missing" };
  return { ok: true };
}

const PAYMENT_ID_RE = /^[0-9]{1,32}$/;

export function normalizeMpPaymentId(raw) {
  const s = String(raw ?? "").trim();
  return PAYMENT_ID_RE.test(s) ? s : null;
}

/** operationId da venda canônica = id do documento estoque_vendas e stock_catalog_operations. */
export function mpPaymentSaleOperationId(paymentId) {
  const pid = normalizeMpPaymentId(paymentId);
  if (!pid) throw new Error("invalid paymentId");
  return `mp_payment_sale_${pid}`;
}

/** Mesmo id usado pelo app ao confirmar o pré-pedido manualmente (PrePedidoSaleIntent). */
export function prePedidoSaleIntentId(orderId) {
  return `pre_pedido:${String(orderId).trim()}`;
}

/**
 * Loja no metadata do pagamento. A API MP devolve snake_case (`loja_id`); `lojaId` aceito por
 * compatibilidade. Se ambos vierem, precisam coincidir.
 * @returns {{ lojaId: string | null, conflict: boolean }}
 */
export function resolvePaymentMetadataLojaId(payment) {
  const md = payment && typeof payment.metadata === "object" && payment.metadata ? payment.metadata : {};
  const values = [md.loja_id, md.lojaId]
    .map((v) => (v == null ? "" : String(v).trim()))
    .filter(Boolean);
  if (values.length === 0) return { lojaId: null, conflict: false };
  if (values.some((v) => v !== values[0])) return { lojaId: null, conflict: true };
  return { lojaId: values[0], conflict: false };
}

export function paymentApprovedAtMs(payment) {
  const raw = payment?.date_approved;
  if (typeof raw !== "string" || !OFFSET_DATETIME_RE.test(raw.trim())) return null;
  const ms = Date.parse(raw.trim());
  return Number.isFinite(ms) ? ms : null;
}

/** `transaction_amount` → centavos exatos; mais de 2 casas decimais é inválido. */
export function paymentAmountToCents(amount) {
  const n = typeof amount === "number" ? amount : typeof amount === "string" && amount.trim() ? Number(amount) : NaN;
  if (!Number.isFinite(n)) return null;
  const cents = Math.round(n * 100);
  return Math.abs(n * 100 - cents) < 1e-6 ? cents : null;
}

export function isPixPayment(payment) {
  const method = String(payment?.payment_method_id ?? "").toLowerCase();
  const type = String(payment?.payment_type_id ?? "").toLowerCase();
  return method === "pix" || type === "bank_transfer";
}

/**
 * Correlação determinística (fail closed): external_reference, metadata da loja,
 * loja do pedido, valor e moeda devem coincidir.
 */
export function validateCatalogPaymentCorrelation({ payment, lojaId, orderId, order }) {
  const ext = String(payment?.external_reference ?? "").trim();
  if (!ext) return { ok: false, code: "external_reference_missing" };
  if (ext !== String(orderId)) return { ok: false, code: "external_reference_mismatch" };
  const meta = resolvePaymentMetadataLojaId(payment);
  if (meta.conflict) return { ok: false, code: "metadata_loja_conflict" };
  if (!meta.lojaId) return { ok: false, code: "metadata_loja_missing" };
  if (meta.lojaId !== String(lojaId)) return { ok: false, code: "loja_metadata_mismatch" };
  const orderLoja = order?.lojaId == null ? "" : String(order.lojaId).trim();
  if (orderLoja && orderLoja !== String(lojaId)) return { ok: false, code: "order_loja_mismatch" };
  const expectedCents = orderTotalToCents(order?.total);
  if (expectedCents == null || expectedCents < 1) return { ok: false, code: "order_total_invalid" };
  const paidCents = paymentAmountToCents(payment?.transaction_amount);
  if (paidCents == null) return { ok: false, code: "payment_amount_invalid" };
  if (paidCents !== expectedCents) {
    return { ok: false, code: "amount_mismatch", expectedCents, paidCents };
  }
  if (String(payment?.currency_id ?? "").trim().toUpperCase() !== "BRL") {
    return { ok: false, code: "currency_mismatch" };
  }
  return { ok: true, expectedCents, paidCents };
}

const CONFIRMED_STATUSES = new Set([
  "confirmado", "paid", "pago", "aprovado", "embalando", "em_preparacao",
  "enviado", "entregue", "finalizado", "concluido", "concluida",
]);
const CANCELLED_STATUSES = new Set(["cancelado", "cancelada", "cancelled", "canceled"]);
const PAYABLE_STATUSES = new Set(["", "pendente", "aguardando_pagamento", "aguardando", "novo"]);

function str(v) {
  return v == null ? "" : String(v).trim();
}

/**
 * Estado de negócio do pedido lido na transação.
 * `already_business_confirmed`: venda manual/automática já existe ou pedido já pago → 0 efeitos.
 * `blocked`: pagamento aprovado mas o pedido não pode receber venda automática → alerta ao lojista.
 */
export function classifyOrderForAutoSale(order, paymentId) {
  if (!order || typeof order !== "object") return { state: "missing", reason: "order_document_not_found" };
  const status = str(order.status).toLowerCase();
  const sp = str(order.statusPagamento).toLowerCase();
  const mp = str(order.mpPaymentStatus).toLowerCase();
  if (order.paidAt != null) return { state: "already_business_confirmed", reason: "order_paid_at_present" };
  if (str(order.vendaId) || str(order.saleId)) {
    return { state: "already_business_confirmed", reason: "order_sale_link_present" };
  }
  if (str(order.paymentId)) {
    return {
      state: "already_business_confirmed",
      reason: str(order.paymentId) === String(paymentId) ? "order_payment_already_recorded" : "order_paid_by_other_payment",
    };
  }
  if (CONFIRMED_STATUSES.has(status)) return { state: "already_business_confirmed", reason: `order_status_${status}` };
  if (sp === "aprovado" || sp === "approved" || sp === "pago" || mp === "approved") {
    return { state: "already_business_confirmed", reason: "order_payment_status_approved" };
  }
  if (CANCELLED_STATUSES.has(status) || sp === "cancelado" || sp === "cancelada") {
    return { state: "blocked", reason: "order_cancelled" };
  }
  if (str(order.governancaStatus) === "substituido") return { state: "blocked", reason: "order_superseded" };
  if (!PAYABLE_STATUSES.has(status)) return { state: "blocked", reason: "order_status_unexpected" };
  return { state: "payable", reason: null };
}

/** Intenção de venda manual do app (lojas/{id}/sale_intents/pre_pedido:{orderId}). */
export function classifySaleIntent(intentData) {
  if (!intentData || typeof intentData !== "object") return { blocking: false };
  const status = str(intentData.status);
  if (status === "reverted") return { blocking: false };
  return { blocking: true, reason: `manual_sale_intent_${status || "unknown"}` };
}

function num(v) {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : NaN;
}

function round2(n) {
  return Math.round(n * 100 + Number.EPSILON) / 100;
}

function selector(v, technical) {
  const s = typeof v === "string" ? v.trim() : v == null ? "" : String(v).trim();
  return technical.includes(s.toLowerCase()) ? "" : s;
}

function clip(v, max) {
  const s = str(v);
  return s.length > max ? s.slice(0, max) : s;
}

/**
 * Pré-pedido → comando canônico de venda.
 * @returns {{ok: true, command: object} | {ok: false, reason: string}}
 */
export function buildCanonicalSaleCommandFromOrder({ lojaId, orderId, paymentId, payment, order, paidCents }) {
  const raw = Array.isArray(order?.itens) ? order.itens : Array.isArray(order?.items) ? order.items : null;
  if (!raw || raw.length === 0) return { ok: false, reason: "order_items_missing" };
  if (raw.length > 100) return { ok: false, reason: "order_items_too_many" };

  const items = [];
  const saleItens = [];
  let totalQty = 0;
  for (const it of raw) {
    if (!it || typeof it !== "object") return { ok: false, reason: "order_item_invalid" };
    const combo = it.itensComboComSelecao;
    if ((Array.isArray(combo) && combo.length > 0) || str(it.comboConfiguravelResumo)) {
      return { ok: false, reason: "configurable_combo_requires_manual_confirmation" };
    }
    const productId = str(it.productId ?? it.produtosId ?? it.id);
    if (!productId || productId.includes("/") || productId.length > 256) {
      return { ok: false, reason: "order_item_product_missing" };
    }
    const qty = num(it.quantidade ?? it.qty);
    if (!Number.isSafeInteger(qty) || qty <= 0) return { ok: false, reason: "order_item_quantity_invalid" };
    const size = selector(it.tamanho ?? it.size, ["sem-tamanho"]);
    const color = selector(it.cor ?? it.color, ["sem-cor", "semcor"]);
    const extra = selector(it.extraValor ?? it.variacaoExtra, []);
    items.push({ productId, quantity: qty, size, color, extra });

    const pu = num(it.precoUnitario ?? it.preco ?? it.price);
    const precoUnitario = Number.isFinite(pu) && pu >= 0 ? pu : 0;
    const line = {
      produtoNome: clip(it.nomeSnapshot ?? it.nome ?? it.name, 300),
      quantidade: qty,
      tamanho: clip(it.tamanho, 80),
      cor: clip(it.cor, 80),
      precoUnitario,
      precoTotal: round2(precoUnitario * qty),
      productId,
    };
    const resumo = clip(it.variacaoExtraResumo, 200);
    if (resumo) line.variacaoExtraResumo = resumo;
    const extraValor = clip(it.extraValor ?? it.variacaoExtra, 80);
    if (extraValor) line.extraValor = extraValor;
    saleItens.push(line);
    totalQty += qty;
  }

  const total = paidCents / 100;
  const freteMap = order?.frete && typeof order.frete === "object" ? order.frete : {};
  const freteGratis = freteMap.gratis === true || freteMap.freteGratis === true;
  const freteRaw = num(freteMap.valor);
  const frete = freteGratis || !Number.isFinite(freteRaw) || freteRaw < 0 ? 0 : round2(freteRaw);
  const cupomDesc = num(order?.cupom?.desconto);
  const pix = isPixPayment(payment);
  const type = String(payment?.payment_type_id ?? "").toLowerCase();
  const formasPagamento = pix
    ? "Mercado Pago (PIX)"
    : type === "credit_card" || type === "debit_card"
      ? "Mercado Pago (Cartão)"
      : "Mercado Pago";
  const cliente = order?.cliente && typeof order.cliente === "object" ? order.cliente : {};
  const clienteId = str(cliente.id);

  const sale = {
    clienteNome: clip(cliente.nome, 200) || "Cliente",
    ...(clienteId && clienteId.length <= 128 ? { clienteId } : {}),
    produtosDescricao: clip(saleItens.map((i) => `${i.quantidade}x ${i.produtoNome}`).join(", "), 8000),
    quantidade: totalQty,
    preco: Math.max(0, round2(total - frete)),
    total,
    formasPagamento,
    frete,
    desconto: 0,
    descontoValor: Number.isFinite(cupomDesc) && cupomDesc > 0 ? round2(cupomDesc) : 0,
    observacao: `Pedido do catálogo ${orderId} · pagamento Mercado Pago ${paymentId}`,
    pagamentoPix: pix ? total : 0,
    pagamentoCartao: pix ? 0 : total,
    vendedor: "Loja online",
    itens: saleItens,
  };

  return {
    ok: true,
    command: {
      protocolVersion: 1,
      lojaId: String(lojaId),
      operationId: mpPaymentSaleOperationId(paymentId),
      kind: "sale",
      items,
      atomicPdvSale: true,
      sale,
    },
  };
}

/** Erros determinísticos do comando de estoque (validação/negócio): não adianta retentar. */
export function isDeterministicStockError(error) {
  const code = error?.code;
  return typeof code === "string" && [
    "failed-precondition", "invalid-argument", "not-found", "permission-denied",
    "resource-exhausted", "already-exists", "out-of-range",
  ].includes(code);
}

/** Motivo resumido (sem PII) para marcador/e-mail. */
export function stockErrorReason(error) {
  const issues = Array.isArray(error?.issues) ? error.issues : [];
  const codes = [...new Set(issues.map((i) => str(i?.reasonCode)).filter(Boolean))];
  if (codes.length) return `stock_${codes.join("+").toLowerCase()}`.slice(0, 120);
  const msg = str(error?.message).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
  return `stock_${String(error?.code || "error")}_${msg}`.slice(0, 120);
}

export function maskEmailsInText(text) {
  return String(text ?? "").replace(/[^\s<>@"']+@[^\s<>@"']+/g, "[email]");
}

const BLOCKED_REASON_PT = {
  order_cancelled: "o pedido está cancelado (verifique reembolso ao cliente)",
  order_superseded: "o pedido foi substituído por outra tentativa de checkout (verifique duplicidade/reembolso)",
  order_status_unexpected: "o pedido está num estado que não permite venda automática",
  configurable_combo_requires_manual_confirmation: "o pedido contém combo configurável",
  order_items_missing: "o pedido não tem itens",
  order_items_too_many: "o pedido tem itens demais para a venda automática",
  order_item_invalid: "o pedido tem um item inválido",
  order_item_product_missing: "um item do pedido não tem produto identificado",
  order_item_quantity_invalid: "um item do pedido tem quantidade inválida",
};

export function blockedReasonText(reason) {
  const r = str(reason);
  if (BLOCKED_REASON_PT[r]) return BLOCKED_REASON_PT[r];
  if (r.includes("insufficient_stock")) return "estoque insuficiente para algum item";
  if (r.startsWith("stock_")) return "o estoque/cadastro de algum item não permitiu a baixa automática";
  return "a venda automática não pôde ser registrada";
}
