/**
 * Handler do Webhook Mercado Pago – MasterPalm
 *
 * Garantias:
 * - Idempotência por paymentId (reenvios não duplicam processamento)
 * - Token correto por lojaId (multi-tenant)
 * - Baixa de estoque apenas uma vez (transação atômica)
 *
 * Fluxo:
 * 1. Verifica se paymentId já foi processado (early return 200)
 * 2. Resolve lojaId e token (global ou por loja)
 * 3. Busca payment na API MP
 * 4. Transação: marca processado + atualiza pedido + baixa estoque
 */

import { getFirestore, FieldValue } from "firebase-admin/firestore";

/** Lazy: evita getFirestore() antes de initializeApp() no deploy/analyze */
function getDb() {
  return getFirestore();
}
const nowTs = FieldValue.serverTimestamp();
const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";

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
 * Ordem: 1) token global (se houver) 2) busca em todas as lojas com token MP
 * Exportado para uso em posPagamento.js (multi-loja).
 */
export async function resolveLojaAndPayment(paymentId, globalToken) {
  // 1) Tentar token global primeiro (fallback para lojas sem OAuth)
  if (globalToken && globalToken.length > 10) {
    const payment = await fetchPaymentFromMp(paymentId, globalToken);
    if (payment) {
      const lojaId = payment?.metadata?.lojaId || null;
      return { payment, lojaId };
    }
  }

  // 2) Iterar lojas para encontrar a que tem o payment
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
 * Token: resolve por loja (OAuth) ou global (fallback).
 */
export async function processMpWebhook(paymentId, globalToken) {
  if (!paymentId) return false;

  // 1) Resolver loja e buscar payment (token correto por loja)
  const { payment, lojaId } = await resolveLojaAndPayment(paymentId, globalToken);

  if (!payment) {
    console.warn("[mpWebhook] Payment não encontrado para:", paymentId);
    return false;
  }

  const orderId = payment.external_reference;
  const status = payment.status;

  let resolvedLojaId = lojaId || payment?.metadata?.lojaId || null;
  if (!resolvedLojaId && orderId) {
    resolvedLojaId = await findLojaIdByOrderId(orderId);
  }

  if (!orderId || !resolvedLojaId) {
    console.warn("[mpWebhook] orderId ou lojaId ausente:", { orderId, lojaId: resolvedLojaId });
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

  const webhookProcessedRef = db.collection(WEBHOOK_PROCESSED_COL).doc(String(paymentId));

  // 2) Early check: se já processamos, retornar imediatamente (evita transação desnecessária)
  const existingProcessed = await webhookProcessedRef.get();
  if (existingProcessed.exists) {
    console.log("[mpWebhook] Idempotente: paymentId já processado:", paymentId);
    return true;
  }

  // 3) Registrar status no payments (auditoria)
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

  // 4) Se aprovado: transação atômica (marca processado + pedido + estoque)
  if (status !== "approved") return true;

  let orderSnap = await orderRef.get();
  let isPrePedido = false;
  if (!orderSnap.exists) {
    orderSnap = await prePedidoRef.get();
    isPrePedido = orderSnap.exists;
  }
  if (!orderSnap.exists) {
    console.warn("[mpWebhook] Pedido não encontrado (nem pedidos nem pre_pedidos):", orderId);
    return false;
  }

  const orderRefToUse = orderSnap.ref;
  const order = orderSnap.data() || {};
  const alreadyPaid = !!order.paidAt;

  if (alreadyPaid) {
    await webhookProcessedRef.set(
      { processedAt: nowTs, orderId, lojaId: resolvedLojaId, status: "already_paid" },
      { merge: true }
    );
    return true;
  }

  const items = order.items || order.itens || [];

  // Transação atômica: garante que apenas uma execução processa (evita duplicar baixa de estoque)
  await getDb().runTransaction(async (tx) => {
    const procDoc = await tx.get(webhookProcessedRef);
    if (procDoc.exists) {
      return; // Já processado por outra requisição
    }

    const ordDoc = await tx.get(orderRefToUse);
    const ord = ordDoc.exists ? ordDoc.data() : {};
    if (ord.paidAt) {
      tx.set(webhookProcessedRef, { processedAt: nowTs, orderId, lojaId: resolvedLojaId, status: "already_paid" }, { merge: true });
      return;
    }

    tx.set(webhookProcessedRef, {
      paymentId: String(paymentId),
      orderId,
      lojaId: resolvedLojaId,
      processedAt: nowTs,
      status: "done",
    }, { merge: true });

    const updatePayload = {
      status: "paid",
      paidAt: nowTs,
      updatedAt: nowTs,
      paymentId: String(paymentId),
      paymentMethod: payment.payment_method_id,
    };
    if (isPrePedido) {
      updatePayload.statusPagamento = "aprovado";
    }
    tx.set(orderRefToUse, updatePayload, { merge: true });

    for (const it of items) {
      const pId = it.productId || it.produtosId || it.id || it.slug;
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

      if (temVariacao) {
        const prodSnap = await tx.get(produtosRef);
        const data = prodSnap.exists ? prodSnap.data() : {};
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
        const prodSnap = await tx.get(produtosRef);
        const data = prodSnap.exists ? prodSnap.data() : {};
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

  // Para pre_pedidos: criar venda em estoque_vendas (APK sync) e notificar admin
  if (isPrePedido) {
    const cliente = order.cliente || {};
    const clienteNome = cliente.nome || "Cliente";
    const total = Number(order.total || 0);
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
    await estoqueVendasRef.set(
      {
        id: vendaId,
        lojaId: resolvedLojaId,
        data: nowTs,
        total,
        desconto: 0,
        descontoValor: 0,
        formasPagamento: "Mercado Pago",
        frete: Number((order.frete || {}).valor || 0),
        clienteNome,
        produtosDescricao: itensVenda.map((i) => `${i.quantidade}x ${i.produtoNome}`).join(", "),
        quantidade: itensVenda.reduce((s, i) => s + i.quantidade, 0),
        preco: total - Number((order.frete || {}).valor || 0),
        tamanho: "",
        vendedor: "Catálogo Web",
        observacao: order.observacao || "",
        pagamentoDinheiro: 0,
        pagamentoPix: 0,
        pagamentoCartao: total,
        taxas: 0,
        custoProdutos: 0,
        itens: itensVenda,
        clienteId: (cliente.id || "").toString(),
        createdAt: nowTs,
        updatedAt: nowTs,
        status: "concluida",
        origemPrePedido: orderId,
      },
      { merge: true }
    );

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

  console.log("[mpWebhook] Processado:", paymentId, "pedido:", orderId, "loja:", resolvedLojaId, isPrePedido ? "(pre_pedido)" : "");
  return true;
}
