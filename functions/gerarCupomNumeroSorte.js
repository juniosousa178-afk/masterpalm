const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

// Função para gerar código aleatório
function gerarCodigo(prefixo = 'CUPOM', tamanho = 8) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let codigo = prefixo + '-';
  for (let i = 0; i < tamanho; i++) {
    codigo += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return codigo;
}

// Função para gerar número da sorte (5 dígitos — alinhado ao app)
function gerarNumeroSorte() {
  return String(Math.floor(10000 + Math.random() * 90000));
}

/**
 * Cloud Function: Gerar cupom e número da sorte após pedido finalizado
 *
 * Chamada: POST https://REGION-PROJECT.cloudfunctions.net/gerarCupomNumeroSorte
 * Body: {
 *   lojaId: string,
 *   clienteId: string,
 *   pedidoId: string,
 *   valorPedido: number,
 *   clienteEmail: string,
 *   clienteNome: string,
 *   clienteTelefone?: string
 * }
 */
exports.gerarCupomNumeroSorte = functions
  .region('southamerica-east1')
  .https.onRequest(async (req, res) => {
    // Configurar CORS
    res.set('Access-Control-Allow-Origin', '*');

    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type');
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).send('Método não permitido');
      return;
    }

    try {
      const {
        lojaId,
        clienteId,
        pedidoId,
        valorPedido,
        clienteEmail,
        clienteNome,
        clienteTelefone
      } = req.body;

      // Validações
      if (!lojaId || !clienteId || !pedidoId) {
        res.status(400).json({
          error: 'Parâmetros obrigatórios: lojaId, clienteId, pedidoId'
        });
        return;
      }

      const db = admin.firestore();

      // Gerar cupom de desconto (10% para próxima compra)
      const codigoCupom = gerarCodigo('CUPOM', 8);
      const dataValidade = new Date();
      dataValidade.setDate(dataValidade.getDate() + 30); // Válido por 30 dias

      const cupom = {
        codigo: codigoCupom,
        desconto: 10, // 10% de desconto
        validade: dataValidade.toLocaleDateString('pt-BR'),
        usado: false,
        criadoEm: new Date().toISOString(),
        pedidoOrigem: pedidoId,
      };

      // Gerar número da sorte
      const numeroSorte = gerarNumeroSorte();

      // Adicionar cupom e número ao documento do cliente
      const clienteRef = db
        .collection('lojas')
        .doc(lojaId)
        .collection('clientes')
        .doc(clienteId);

      await clienteRef.update({
        cupons: admin.firestore.FieldValue.arrayUnion(cupom),
        pedidos: admin.firestore.FieldValue.arrayUnion({
          id: pedidoId,
          numeroSorte: numeroSorte,
          data: new Date().toLocaleDateString('pt-BR'),
          valor: valorPedido || 0,
          status: 'Confirmado'
        })
      });

      // Registrar número da sorte na campanha ativa (coleção canônica: campanhas_sorteio)
      try {
        const agora = new Date();
        const campanhasSnapshot = await db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .where('ativa', '==', true)
          .where('dataInicio', '<=', agora)
          .where('dataFim', '>=', agora)
          .limit(1)
          .get();

        if (!campanhasSnapshot.empty) {
          const campanhaDoc = campanhasSnapshot.docs[0];
          // Verificar duplicidade por pedidoId
          const dup = await campanhaDoc.ref.collection('participantes')
            .where('pedidoId', '==', pedidoId)
            .limit(1)
            .get();
          if (!dup.empty) {
            console.warn('Participação duplicada para pedidoId:', pedidoId);
          } else {
          const participante = {
            clienteId,
            numeroSorte,
            pedidoId,
            vendaId: pedidoId,
            clienteNome: clienteNome || '',
            clienteEmail: clienteEmail || null,
            clienteTelefone: clienteTelefone || null,
            valorPedido: valorPedido ?? 0,
            valorCompra: valorPedido ?? 0,
            dataParticipacao: admin.firestore.FieldValue.serverTimestamp(),
            status: 'valido',
            sorteado: false,
            campanhaId: campanhaDoc.id,
            origem: 'gerar_cupom',
            nomeCliente: clienteNome || '',
            numeros: [numeroSorte],
            criadoEm: admin.firestore.FieldValue.serverTimestamp(),
          };
          await campanhaDoc.ref.collection('participantes').add(participante);
          }
        }
      } catch (campErr) {
        console.error('Erro ao registrar na campanha:', campErr);
        // Continuar mesmo se houver erro na campanha
      }

      res.status(200).json({
        success: true,
        cupom: cupom,
        numeroSorte: numeroSorte,
        clienteEmail: clienteEmail,
        clienteTelefone: clienteTelefone,
        message: 'Cupom e número da sorte gerados com sucesso!'
      });

    } catch (error) {
      console.error('Erro ao gerar cupom e número:', error);
      res.status(500).json({
        error: 'Erro ao gerar cupom e número da sorte',
        details: error.message
      });
    }
  });

/**
 * Cloud Function: Enviar cupom e número por email
 */
exports.enviarCupomEmail = functions
  .region('southamerica-east1')
  .https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');

    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type');
      res.status(204).send('');
      return;
    }

    try {
      const {
        email,
        nome,
        cupom,
        numeroSorte,
        lojaId,
        valorPedido
      } = req.body;

      if (!email || !nome) {
        res.status(400).json({ error: 'Email e nome são obrigatórios' });
        return;
      }

      // Configurar transporte de email (usar Gmail ou outro provedor)
      // IMPORTANTE: Configure as variáveis de ambiente no Firebase
      const transporter = nodemailer.createTransporter({
        service: 'gmail',
        auth: {
          user: functions.config().email?.user || process.env.EMAIL_USER,
          pass: functions.config().email?.pass || process.env.EMAIL_PASS,
        }
      });

      const htmlEmail = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 10px 10px; }
            .card { background: white; padding: 20px; margin: 15px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .cupom { background: #ffd700; color: #333; padding: 15px; text-align: center; font-size: 24px; font-weight: bold; border-radius: 8px; margin: 10px 0; letter-spacing: 2px; }
            .numero { background: #28a745; color: white; padding: 15px; text-align: center; font-size: 32px; font-weight: bold; border-radius: 8px; margin: 10px 0; letter-spacing: 3px; }
            .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
            .highlight { color: #667eea; font-weight: bold; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>🎉 Parabéns, ${nome}!</h1>
              <p>Obrigado pela sua compra!</p>
            </div>
            <div class="content">
              <div class="card">
                <h2>🎁 Seu Cupom de Desconto</h2>
                <p>Como agradecimento pela sua compra, você ganhou um cupom de <span class="highlight">${cupom.desconto}% de desconto</span> para sua próxima compra!</p>
                <div class="cupom">${cupom.codigo}</div>
                <p style="text-align: center; color: #666; font-size: 14px;">Válido até ${cupom.validade}</p>
              </div>

              <div class="card">
                <h2>🎰 Seu Número da Sorte</h2>
                <p>Você está concorrendo a prêmios incríveis! Guarde bem seu número da sorte:</p>
                <div class="numero">${numeroSorte}</div>
                <p style="text-align: center; color: #666; font-size: 14px;">Boa sorte! 🍀</p>
              </div>

              <div class="card">
                <h3>📦 Resumo do Pedido</h3>
                <p><strong>Valor:</strong> R$ ${(valorPedido || 0).toFixed(2)}</p>
                <p><strong>Loja:</strong> ${lojaId}</p>
              </div>
            </div>
            <div class="footer">
              <p>Este é um email automático, por favor não responda.</p>
              <p>© 2025 ${lojaId}. Todos os direitos reservados.</p>
            </div>
          </div>
        </body>
        </html>
      `;

      await transporter.sendMail({
        from: `"${lojaId}" <${functions.config().email?.user || 'noreply@loja.com'}>`,
        to: email,
        subject: `🎁 Seu Cupom e Número da Sorte - Pedido Confirmado!`,
        html: htmlEmail,
      });

      res.status(200).json({ success: true, message: 'Email enviado com sucesso!' });

    } catch (error) {
      console.error('Erro ao enviar email:', error);
      res.status(500).json({ error: 'Erro ao enviar email', details: error.message });
    }
  });
