/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require('firebase-functions');
const {onDocumentUpdated, onDocumentCreated} = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// =============================================================================
// SISTEMA DE COMISSÕES - Cloud Functions
// =============================================================================

/**
 * Calcula e registra comissão quando um pedido pendente é confirmado (pago)
 * Dispara quando o campo 'status' muda para 'pago' em pedidos_pendentes
 */
exports.calcularComissaoPagamento = onDocumentUpdated(
  'lojas/{lojaId}/pedidos_pendentes/{pedidoId}',
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const lojaId = event.params.lojaId;
    const pedidoId = event.params.pedidoId;

    // Verificar se o status mudou para 'pago'
    if (beforeData.status === afterData.status || afterData.status !== 'pago') {
      logger.info(`[COMISSAO] Pedido ${pedidoId} - Status não mudou para pago, ignorando.`);
      return null;
    }

    // Verificar se há vendedor associado (tracking)
    const vendedorUid = afterData.vendedorUid || afterData.vendedorId;
    if (!vendedorUid) {
      logger.info(`[COMISSAO] Pedido ${pedidoId} - Sem vendedor associado, ignorando.`);
      return null;
    }

    logger.info(`[COMISSAO] Pedido ${pedidoId} pago - Calculando comissão para ${vendedorUid}`);

    try {
      // Buscar configuração de comissão
      const configDoc = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('configuracoes')
        .doc('comissao')
        .get();

      const config = configDoc.exists ? configDoc.data() : {
        comissaoGlobalPercent: 5.0,
        excluirFreteDaBase: true,
        descontoReduzBase: true,
      };

      // Buscar configuração específica do vendedor
      const vendedorConfigDoc = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('comissoes_vendedores')
        .doc(vendedorUid)
        .get();

      const vendedorConfig = vendedorConfigDoc.exists ? vendedorConfigDoc.data() : null;

      // Determinar percentual
      const percentual = vendedorConfig?.comissaoPercentual ?? config.comissaoGlobalPercent;

      // Calcular base de comissão
      const subtotal = afterData.subtotal || 0;
      const frete = afterData.frete?.valor || 0;
      const desconto = afterData.desconto || 0;

      let baseComissao = subtotal;
      if (config.descontoReduzBase) {
        baseComissao -= desconto;
      }
      if (baseComissao < 0) baseComissao = 0;

      // Calcular valor da comissão
      let comissaoValor = baseComissao * (percentual / 100);

      // Aplicar limites
      const minimo = config.comissaoMinimaValor || 0;
      const maximo = config.comissaoMaximaValor || 0;

      if (minimo > 0 && comissaoValor < minimo) {
        comissaoValor = minimo;
      }
      if (maximo > 0 && comissaoValor > maximo) {
        comissaoValor = maximo;
      }

      // Criar registro de comissão
      const comissaoId = `com_${Date.now()}`;
      const comissaoData = {
        comissaoId,
        lojaId,
        vendaId: pedidoId,
        vendedorUid,
        vendedorEmail: afterData.vendedorEmail || '',
        vendedorNome: afterData.vendedorNome || '',
        trackingId: afterData.trackingId || null,
        subtotalProdutos: subtotal,
        frete,
        desconto,
        totalVenda: afterData.total || 0,
        baseComissao,
        comissaoPercentual: percentual,
        comissaoValor,
        status: 'confirmado',
        origem: 'catalogo',
        statusPagamentoVenda: 'pago',
        dataVenda: afterData.dataHora || admin.firestore.FieldValue.serverTimestamp(),
        dataConfirmacao: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db
        .collection('lojas')
        .doc(lojaId)
        .collection('comissoes')
        .doc(comissaoId)
        .set(comissaoData);

      // Atualizar tracking como utilizado
      if (afterData.trackingId) {
        await db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .doc(afterData.trackingId)
          .update({
            utilizado: true,
            vendaId: pedidoId,
            utilizadoEm: admin.firestore.FieldValue.serverTimestamp(),
          });
      }

      logger.info(`[COMISSAO] ✅ Comissão registrada: ${comissaoId}`);
      logger.info(`   Valor: R$ ${comissaoValor.toFixed(2)} (${percentual}%)`);
      logger.info(`   Vendedor: ${afterData.vendedorNome || vendedorUid}`);

      return { success: true, comissaoId, valor: comissaoValor };
    } catch (error) {
      logger.error(`[COMISSAO] ❌ Erro ao calcular comissão: ${error.message}`);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Estorna comissão automaticamente quando pedido é cancelado
 */
exports.estornarComissaoCancelamento = onDocumentUpdated(
  'lojas/{lojaId}/pedidos_pendentes/{pedidoId}',
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const lojaId = event.params.lojaId;
    const pedidoId = event.params.pedidoId;

    // Verificar se o status mudou para 'cancelado'
    if (beforeData.status === afterData.status || afterData.status !== 'cancelado') {
      return null;
    }

    logger.info(`[COMISSAO] Pedido ${pedidoId} cancelado - Verificando estorno`);

    try {
      // Buscar configuração
      const configDoc = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('configuracoes')
        .doc('comissao')
        .get();

      const config = configDoc.exists ? configDoc.data() : { estornoAutomaticoEmCancelamento: true };

      if (!config.estornoAutomaticoEmCancelamento) {
        logger.info(`[COMISSAO] Estorno automático desabilitado para loja ${lojaId}`);
        return null;
      }

      // Buscar comissões do pedido
      const comissoesSnapshot = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('comissoes')
        .where('vendaId', '==', pedidoId)
        .where('status', 'in', ['pendente', 'confirmado'])
        .get();

      if (comissoesSnapshot.empty) {
        logger.info(`[COMISSAO] Nenhuma comissão para estornar do pedido ${pedidoId}`);
        return null;
      }

      const batch = db.batch();
      let count = 0;

      comissoesSnapshot.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'estornado',
          statusPagamentoVenda: 'cancelado',
          dataEstorno: admin.firestore.FieldValue.serverTimestamp(),
          motivoEstorno: 'Pedido cancelado',
        });
        count++;
      });

      await batch.commit();

      logger.info(`[COMISSAO] ✅ ${count} comissões estornadas do pedido ${pedidoId}`);
      return { success: true, estornadas: count };
    } catch (error) {
      logger.error(`[COMISSAO] ❌ Erro ao estornar comissões: ${error.message}`);
      return { success: false, error: error.message };
    }
  }
);

/**
 * Sincroniza vendedores com configurações de comissão quando adicionados à loja
 */
exports.sincronizarNovoVendedor = onDocumentCreated(
  'lojas/{lojaId}/members/{memberId}',
  async (event) => {
    const memberData = event.data.data();
    const lojaId = event.params.lojaId;
    const memberId = event.params.memberId;

    // Verificar se é vendedor
    if (memberData.tipo !== 'vendedor') {
      return null;
    }

    logger.info(`[COMISSAO] Novo vendedor adicionado: ${memberId}`);

    try {
      // Verificar se já tem configuração
      const existingDoc = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('comissoes_vendedores')
        .doc(memberId)
        .get();

      if (existingDoc.exists) {
        logger.info(`[COMISSAO] Vendedor ${memberId} já tem configuração`);
        return null;
      }

      // Criar configuração padrão
      await db
        .collection('lojas')
        .doc(lojaId)
        .collection('comissoes_vendedores')
        .doc(memberId)
        .set({
          lojaId,
          vendedorUid: memberId,
          vendedorEmail: memberData.email || '',
          vendedorNome: memberData.nome || '',
          comissaoPercentual: null, // Usa global
          ativo: true,
          criadoEm: admin.firestore.FieldValue.serverTimestamp(),
          atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
        });

      logger.info(`[COMISSAO] ✅ Configuração de comissão criada para ${memberData.nome || memberId}`);
      return { success: true };
    } catch (error) {
      logger.error(`[COMISSAO] ❌ Erro ao criar config de vendedor: ${error.message}`);
      return { success: false, error: error.message };
    }
  }
);
