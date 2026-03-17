// functions/src/posPagamento.js
/**
 * Cloud Functions para processar pós-pagamento
 *
 * Funcionalidades:
 * - Webhook do Mercado Pago
 * - Baixa de estoque
 * - Geração de número da sorte
 * - Envio de Email e WhatsApp
 */

import { onRequest } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import axios from "axios";
import nodemailer from "nodemailer";

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

      // Buscar detalhes do pagamento no Mercado Pago
      const payment = await buscarPagamentoMercadoPago(paymentId);

      if (!payment) {
        console.error('❌ Não foi possível buscar detalhes do pagamento');
        return res.status(200).send('OK');
      }

      const status = payment.status;
      const externalReference = payment.external_reference;

      console.log(`📊 Status do pagamento: ${status}`);
      console.log(`🔗 External Reference (vendaId): ${externalReference}`);

      // Se o pagamento foi aprovado, processar pós-pagamento
      if (status === 'approved' && externalReference) {
        await processarPosPagamento(externalReference, payment);
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

/**
 * Busca detalhes do pagamento no Mercado Pago
 */
async function buscarPagamentoMercadoPago(paymentId) {
  try {
    // Buscar Access Token do Firestore
    // IMPORTANTE: Se você tiver múltiplas lojas, precisará determinar qual loja
    // baseado em algum campo do payment ou external_reference

    // Por enquanto, vamos buscar da loja 'masterpalm' (ajuste conforme necessário)
    const lojaId = 'masterpalm';

    const configDoc = await db
      .collection('lojas')
      .doc(lojaId)
      .collection('config')
      .doc('payments')
      .get();

    if (!configDoc.exists) {
      console.error('❌ Configuração de pagamentos não encontrada');
      return null;
    }

    const config = configDoc.data();
    const accessToken = config.mp?.access_token || config.mp?.token;

    if (!accessToken) {
      console.error('❌ Access Token do Mercado Pago não encontrado');
      return null;
    }

    // Consultar pagamento
    const response = await axios.get(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      }
    );

    return response.data;
  } catch (error) {
    console.error('❌ Erro ao buscar pagamento:', error.response?.data || error.message);
    return null;
  }
}

/**
 * Processa ações pós-pagamento
 */
async function processarPosPagamento(vendaId, payment) {
  try {
    console.log(`🎯 Processando pós-pagamento para venda: ${vendaId}`);

    // Buscar pedido no Firestore usando collectionGroup
    const pedidosSnapshot = await db
      .collectionGroup('pedidos')
      .where('vendaId', '==', vendaId)
      .limit(1)
      .get();

    if (pedidosSnapshot.empty) {
      console.error('❌ Pedido não encontrado:', vendaId);
      return;
    }

    const pedidoDoc = pedidosSnapshot.docs[0];
    const pedidoData = pedidoDoc.data();
    const lojaId = pedidoDoc.ref.parent.parent.id;

    console.log(`🏪 Loja ID: ${lojaId}`);
    console.log(`📦 Pedido encontrado:`, JSON.stringify(pedidoData, null, 2));

    // 1. Atualizar status do pedido
    await pedidoDoc.ref.update({
      status: 'pago',
      dataAtualizacao: FieldValue.serverTimestamp(),
      mercadoPagoPaymentId: payment.id,
    });

    console.log('✅ Status atualizado para: pago');

    // 2. Baixar estoque
    await baixarEstoque(lojaId, pedidoData.itens || []);

    // 3. Registrar participação em campanhas ativas e gerar números da sorte
    const campanhaResult = await registrarParticipacaoCampanha(
      lojaId,
      pedidoData.cliente,
      pedidoData.total || 0
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
      const productId = item.productId;

      if (!productId) {
        console.warn('⚠️ Item sem productId:', item.nome);
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
 * Registra participação em campanhas ativas e gera números da sorte
 */
async function registrarParticipacaoCampanha(lojaId, cliente, valorCompra) {
  try {
    console.log(`🎯 Verificando campanhas ativas para valor: R$ ${valorCompra}`);

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
      const valorMinimo = data.valorMinimo || 0;
      const x = data.valorX || 50;

      if (valorCompra < valorMinimo) {
        console.log(`⏭️ Campanha ${doc.id}: valor mínimo não atingido (R$ ${valorMinimo})`);
        continue;
      }

      const quantidadeNumeros = Math.floor(valorCompra / x);
      if (quantidadeNumeros <= 0) continue;

      console.log(`✅ Campanha ${doc.id}: gerando ${quantidadeNumeros} números`);

      // Gerar números sequenciais
      const numerosGerados = await gerarNumerosCampanha(lojaId, quantidadeNumeros);
      todosNumeros.push(...numerosGerados);

      // Salvar participação
      await doc.ref.collection('participantes').add({
        clienteId: cliente?.id || null,
        nomeCliente: cliente?.nome || 'Cliente',
        clienteEmail: cliente?.email || null,
        clienteTelefone: cliente?.telefone || null,
        valorCompra: valorCompra,
        dataCompra: agora,
        numeros: numerosGerados,
        criadoEm: agora,
      });

      todasCampanhas.push({
        id: doc.id,
        nome: data.nome || '',
        descricao: data.descricao || '',
        premioDescricao: data.premioDescricao || '',
        dataSorteio: data.dataSorteio,
        numeros: numerosGerados,
      });

      console.log(`🎲 Números gerados para campanha ${doc.id}: ${numerosGerados.join(', ')}`);
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
