/**
 * Handler do Webhook Mercado Pago – MasterPalm
 *
 * Garantias:
 * - Idempotência por paymentId (reenvios não duplicam processamento)
 * - Token correto por lojaId (multi-tenant)
 * - Baixa de estoque apenas uma vez (transação atômica)
 * - Gravação de auditoria em payments/ e espelho estoque_vendas: falhas são logadas
 *   e não impedem o restante (transação já commitada; admin/WhatsApp seguem quando aplicável)
 *
 * Fluxo:
 * 1. Verifica se paymentId já foi processado (early return 200)
 * 2. Resolve lojaId e token (global ou por loja)
 * 3. Busca payment na API MP
 * 4. Transação: marca processado + atualiza pedido + baixa estoque
 * 5. Pós-pagamento promocional (campanha / número da sorte): mpWebhookPromo.js
 */

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import {
  registrarPromocaoPosPagamentoMp,
  registrarPromocaoPosPagamentoMpRecovery,
} from "./mpWebhookPromo.js";
import {
  orderTotalToCents,
  validateMpPaymentAgainstOrder,
  mapCatalogOrderPagamentoToVendaFields,
  resolveCatalogStockItemDocIds,
} from "./catalogMpOrderHelpers.js";
import { emitWebhookLog } from "./mpStructuredLogsMp.js";

/** Lazy: evita getFirestore() antes de initializeApp() no deploy/analyze */
function getDb() {
  return getFirestore();
}
const nowTs = FieldValue.serverTimestamp();
const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";
/** Forense suporte: falhas de validação (sem raw MP). Não bloqueia _mp_webhook_processed. */
const WEBHOOK_VALIDATION_REJECTS_COL = "_mp_webhook_validation_rejects";

/**
 * Registro mínimo consultável para snapshot (sem PII, sem payload bruto).
 * merge: reentradas atualizam updatedAt; createdAt preservado na primeira gravação.
 */
export async function persistWebhookValidationReject(db, payload) {
  const {
    paymentId,
    lojaId,
    orderId,
    externalReference,
    validationReason,
    paymentStatus,
    paymentMethod,
    amountExpectedCents,
    amountReceivedCents,
    currencyId,
  } = payload;
  const ref = db.collection(WEBHOOK_VALIDATION_REJECTS_COL).doc(String(paymentId));
  const existing = await ref.get();
  const doc = {
    lojaId: String(lojaId),
    orderId: String(orderId),
    paymentId: String(paymentId),
    externalReference: String(externalReference ?? orderId),
    validationReason: String(validationReason),
    paymentStatus: paymentStatus != null ? String(paymentStatus) : null,
    paymentMethod: paymentMethod != null ? String(paymentMethod) : null,
    amountExpectedCents: amountExpectedCents != null ? Number(amountExpectedCents) : null,
    amountReceivedCents: amountReceivedCents != null ? Number(amountReceivedCents) : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (currencyId != null && String(currencyId).trim()) {
    doc.currencyId = String(currencyId).toUpperCase().slice(0, 8);
  }
  if (!existing.exists) doc.createdAt = FieldValue.serverTimestamp();
  await ref.set(doc, { merge: true });
}

/** fetch com timeout */
async function fetchWithTimeout(url, opts = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...opts, signal: controller.signal });
    clearTimeout(id);
    return res;
  } catch (e) {
    clearTimeout(id);
    if (e.name === "AbortError") throw new Error(`Request timeout after ${timeoutMs}ms`);
    throw e;
  }
}

/**
 * Obtém token MP da loja (OAuth mp.access_token ou legado mp_access_token)
 */
async function getLojaMpToken(lojaId) {
  try {
    const db = getDb();
    const doc = await db
      .collection(COLLECTION_LOJAS)
      .doc(String(lojaId))
      .collection("config")
      .doc("payments")
      .get();

    const data = doc.exists ? (doc.data() || {}) : {};
    // OAuth: mp.access_token | mp.token | legado: mp_access_token
    const token =
      (data.mp?.access_token || data.mp?.token || data.mp_access_token || "").trim();
    return token || null;
  } catch (e) {
    console.error("[getLojaMpToken] erro:", e);
    return null;
  }
}

/**
 * Busca payment na API MP com o token fornecido
 */
async function fetchPaymentFromMp(paymentId, token) {
  const r = await fetchWithTimeout(
    `https://api.mercadopago.com/v1/payments/${paymentId}`,
    { headers: { Authorization: `Bearer ${token}` } },
    15000
  );

  if (!r.ok) return null;
  return r.json();
}

/**
 * Resolve lojaId e payment.
 * Ordem: busca estritamente em tokens de lojas (sem credencial de plataforma).
 * Exportado para uso em posPagamento.js (multi-loja).
 */
export async function resolveLojaAndPayment(paymentId) {
  // Iterar lojas para encontrar a que tem o payment
  const lojasSnap = await getDb().collection(COLLECTION_LOJAS).select().get();

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const token = await getLojaMpToken(lojaId);
    if (!token || token.length < 10) continue;

    const payment = await fetchPaymentFromMp(paymentId, token);
    if (payment) {
      return { payment, lojaId };
    }
  }

  return { payment: null, lojaId: null };
}

/**
 * Busca lojaId pelo orderId (usa order_loja_index; fallback varre pedidos/pre_pedidos)
 */
async function findLojaIdByOrderId(orderId) {
  const { resolveLojaIdByOrderId } = await import("./orderLojaIndex.js");
  return resolveLojaIdByOrderId(getDb(), orderId);
}

/**
 * Processa o webhook de pagamento MP.
 * Retorna true se processou (ou já estava processado), false se ignorado.
 *
 * Idempotência: transação atômica garante que paymentId é processado apenas uma vez.
 * Token: resolve estritamente por loja (OAuth/legado da própria loja).
 */
/**
 * @param {string} paymentId
 * @param {{ smtpUser?: string; smtpPass?: string }} [mailOpts] — e-mail pós-aprovação (secrets no index mpWebhook)
 */
export async function processMpWebhook(paymentId, mailOpts = {}) {
  if (!paymentId) return false;

  const smtpUser = (mailOpts.smtpUser || "").trim();
  const smtpPass = (mailOpts.smtpPass || "").trim();

  // 1) Resolver loja e buscar payment (token correto por loja)
  const { payment, lojaId } = await resolveLojaAndPayment(paymentId);

  if (!payment) {
    emitWebhookLog({
      event: "mpWebhook_validation_failed",
      severity: "warn",
      reason: "payment_not_found",
      paymentId: String(paymentId),
    });
    return false;
  }

  const orderId = payment.external_reference;
  const status = payment.status;
  emitWebhookLog({
    event: "mpWebhook_received",
    severity: "info",
    paymentId: String(paymentId),
    paymentStatus: status != null ? String(status) : undefined,
    paymentMethod: payment.payment_method_id != null ? String(payment.payment_method_id) : undefined,
    externalReference: orderId != null ? String(orderId) : undefined,
    lojaId: payment?.metadata?.lojaId != null ? String(payment.metadata.lojaId) : undefined,
  });

  let resolvedLojaId = lojaId || payment?.metadata?.lojaId || null;
  if (!resolvedLojaId && orderId) {
    resolvedLojaId = await findLojaIdByOrderId(orderId);
  }

  if (!orderId || !resolvedLojaId) {
    emitWebhookLog({
      event: "mpWebhook_validation_failed",
      severity: "warn",
      reason: "orderId_or_lojaId_missing",
      paymentId: String(paymentId),
      externalReference: orderId != null ? String(orderId) : undefined,
      lojaId: resolvedLojaId != null ? String(resolvedLojaId) : undefined,
    });
    return false;
  }

  const db = getDb();
  const orderRef = db
    .collection(COLLECTION_LOJAS)
    .doc(resolvedLojaId)
    .collection("pedidos")
    .doc(orderId);
  const prePedidoRef = db
    .collection(COLLECTION_LOJAS)
    .doc(resolvedLojaId)
    .collection("pre_pedidos")
    .doc(orderId);
  const pedidoPendenteRef = db
    .collection(COLLECTION_LOJAS)
    .doc(resolvedLojaId)
    .collection("pedidos_pendentes")
    .doc(orderId);

  const webhookProcessedRef = db.collection(WEBHOOK_PROCESSED_COL).doc(String(paymentId));

  // 2) Early check: se já processamos, retornar imediatamente (evita transação desnecessária)
  const existingProcessed = await webhookProcessedRef.get();
  if (existingProcessed.exists) {
    emitWebhookLog({
      event: "mpWebhook_duplicate_ignored",
      severity: "info",
      paymentId: String(paymentId),
      orderId: String(orderId),
      lojaId: String(resolvedLojaId),
      paymentStatus: status != null ? String(status) : undefined,
      externalReference: String(orderId),
    });
    try {
      await webhookProcessedRef.set(
        {
          lastDuplicateWebhookAt: nowTs,
          lastDuplicateWebhookOutcome: "noop_redelivery_after_processed",
          updatedAt: nowTs,
        },
        { merge: true },
      );
    } catch (e) {
      console.warn("[mpWebhook] merge duplicate delivery meta:", e && e.message);
    }
    // Recuperação: estoque já foi processado numa entrega anterior; campanha pode ter falhado depois.
    if (status === "approved") {
      const pdata = existingProcessed.data() || {};
      if (pdata.orderId && pdata.lojaId) {
        try {
          await registrarPromocaoPosPagamentoMpRecovery(getDb(), {
            lojaId: pdata.lojaId,
            orderId: pdata.orderId,
            paymentId,
          });
        } catch (re) {
          console.error("[PROMO-ERROR] recovery após processed", re && re.message);
        }
      } else {
        console.log("[PROMO-SKIP] recovery: _mp_webhook_processed sem orderId/lojaId");
      }
    }
    return true;
  }

  // 3) Registrar status no payments (auditoria) — não bloquear fluxo principal se falhar (regras/tamanho).
  try {
    await getDb()
      .collection(COLLECTION_LOJAS)
      .doc(resolvedLojaId)
      .collection("payments")
      .doc(String(paymentId))
      .set(
        {
          kind: "payment",
          orderId,
          lojaId: resolvedLojaId,
          status,
          amount: payment.transaction_amount,
          raw: payment,
          updatedAt: nowTs,
        },
        { merge: true }
      );
  } catch (auditErr) {
    emitWebhookLog({
      event: "mpWebhook_payments_audit_write_failed",
      severity: "warn",
      paymentId: String(paymentId),
      orderId: String(orderId),
      lojaId: String(resolvedLojaId),
      err: String(auditErr?.message || auditErr),
    });
  }

  // 4) Se aprovado: transação atômica (marca processado + pedido + estoque)
  if (status !== "approved") {
    return true;
  }

  let orderSnap = await orderRef.get();
  let isPrePedido = false;
  let isPedidoPendente = false;
  if (!orderSnap.exists) {
    orderSnap = await prePedidoRef.get();
    isPrePedido = orderSnap.exists;
  }
  if (!orderSnap.exists) {
    orderSnap = await pedidoPendenteRef.get();
    isPedidoPendente = orderSnap.exists;
  }
  if (!orderSnap.exists) {
    emitWebhookLog({
      event: "mpWebhook_validation_failed",
      severity: "warn",
      reason: "order_document_not_found",
      paymentId: String(paymentId),
      orderId: String(orderId),
      lojaId: String(resolvedLojaId),
      externalReference: String(orderId),
    });
    try {
      await persistWebhookValidationReject(getDb(), {
        paymentId,
        lojaId: resolvedLojaId,
        orderId,
        externalReference: orderId,
        validationReason: "order_document_not_found",
        paymentStatus: status,
        paymentMethod: payment.payment_method_id,
        amountExpectedCents: null,
        amountReceivedCents: orderTotalToCents(payment.transaction_amount),
      });
    } catch (e) {
      console.warn("[mpWebhook] persist validation reject (order missing):", e && e.message);
    }
    return false;
  }

  const orderRefToUse = orderSnap.ref;
  const order = orderSnap.data() || {};

  const expectedCents = orderTotalToCents(order.total);
  const pv = validateMpPaymentAgainstOrder({
    payment,
    expectedCents,
    resolvedLojaId,
    orderId: String(orderId),
  });
  if (!pv.ok) {
    emitWebhookLog({
      event: "mpWebhook_payment_validation_failed",
      severity: "error",
      reason: pv.code,
      paymentId: String(paymentId),
      orderId: String(orderId),
      lojaId: String(resolvedLojaId),
      externalReference: String(orderId),
      amountExpectedCents: expectedCents,
      amountReceivedCents:
        pv.paidCents != null ? Number(pv.paidCents) : orderTotalToCents(payment.transaction_amount) ?? undefined,
    });
    try {
      const recv =
        pv.paidCents != null ? Number(pv.paidCents) : orderTotalToCents(payment.transaction_amount);
      await persistWebhookValidationReject(getDb(), {
        paymentId,
        lojaId: resolvedLojaId,
        orderId,
        externalReference: orderId,
        validationReason: String(pv.code),
        paymentStatus: status,
        paymentMethod: payment.payment_method_id,
        amountExpectedCents: expectedCents,
        amountReceivedCents: recv != null ? recv : null,
        currencyId:
          pv.currency != null ? pv.currency : payment.currency_id != null ? payment.currency_id : null,
      });
    } catch (e) {
      console.warn("[mpWebhook] persist validation reject:", e && e.message);
    }
    return false;
  }

  emitWebhookLog({
    event: "mpWebhook_payment_approved",
    severity: "info",
    paymentId: String(paymentId),
    orderId: String(orderId),
    lojaId: String(resolvedLojaId),
    externalReference: String(orderId),
    paymentStatus: "approved",
    amountExpectedCents: expectedCents,
    amountReceivedCents: expectedCents,
  });

  const alreadyPaid = !!order.paidAt;

  if (alreadyPaid) {
    await webhookProcessedRef.set(
      {
        paymentId: String(paymentId),
        processedAt: nowTs,
        orderId,
        lojaId: resolvedLojaId,
        status: "already_paid",
        effectiveOutcome: "noop_order_already_paid",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    if (status === "approved") {
      try {
        await registrarPromocaoPosPagamentoMpRecovery(getDb(), {
          lojaId: resolvedLojaId,
          orderId,
          paymentId,
        });
      } catch (e) {
        console.error("[PROMO-ERROR] already_paid recovery", e && e.message);
      }
    }
    return true;
  }

  const items = order.items || order.itens || [];
  const itemsForStock = await resolveCatalogStockItemDocIds(getDb(), resolvedLojaId, items);

  emitWebhookLog({
    event: "mpWebhook_stock_update_started",
    severity: "info",
    paymentId: String(paymentId),
    orderId: String(orderId),
    lojaId: String(resolvedLojaId),
    externalReference: String(orderId),
  });

  // Transação atômica: garante que apenas uma execução processa (evita duplicar baixa de estoque)
  try {
    await getDb().runTransaction(async (tx) => {
    const procDoc = await tx.get(webhookProcessedRef);
    if (procDoc.exists) {
      return; // Já processado por outra requisição
    }

    const ordDoc = await tx.get(orderRefToUse);
    const ord = ordDoc.exists ? ordDoc.data() : {};
    if (ord.paidAt) {
      tx.set(
        webhookProcessedRef,
        {
          paymentId: String(paymentId),
          processedAt: nowTs,
          orderId,
          lojaId: resolvedLojaId,
          status: "already_paid",
          effectiveOutcome: "noop_concurrent_order_already_paid",
          updatedAt: nowTs,
        },
        { merge: true },
      );
      return;
    }

    tx.set(webhookProcessedRef, {
      paymentId: String(paymentId),
      orderId,
      lojaId: resolvedLojaId,
      processedAt: nowTs,
      status: "done",
      effectiveOutcome: "applied_order_paid_new_effect",
      updatedAt: nowTs,
    }, { merge: true });

    const updatePayload = {
      status: "paid",
      paidAt: nowTs,
      updatedAt: nowTs,
      paymentId: String(paymentId),
      paymentMethod: payment.payment_method_id,
    };
    if (isPrePedido || isPedidoPendente) {
      updatePayload.statusPagamento = "aprovado";
    }
    updatePayload.estoqueBaixado = true;
    tx.set(orderRefToUse, updatePayload, { merge: true });

    for (const it of itemsForStock) {
      const pId = it.__resolvedDocId;
      if (!pId) continue;
      const qty = Number(it.qty ?? it.quantidade ?? 0);
      if (qty <= 0) continue;

      const tamanho = (it.tamanho ?? "").toString().trim();
      const cor = (it.cor ?? "").toString().trim();
      const temVariacao = tamanho || cor;

      const produtosRef = db
        .collection(COLLECTION_LOJAS)
        .doc(resolvedLojaId)
        .collection("produtos")
        .doc(String(pId));
      const estoqueRef = db
        .collection(COLLECTION_LOJAS)
        .doc(resolvedLojaId)
        .collection("estoque_produtos")
        .doc(String(pId));

      let updateProdutos = {};
      let updateEstoque = {};

      // Priorizar estoque_produtos como fonte (alinhado com app/admin). Fallback para produtos.
      const estoqueSnap = await tx.get(estoqueRef);
      const prodSnap = await tx.get(produtosRef);
      const data = (estoqueSnap.exists && estoqueSnap.data())
        ? estoqueSnap.data()
        : (prodSnap.exists && prodSnap.data())
          ? prodSnap.data()
          : {};

      if (temVariacao) {
        const variacoesRaw = data.variacoes;
        const estoquePorTamanhoRaw = data.estoquePorTamanho;

        const variacoes = variacoesRaw && typeof variacoesRaw === "object"
          ? JSON.parse(JSON.stringify(variacoesRaw))
          : null;
        const estoquePorTamanho = estoquePorTamanhoRaw && typeof estoquePorTamanhoRaw === "object"
          ? JSON.parse(JSON.stringify(estoquePorTamanhoRaw))
          : null;

        const usaVariacoes = variacoes && Object.keys(variacoes).length > 0 && tamanho && cor;
        const temEstoquePorTamanho = estoquePorTamanho && Object.keys(estoquePorTamanho).length > 0 && tamanho;

        if (usaVariacoes) {
          const mapaTamanho = variacoes[tamanho];
          if (mapaTamanho && typeof mapaTamanho === "object") {
            const disponivel = (mapaTamanho[cor] ?? 0) | 0;
            const novo = Math.max(0, disponivel - qty);
            if (novo > 0) {
              mapaTamanho[cor] = novo;
            } else {
              delete mapaTamanho[cor];
            }
            if (Object.keys(mapaTamanho).length === 0) delete variacoes[tamanho];
            const qtdTotal = Object.values(variacoes).reduce((acc, m) => acc + Object.values(m).reduce((a, b) => a + (b | 0), 0), 0);
            updateProdutos = { variacoes, quantidade: qtdTotal, estoque: qtdTotal, estoque_atual: qtdTotal, updatedAt: nowTs };
            if (qtdTotal <= 0) updateProdutos.ativo = false;
            updateEstoque = { variacoes, quantidade: qtdTotal, updatedAt: nowTs };
          }
        } else if (temEstoquePorTamanho) {
          const disponivel = (estoquePorTamanho[tamanho] ?? 0) | 0;
          const novo = Math.max(0, disponivel - qty);
          if (novo > 0) {
            estoquePorTamanho[tamanho] = novo;
          } else {
            delete estoquePorTamanho[tamanho];
          }
          const qtdTotal = Object.values(estoquePorTamanho).reduce((a, b) => a + (b | 0), 0);
          updateProdutos = { estoquePorTamanho, quantidade: qtdTotal, estoque: qtdTotal, estoque_atual: qtdTotal, updatedAt: nowTs };
          if (qtdTotal <= 0) updateProdutos.ativo = false;
          updateEstoque = { estoquePorTamanho, quantidade: qtdTotal, updatedAt: nowTs };
        }
      }

      if (Object.keys(updateProdutos).length === 0) {
        const currentQty = (data.quantidade ?? data.estoque ?? 0) | 0;
        const novoEstoque = Math.max(0, currentQty - qty);
        updateProdutos = { estoque: novoEstoque, quantidade: novoEstoque, estoque_atual: novoEstoque, updatedAt: nowTs };
        if (novoEstoque <= 0) updateProdutos.ativo = false;
        updateEstoque = { quantidade: novoEstoque, updatedAt: nowTs };
      }

      tx.set(produtosRef, updateProdutos, { merge: true });
      tx.set(estoqueRef, updateEstoque, { merge: true });
    }
    });
  } catch (txErr) {
    emitWebhookLog({
      event: "mpWebhook_stock_update_error",
      severity: "error",
      paymentId: String(paymentId),
      orderId: String(orderId),
      lojaId: String(resolvedLojaId),
      externalReference: String(orderId),
      err: String(txErr?.message || txErr),
    });
    throw txErr;
  }

  emitWebhookLog({
    event: "mpWebhook_stock_update_success",
    severity: "info",
    paymentId: String(paymentId),
    orderId: String(orderId),
    lojaId: String(resolvedLojaId),
    externalReference: String(orderId),
  });
  emitWebhookLog({
    event: "mpWebhook_order_marked_paid",
    severity: "info",
    paymentId: String(paymentId),
    orderId: String(orderId),
    lojaId: String(resolvedLojaId),
    externalReference: String(orderId),
    amountExpectedCents: expectedCents,
  });

  // Campanha + número da sorte (fonte oficial MP catálogo). Idempotente por paymentId (_mp_webhook_promo_processed).
  try {
    await registrarPromocaoPosPagamentoMp(getDb(), {
      lojaId: resolvedLojaId,
      orderId,
      paymentId,
      orderData: order,
      orderRef: orderRefToUse,
    });
  } catch (promoErr) {
    console.error("[PROMO-ERROR] pós-transação principal", promoErr && promoErr.message);
  }

  // Catálogo: pre_pedidos + pedidos_pendentes → mesma venda idempotente em estoque_vendas
  const mirrorEstoqueVendas = isPrePedido || isPedidoPendente;
  if (mirrorEstoqueVendas) {
    const cliente = order.cliente || {};
    const clienteNome = cliente.nome || "Cliente";
    const total = Number(order.total || 0);
    const pagamentoFields = mapCatalogOrderPagamentoToVendaFields(
      order.pagamento,
      total,
      payment,
    );
    const itensVenda = (order.itens || []).map((it) => ({
      produtoNome: it.nome || "",
      quantidade: Number(it.quantidade || 0),
      tamanho: (it.tamanho || "").toString(),
      cor: (it.cor || "").toString(),
      precoUnitario: Number(it.precoUnitario || 0),
      precoTotal: Number((it.precoUnitario || 0) * (it.quantidade || 0)),
    }));
    const vendaId = `mp_${orderId}_${paymentId}`;
    const estoqueVendasRef = db
      .collection(COLLECTION_LOJAS)
      .doc(resolvedLojaId)
      .collection("estoque_vendas")
      .doc(vendaId);
    try {
      await estoqueVendasRef.set(
        {
          id: vendaId,
          lojaId: resolvedLojaId,
          data: nowTs,
          total,
          desconto: 0,
          descontoValor: 0,
          formasPagamento: pagamentoFields.formasPagamento,
          frete: Number((order.frete || {}).valor || 0),
          clienteNome,
          produtosDescricao: itensVenda.map((i) => `${i.quantidade}x ${i.produtoNome}`).join(", "),
          quantidade: itensVenda.reduce((s, i) => s + i.quantidade, 0),
          preco: total - Number((order.frete || {}).valor || 0),
          tamanho: "",
          vendedor: "Catálogo Web",
          observacao: order.observacao || "",
          pagamentoDinheiro: pagamentoFields.pagamentoDinheiro,
          pagamentoPix: pagamentoFields.pagamentoPix,
          pagamentoCartao: pagamentoFields.pagamentoCartao,
          taxas: 0,
          custoProdutos: 0,
          itens: itensVenda,
          clienteId: (cliente.id || "").toString(),
          createdAt: nowTs,
          updatedAt: nowTs,
          status: "concluida",
          statusVenda: "concluida",
          paymentId: String(paymentId),
          orderId: String(orderId),
          prePedidoId: String(orderId),
          origemPrePedido: orderId,
          origemVenda: "mp_webhook",
        },
        { merge: true }
      );
    } catch (mirrorErr) {
      emitWebhookLog({
        event: "mpWebhook_estoque_vendas_mirror_failed",
        severity: "error",
        paymentId: String(paymentId),
        orderId: String(orderId),
        lojaId: String(resolvedLojaId),
        err: String(mirrorErr?.message || mirrorErr),
      });
    }

    // Notificar admin
    try {
      const lojaDoc = await db.collection(COLLECTION_LOJAS).doc(resolvedLojaId).get();
      const lojaData = lojaDoc.exists ? lojaDoc.data() || {} : {};
      const adminUid = lojaData.ownerUid || lojaData.adminUid || "";
      const adminEmail = lojaData.ownerEmail || lojaData.adminEmail || "";
      if (adminUid) {
        await db
          .collection(COLLECTION_LOJAS)
          .doc(resolvedLojaId)
          .collection("notificacoes")
          .add({
            destinatarioUid: adminUid,
            destinatarioEmail: adminEmail,
            tipo: "novaVenda",
            titulo: "🎉 NOVO PEDIDO PAGO! Parabéns!",
            mensagem: `Cliente: ${clienteNome}\nValor: R$ ${total.toFixed(2).replace(".", ",")}\n\n✅ PAGAMENTO CONFIRMADO - Dinheiro na conta!`,
            pedidoId: orderId,
            storeId: resolvedLojaId,
            valor: total,
            criadaEm: nowTs,
            lida: false,
            dados: { clienteNome, origem: "catalogo_web", pagamentoConfirmado: true },
          });
      }
    } catch (notifErr) {
      console.warn("[mpWebhook] Erro ao notificar admin:", notifErr.message);
    }
  }

  // Enviar confirmação de pedido por WhatsApp (formato tipo DELIGELI)
  try {
    const cliente = order.cliente || {};
    const telefone = (cliente.telefone || "").toString().trim().replace(/\D/g, "");
    const nome = (cliente.nome || "Cliente").toString();
    if (telefone.length >= 10) {
      const lojaDoc = await getDb().collection(COLLECTION_LOJAS).doc(resolvedLojaId).get();
      const lojaNome = lojaDoc.exists ? (lojaDoc.data().nome || resolvedLojaId) : resolvedLojaId;
      const itens = order.items || order.itens || [];
      const itensLinhas = itens
        .map((it) => {
          const qtd = Number(it.qty ?? it.quantidade ?? 1);
          const nomeItem = (it.name || it.nome || "").toString();
          return `➡ ${qtd}x ${nomeItem}`;
        })
        .join("\n");
      const total = Number(order.total || 0);
      const formaPagamento = (order.pagamento || "Mercado Pago").toString();
      const endereco = (cliente.enderecoFormatado || cliente.endereco || "Não informado").toString();
      const tempoEntrega = "45 - 60min";

      const message = `Olá ${nome}, aqui é o atendente virtual da *${String(lojaNome).toUpperCase()}*.

Vim te avisar que seu pedido foi realizado com sucesso e já está em preparo. 😊
Fique tranquilo(a) que vou enviar as atualizações do status do seu pedido por aqui.

*Nº do pedido* ${orderId}

*Itens:*
${itensLinhas || "—"}

*Forma de pagamento:* ${formaPagamento}

*Tempo de entrega:* ${tempoEntrega}

*Local de entrega:* ${endereco}

*Total do pedido:* R$ ${total.toFixed(2).replace(".", ",")}

Obrigado por comprar conosco! 💜`;

      const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
      if (projectId) {
        const cfUrl = `https://southamerica-east1-${projectId}.cloudfunctions.net/sendWhatsAppOrderConfirmation`;
        const r = await fetchWithTimeout(
          cfUrl,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              lojaId: resolvedLojaId,
              phone: cliente.telefone || telefone,
              message,
            }),
          },
          15000
        );
        if (r.ok) {
          console.log("[mpWebhook] WhatsApp confirmação enviado para", telefone);
        } else {
          console.warn("[mpWebhook] WhatsApp confirmação falhou:", r.status, await r.text());
        }
      }
    }
  } catch (whatsappErr) {
    console.warn("[mpWebhook] Erro ao enviar WhatsApp (não crítico):", whatsappErr.message);
  }

  // E-mail: pagamento aprovado — cliente + vendedor (SMTP igual onPrePedidoCreated)
  if (smtpUser && smtpPass) {
    try {
      const cliente = order.cliente || {};
      const clienteNome = (cliente.nome || "Cliente").toString().trim() || "Cliente";
      const clienteEmail = (cliente.email || "").toString().trim().toLowerCase();
      const total = Number(order.total || 0);
      const valorStr = total.toFixed(2).replace(".", ",");

      const lojaDoc = await getDb().collection(COLLECTION_LOJAS).doc(resolvedLojaId).get();
      const lojaData = lojaDoc.exists ? lojaDoc.data() || {} : {};
      const lojaNome = (lojaData.nome || "Loja").toString().trim() || "Loja";
      let adminEmail = (lojaData.ownerEmail || lojaData.adminEmail || "").toString().trim();
      if (!adminEmail && lojaData.owner && typeof lojaData.owner === "object") {
        adminEmail = (lojaData.owner.email || "").toString().trim();
      }

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: { user: smtpUser, pass: smtpPass },
      });

      if (clienteEmail && clienteEmail.includes("@")) {
        const corpoCliente =
          `Olá, ${clienteNome}!\n\n` +
          `Seu pagamento foi aprovado e o pedido foi confirmado.\n\n` +
          `Pedido: ${orderId}\n` +
          `Total: R$ ${valorStr}\n\n` +
          `Em breve a loja pode entrar em contato com atualizações do envio.\n\n` +
          `Obrigado por comprar conosco!`;
        await transporter.sendMail({
          from: `"${lojaNome}" <${smtpUser}>`,
          to: clienteEmail,
          subject: `Pagamento confirmado — pedido ${orderId}`,
          text: corpoCliente,
        });
        console.log("[mpWebhook] E-mail cliente (pagamento aprovado):", clienteEmail);
      } else {
        console.log("[mpWebhook] Cliente sem e-mail válido — e-mail de confirmação não enviado ao comprador");
      }

      if (adminEmail && adminEmail.includes("@")) {
        const corpoAdmin =
          `Pagamento aprovado no Mercado Pago.\n\n` +
          `Pedido / referência: ${orderId}\n` +
          `Cliente: ${clienteNome}\n` +
          `E-mail do cliente: ${clienteEmail || "(não informado)"}\n` +
          `Valor: R$ ${valorStr}\n` +
          `ID pagamento MP: ${paymentId}\n\n` +
          `Consulte os detalhes no painel da loja.`;
        await transporter.sendMail({
          from: `"MasterPalm" <${smtpUser}>`,
          to: adminEmail.toLowerCase(),
          subject: `Pedido pago — ${orderId} — ${lojaNome}`,
          text: corpoAdmin,
        });
        console.log("[mpWebhook] E-mail vendedor (pagamento aprovado):", adminEmail);
      } else {
        console.log("[mpWebhook] Loja sem e-mail do dono — e-mail ao vendedor não enviado");
      }
    } catch (mailErr) {
      console.warn("[mpWebhook] E-mail pós-aprovacao (não crítico):", mailErr && mailErr.message);
    }
  } else {
    console.log("[mpWebhook] SMTP não configurado — e-mails de pagamento aprovado não enviados");
  }

  return true;
}
