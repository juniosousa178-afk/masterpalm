// functions/src/posPagamento.js
/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║  ⛔ DEPRECADO — NÃO USE EM PRODUÇÃO                                        ║
 * ║  Este arquivo NÃO está em uso. O webhook mercadopagoWebhook NÃO é          ║
 * ║  exportado em index.js. Uso acidental pode gerar inconsistência.           ║
 * ║  Fluxo correto: mpWebhook → processMpWebhook (mpWebhookHandler.js)         ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 *
 * Mantido apenas para referência. Não configurar no Mercado Pago.
 */

import { onRequest } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import axios from "axios";
import nodemailer from "nodemailer";

import { resolveLojaAndPayment } from "./mpWebhookHandler.js";
import { resolveLojaIdByOrderId } from "./orderLojaIndex.js";

const db = getFirestore();

// ============================================================================
// WEBHOOK DO MERCADO PAGO
// ============================================================================

/**
 * Webhook para receber notificações do Mercado Pago
 *
 * Configurar no Mercado Pago:
 * URL: https://southamerica-east1-YOUR_PROJECT.cloudfunctions.net/mercadopagoWebhook
 * Eventos: payment (pagamento criado/atualizado)
 */
export const mercadopagoWebhook = onRequest(async (req, res) => {
  try {
    console.log('🔔 Webhook recebido do Mercado Pago:', JSON.stringify(req.body));

    const { type, data, action } = req.body;

    // Mercado Pago envia notificações no formato:
    // { action: "payment.created", data: { id: "123456789" }, type: "payment" }
    if (type === 'payment' || action?.includes('payment')) {
      const paymentId = data?.id;

      if (!paymentId) {
        console.warn('⚠️ Webhook sem payment ID');
        return res.status(200).send('OK');
      }

      console.log(`💳 Processando pagamento ID: ${paymentId}`);

      // Buscar detalhes do pagamento no Mercado Pago (multi-loja: tenta token global, depois cada loja)
      const globalToken = process.env.MP_ACCESS_TOKEN || (functions.config().mp?.access_token || "") || "";
      const { payment, lojaId } = await resolveLojaAndPayment(paymentId, globalToken);

      if (!payment) {
        console.error('❌ Não foi possível buscar detalhes do pagamento');
        return res.status(200).send('OK');
      }

      const status = payment.status;
      const externalReference = payment.external_reference;
      const lojaIdFromPayment = lojaId || payment.metadata?.lojaId || null;

      console.log(`📊 Status do pagamento: ${status}`);
      console.log(`🔗 External Reference (orderId): ${externalReference}`);

      // Se o pagamento foi aprovado, processar pós-pagamento (multi-tenant: lojaId do payment ou resolvido por orderId)
      if (status === 'approved' && externalReference) {
        await processarPosPagamento(externalReference, payment, lojaIdFromPayment);
      } else {
        console.log(`ℹ️ Pagamento não processado (status: ${status})`);
      }
    }

    res.status(200).send('OK');
  } catch (error) {
    console.error('❌ Erro ao processar webhook:', error);
    // Retornar 200 para evitar reenvios do Mercado Pago
    res.status(200).send('OK');
  }
});

/** Extrai lojaId do path do documento (suporta lojas/X/pedidos/Y e lojas/X/vendas/V/pedidos/Z) */
function getLojaIdFromDocPath(ref) {
  const parts = (ref.path || '').split('/');
  const i = parts.indexOf('lojas');
  return i >= 0 && parts[i + 1] ? parts[i + 1] : null;
}

/**
 * Processa ações pós-pagamento.
 * Multi-tenant: lojaId do payment.metadata ou resolvido por orderId (order_loja_index / pre_pedidos / pedidos).
 * Fluxo catálogo: external_reference = pre_pedido doc id → busca em pre_pedidos.
 * Fluxo legado: external_reference = vendaId → fallback collectionGroup pedidos.
 */
async function processarPosPagamento(orderId, payment, lojaIdFromPayment = null) {
  try {
    console.log(`🎯 Processando pós-pagamento para orderId: ${orderId}`);

    let lojaId = lojaIdFromPayment || null;
    let pedidoDoc = null;
    let pedidoData = null;

    if (lojaId) {
      const prePedidoSnap = await db.collection('lojas').doc(lojaId).collection('pre_pedidos').doc(orderId).get();
      if (prePedidoSnap.exists) {
        pedidoDoc = prePedidoSnap;
        pedidoData = prePedidoSnap.data();
        console.log(`📦 Pré-pedido encontrado (catálogo): lojas/${lojaId}/pre_pedidos/${orderId}`);
      }
      if (!pedidoDoc) {
        const pedidoSnap = await db.collection('lojas').doc(lojaId).collection('pedidos').doc(orderId).get();
        if (pedidoSnap.exists) {
          pedidoDoc = pedidoSnap;
          pedidoData = pedidoSnap.data();
          console.log(`📦 Pedido encontrado: lojas/${lojaId}/pedidos/${orderId}`);
        }
      }
    }

    if (!pedidoDoc) {
      lojaId = await resolveLojaIdByOrderId(db, orderId);
      if (lojaId) {
        const prePedidoSnap = await db.collection('lojas').doc(lojaId).collection('pre_pedidos').doc(orderId).get();
        if (prePedidoSnap.exists) {
          pedidoDoc = prePedidoSnap;
          pedidoData = prePedidoSnap.data();
          console.log(`📦 Pré-pedido encontrado (índice): lojas/${lojaId}/pre_pedidos/${orderId}`);
        }
        if (!pedidoDoc) {
          const pedidoSnap = await db.collection('lojas').doc(lojaId).collection('pedidos').doc(orderId).get();
          if (pedidoSnap.exists) {
            pedidoDoc = pedidoSnap;
            pedidoData = pedidoSnap.data();
            console.log(`📦 Pedido encontrado (índice): lojas/${lojaId}/pedidos/${orderId}`);
          }
        }
      }
    }

    if (!pedidoDoc) {
      const pedidosSnapshot = await db.collectionGroup('pedidos').where('vendaId', '==', orderId).limit(1).get();
      if (!pedidosSnapshot.empty) {
        pedidoDoc = pedidosSnapshot.docs[0];
        pedidoData = pedidoDoc.data();
        lojaId = getLojaIdFromDocPath(pedidoDoc.ref) || pedidoDoc.ref.parent?.parent?.id || pedidoData.lojaId;
        console.log(`📦 Pedido encontrado (legado vendaId): lojaId=${lojaId}`);
      }
    }

    if (!pedidoDoc || !pedidoData || !lojaId) {
      console.error('❌ Pedido não encontrado (pre_pedidos nem pedidos):', orderId);
      return;
    }

    console.log(`🏪 Loja ID: ${lojaId}`);
    console.log(`📦 Pedido encontrado:`, JSON.stringify(pedidoData, null, 2));

    // 1. Atualizar status do pedido (pre_pedidos: statusPagamento; pedidos: status)
    const isPrePedido = (pedidoDoc.ref.path || "").includes("/pre_pedidos/");
    const updatePayload = {
      dataAtualizacao: FieldValue.serverTimestamp(),
      mercadoPagoPaymentId: payment.id,
    };
    if (isPrePedido) {
      updatePayload.statusPagamento = "aprovado";
      updatePayload.status = "confirmado";
    } else {
      updatePayload.status = "pago";
    }
    await pedidoDoc.ref.update(updatePayload);

    console.log('✅ Status atualizado para: pago');

    // 2. Baixar estoque
    await baixarEstoque(lojaId, pedidoData.itens || []);

    // 3. Registrar participação em campanhas ativas e gerar números da sorte
    const pedidoId = pedidoDoc.id;
    const vendaIdPedido = pedidoData.vendaId || orderId;
    const campanhaResult = await registrarParticipacaoCampanha(
      lojaId,
      pedidoData.cliente,
      pedidoData.total || 0,
      pedidoId,
      vendaIdPedido
    );

    // 4. Enviar notificações com os números da sorte
    if (campanhaResult.temCampanha) {
      await enviarNotificacoes(
        lojaId,
        pedidoData,
        campanhaResult.numeros,
        campanhaResult.campanhas,
        pedidoData.cupomRoleta || null
      );
    } else {
      console.log('ℹ️ Nenhuma campanha ativa encontrada');
    }

    console.log('✅ Pós-pagamento processado com sucesso!');
  } catch (error) {
    console.error('❌ Erro ao processar pós-pagamento:', error);
  }
}

/**
 * Baixa estoque dos produtos vendidos
 */
async function baixarEstoque(lojaId, itens) {
  try {
    console.log(`📦 Baixando estoque de ${itens.length} itens...`);

    for (const item of itens) {
      const productId = item.productId || item.produtosId || item.id;

      if (!productId) {
        console.warn('⚠️ Item sem productId/produtosId:', item.nome);
        continue;
      }

      const productRef = db
        .collection('lojas')
        .doc(lojaId)
        .collection('produtos')
        .doc(productId);

      const productDoc = await productRef.get();

      if (!productDoc.exists) {
        console.warn('⚠️ Produto não encontrado:', productId);
        continue;
      }

      const productData = productDoc.data();
      const estoqueAtual = productData.estoque ?? productData.quantidade ?? 0;
      const quantidade = item.quantidade || 1;
      const novoEstoque = Math.max(0, estoqueAtual - quantidade);

      const updateData = {
        estoque: novoEstoque,
        quantidade: novoEstoque,
        estoque_atual: novoEstoque,
        ultimaVenda: FieldValue.serverTimestamp(),
      };
      if (novoEstoque <= 0) updateData.ativo = false;
      await productRef.update(updateData);

      console.log(`📦 Estoque atualizado: ${item.nome} (${estoqueAtual} → ${novoEstoque})`);
    }

    console.log('✅ Estoque baixado com sucesso!');
  } catch (error) {
    console.error('❌ Erro ao baixar estoque:', error);
  }
}

/**
 * Gera número da sorte de 5 dígitos (10000-99999) — alinhado ao app
 */
function gerarNumeroSorteAleatorio() {
  return String(Math.floor(10000 + Math.random() * 90000));
}

/**
 * Registra participação em campanhas ativas e gera número da sorte
 * Schema canônico: dataParticipacao, pedidoId, vendaId, valorPedido, numeroSorte, status, sorteado
 */
async function registrarParticipacaoCampanha(lojaId, cliente, valorCompra, pedidoId, vendaId) {
  try {
    console.log(`🎯 Verificando campanhas ativas para valor: R$ ${valorCompra} | pedidoId=${pedidoId} | vendaId=${vendaId}`);

    const agora = FieldValue.serverTimestamp();
    const agoraDate = new Date();

    // Buscar campanhas ativas e dentro do período
    const campanhasSnapshot = await db
      .collection('lojas')
      .doc(lojaId)
      .collection('campanhas_sorteio')
      .where('ativa', '==', true)
      .where('dataInicio', '<=', agoraDate)
      .where('dataFim', '>=', agoraDate)
      .get();

    if (campanhasSnapshot.empty) {
      return {
        temCampanha: false,
        numeros: [],
        campanhas: [],
      };
    }

    const todasCampanhas = [];
    const todosNumeros = [];

    for (const doc of campanhasSnapshot.docs) {
      const data = doc.data();
      const valorMinimo = (data.valorMinimo ?? data.valor_minimo ?? 0);
      const valorX = data.valorX || data.valorXPorNumero || 50;

      if (valorCompra < valorMinimo) {
        console.log(`⏭️ Campanha ${doc.id}: valor mínimo não atingido (R$ ${valorMinimo})`);
        continue;
      }

      // Alinhado ao app: 1 número por venda quando >= valorMinimo (fallback valorX para compatibilidade)
      const usaUmNumeroPorVenda = valorMinimo > 0;
      const quantidadeNumeros = usaUmNumeroPorVenda
        ? 1
        : Math.max(1, Math.floor(valorCompra / valorX));

      if (quantidadeNumeros <= 0) continue;

      // Verificar duplicidade (pedidoId ou vendaId já participou)
      let jaParticipou = false;
      if (pedidoId) {
        const dupPedido = await doc.ref.collection('participantes').where('pedidoId', '==', pedidoId).limit(1).get();
        if (!dupPedido.empty) jaParticipou = true;
      }
      if (!jaParticipou && vendaId) {
        const dupVenda = await doc.ref.collection('participantes').where('vendaId', '==', vendaId).limit(1).get();
        if (!dupVenda.empty) jaParticipou = true;
      }
      if (jaParticipou) {
        console.log(`⏭️ Campanha ${doc.id}: participação duplicada para pedidoId=${pedidoId} vendaId=${vendaId}`);
        continue;
      }

      console.log(`✅ Campanha ${doc.id}: gerando ${quantidadeNumeros} número(s)`);

      // Regra oficial: sempre aleatório 5 dígitos (evita sequenciais e comportamento ambíguo)
      const numerosGerados = [];
      for (let i = 0; i < quantidadeNumeros; i++) {
        numerosGerados.push(gerarNumeroSorteAleatorio());
      }
      const numeroSorte = numerosGerados[0];

      todosNumeros.push(...numerosGerados);

      // Schema canônico + campos legados para compatibilidade
      const participante = {
        // Canônico (app)
        dataParticipacao: agora,
        pedidoId: pedidoId || null,
        vendaId: vendaId || null,
        valorPedido: valorCompra,
        numeroSorte,
        status: 'valido',
        sorteado: false,
        clienteNome: cliente?.nome || 'Cliente',
        clienteEmail: cliente?.email || null,
        clienteTelefone: cliente?.telefone || null,
        campanhaId: doc.id,
        clienteId: cliente?.id || null,
        origem: 'pos_pagamento',
        // Legado (fallback leitura)
        nomeCliente: cliente?.nome || 'Cliente',
        valorCompra,
        numeros: numerosGerados,
        criadoEm: agora,
      };

      await doc.ref.collection('participantes').add(participante);

      todasCampanhas.push({
        id: doc.id,
        nome: data.nome || '',
        descricao: data.descricao || '',
        premioDescricao: data.premioDescricao || '',
        dataSorteio: data.dataSorteio,
        numeros: numerosGerados,
      });

      console.log(`🎲 Número gerado para campanha ${doc.id}: ${numeroSorte}`);
    }

    return {
      temCampanha: todasCampanhas.length > 0,
      numeros: todosNumeros,
      campanhas: todasCampanhas,
    };
  } catch (error) {
    console.error('❌ Erro ao registrar participação em campanha:', error);
    return {
      temCampanha: false,
      numeros: [],
      campanhas: [],
    };
  }
}

/**
 * Gera números sequenciais para a campanha usando transação
 */
async function gerarNumerosCampanha(lojaId, quantidade) {
  if (quantidade <= 0) return [];

  const counterRef = db
    .collection('lojas')
    .doc(lojaId)
    .collection('campanhas_sorteio_config')
    .doc('numeracao');

  try {
    const numeros = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(counterRef);

      let ultimo = 10000; // Inicia na casa das dezenas de milhar
      if (snap.exists) {
        ultimo = snap.data().ultimo || 10000;
      }

      const novoUltimo = ultimo + quantidade;

      transaction.set(counterRef, { ultimo: novoUltimo }, { merge: true });

      const numerosGerados = [];
      for (let i = 1; i <= quantidade; i++) {
        numerosGerados.push(String(ultimo + i).padStart(5, '0'));
      }

      return numerosGerados;
    });

    return numeros;
  } catch (error) {
    console.error('❌ Erro ao gerar números da campanha:', error);
    return [];
  }
}

/**
 * Envia notificações por Email e WhatsApp
 */
async function enviarNotificacoes(lojaId, pedidoData, numeros, campanhas, cupomRoleta) {
  try {
    const { cliente, total } = pedidoData;

    if (!cliente) {
      console.warn('⚠️ Pedido sem dados de cliente');
      return;
    }

    // Buscar dados da loja
    const lojaDoc = await db
      .collection('lojas')
      .doc(lojaId)
      .get();

    const lojaNome = lojaDoc.exists ? (lojaDoc.data().nome || 'Loja') : 'Loja';

    // Enviar Email
    if (cliente.email) {
      await enviarEmail(
        cliente.email,
        cliente.nome || 'Cliente',
        lojaNome,
        numeros,
        campanhas,
        cupomRoleta,
        total || 0
      );
    } else {
      console.log('ℹ️ Cliente sem email, pulando envio');
    }

    // Enviar WhatsApp
    if (cliente.telefone) {
      await enviarWhatsApp(
        cliente.telefone,
        cliente.nome || 'Cliente',
        lojaNome,
        numeros,
        campanhas,
        cupomRoleta
      );
    } else {
      console.log('ℹ️ Cliente sem telefone, pulando envio de WhatsApp');
    }

    console.log('✅ Notificações enviadas!');
  } catch (error) {
    console.error('❌ Erro ao enviar notificações:', error);
  }
}

/**
 * Envia email com números da sorte
 */
async function enviarEmail(email, nome, lojaNome, numeros, campanhas, cupomRoleta, valorTotal) {
  try {
    const temCupom = cupomRoleta && cupomRoleta.codigo;

    // Formatador de data
    const formatarData = (timestamp) => {
      if (!timestamp) return '';
      const data = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
      return data.toLocaleDateString('pt-BR');
    };

    // Montar seção de números
    let numerosHtml = '';
    if (numeros.length === 1) {
      numerosHtml = `
        <div class="numero-sorte">
          <h2>🎟️ Seu Número da Sorte:</h2>
          <div class="numero">${numeros[0]}</div>
        </div>
      `;
    } else {
      numerosHtml = `
        <div class="numero-sorte">
          <h2>🎟️ Seus Números da Sorte (${numeros.length}):</h2>
          <div style="font-size: 24px; font-weight: bold; letter-spacing: 3px;">
            ${numeros.join(' • ')}
          </div>
        </div>
      `;
    }

    // Montar seção de campanhas
    let campanhasHtml = '';
    if (campanhas.length > 0) {
      campanhasHtml = '<h3 style="margin-top: 30px;">📋 Detalhes das Campanhas:</h3>';
      for (const campanha of campanhas) {
        campanhasHtml += `
          <div style="background: #f8f9fa; padding: 15px; border-radius: 10px; margin: 15px 0;">
            <h4 style="margin: 0 0 10px 0; color: #764ba2;">🏆 ${campanha.nome}</h4>
            ${campanha.descricao ? `<p style="margin: 5px 0;">${campanha.descricao}</p>` : ''}
            <p style="margin: 5px 0;"><strong>Prêmio:</strong> ${campanha.premioDescricao}</p>
            ${campanha.dataSorteio ? `<p style="margin: 5px 0;"><strong>Data do sorteio:</strong> ${formatarData(campanha.dataSorteio)}</p>` : ''}
          </div>
        `;
      }
    }

    const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { padding: 30px; }
    .numero-sorte { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin: 20px 0; }
    .numero-sorte h2 { margin: 0 0 10px 0; font-size: 18px; }
    .numero-sorte .numero { font-size: 48px; font-weight: bold; letter-spacing: 5px; }
    .cupom { background: #fff3cd; border: 2px dashed #ffc107; padding: 20px; border-radius: 10px; margin: 20px 0; text-align: center; }
    .cupom-codigo { font-size: 24px; font-weight: bold; color: #856404; letter-spacing: 2px; }
    .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Parabéns, ${nome}!</h1>
    </div>
    <div class="content">
      <p>Obrigado por sua compra de <strong>R$ ${Number(valorTotal).toFixed(2)}</strong> na <strong>${lojaNome}</strong>!</p>

      ${numerosHtml}

      <p style="text-align: center; color: #28a745; font-weight: bold;">
        ✅ Você está participando da nossa promoção!
      </p>

      <p>Seus números foram registrados e você está concorrendo a prêmios incríveis. Boa sorte! 🍀</p>

      ${campanhasHtml}

      ${temCupom ? `
      <div class="cupom">
        <h3 style="margin: 0 0 10px 0; color: #856404;">🎁 Você também ganhou na Roleta da Sorte!</h3>
        <p style="margin: 5px 0; color: #856404;">Cupom de desconto de <strong>${cupomRoleta.desconto}%</strong> para sua próxima compra:</p>
        <div class="cupom-codigo">${cupomRoleta.codigo}</div>
        <p style="margin: 10px 0 0 0; font-size: 12px; color: #856404;">
          📅 Válido por 60 dias | 🔄 Use na próxima compra
        </p>
      </div>
      ` : ''}

      <p style="margin-top: 30px; text-align: center;">
        Obrigado por comprar conosco! 💜
      </p>
    </div>
    <div class="footer">
      <p>${lojaNome} - Todos os direitos reservados</p>
      <p>Este é um email automático, por favor não responda.</p>
    </div>
  </div>
</body>
</html>
`;

    // Buscar credenciais do Firebase Config
    const config = functions.config();
    const emailUser = config.email?.user;
    const emailPass = config.email?.pass;

    if (!emailUser || !emailPass) {
      console.warn('⚠️ Credenciais de email não configuradas. Use: firebase functions:config:set email.user="seu-email@gmail.com" email.pass="senha-app"');
      console.log('📧 Email que seria enviado para:', email);
      return;
    }

    // Configurar transporter do nodemailer
    const transporter = nodemailer.createTransporter({
      service: 'gmail',
      auth: {
        user: emailUser,
        pass: emailPass,
      },
    });

    await transporter.sendMail({
      from: `"${lojaNome}" <${emailUser}>`,
      to: email,
      subject: `🎉 Parabéns! Você está concorrendo - ${lojaNome}`,
      html: html,
    });

    console.log('📧 Email enviado para:', email);
  } catch (error) {
    console.error('❌ Erro ao enviar email:', error);
  }
}

/**
 * Envia mensagem via WhatsApp
 */
async function enviarWhatsApp(telefone, nome, lojaNome, numeros, campanhas, cupomRoleta) {
  try {
    const temCupom = cupomRoleta && cupomRoleta.codigo;

    // Formatador de data
    const formatarData = (timestamp) => {
      if (!timestamp) return '';
      const data = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
      return data.toLocaleDateString('pt-BR');
    };

    // Montar lista de números
    let numerosTexto = '';
    if (numeros.length === 1) {
      numerosTexto = `🎟️ *Seu Número da Sorte:*\n*${numeros[0]}*`;
    } else {
      numerosTexto = `🎟️ *Seus Números da Sorte (${numeros.length}):*\n`;
      numerosTexto += numeros.map(n => `*${n}*`).join(' • ');
    }

    // Montar detalhes das campanhas
    let campanhasTexto = '';
    if (campanhas.length > 0) {
      campanhasTexto = '\n\n📋 *Detalhes das Campanhas:*\n';
      for (const campanha of campanhas) {
        campanhasTexto += `\n🏆 *${campanha.nome}*\n`;
        if (campanha.descricao) {
          campanhasTexto += `${campanha.descricao}\n`;
        }
        campanhasTexto += `Prêmio: ${campanha.premioDescricao}\n`;
        if (campanha.dataSorteio) {
          campanhasTexto += `Data do sorteio: ${formatarData(campanha.dataSorteio)}\n`;
        }
      }
    }

    const mensagem = `
🎉 *Parabéns, ${nome}!*

Obrigado por sua compra na *${lojaNome}*!

${numerosTexto}

✅ Você está participando da nossa promoção!

Seus números foram registrados e você está concorrendo a prêmios incríveis. Boa sorte! 🍀
${campanhasTexto}
${temCupom ? `

🎁 *Você também ganhou na Roleta da Sorte!*

Cupom de *${cupomRoleta.desconto}% OFF* para sua próxima compra:

*${cupomRoleta.codigo}*

📅 Válido por 60 dias
🔄 Use na próxima compra
` : ''}

Obrigado por comprar conosco! 💜
    `.trim();

    // IMPORTANTE: Configure sua API do WhatsApp Business
    // Opções: Twilio, MessageBird, WhatsApp Business API oficial, etc.

    // Exemplo com Evolution API (ajuste conforme seu serviço):
    const whatsappApiUrl = process.env.WHATSAPP_API_URL;
    const whatsappApiKey = process.env.WHATSAPP_API_KEY;

    if (!whatsappApiUrl || !whatsappApiKey) {
      console.warn('⚠️ WhatsApp API não configurada. Mensagem não enviada.');
      console.log('📱 Mensagem que seria enviada:', mensagem);
      return;
    }

    await axios.post(
      whatsappApiUrl,
      {
        phone: telefone,
        message: mensagem,
      },
      {
        headers: {
          'Authorization': `Bearer ${whatsappApiKey}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('📱 WhatsApp enviado para:', telefone);
  } catch (error) {
    console.error('❌ Erro ao enviar WhatsApp:', error);
    console.log('📱 Mensagem não enviada para:', telefone);
  }
}
