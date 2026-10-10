// lib/services/pos_pagamento_service.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../repositories/pedido_repository.dart';
import '../core/firestore_dynamic_map.dart';
import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../models/produto.dart';
import 'catalogo_venda_service.dart';
import 'catalogo_web_apos_estoque_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';
import 'produtos_firestore_service.dart';
import 'venda_combo_estoque_expansion.dart';
import 'firestore_paths.dart';
import 'pedido_collection_resolver.dart';
import 'campanha_sorteio_gate.dart';
import 'campaign_engine_service.dart';
import 'email_service.dart';

/// Serviço para processar ações após confirmação de pagamento
///
/// Funcionalidades:
/// - Baixa de estoque
/// - Atualização de status da venda
/// - Geração de número da sorte
/// - Envio de notificações (Email e WhatsApp)
/// - Integração com cupom da roleta
class PosPagamentoService {
  static final PedidoRepository _pedidoRepository = PedidoRepository();

  /// Apenas testes — injeta FakeFirebaseFirestore.
  static FirebaseFirestore? debugFirestoreOverride;

  /// Apenas testes — substitui [CampaignEngineService.buscarPorVendaId].
  static Future<Participacao?> Function({
    required String lojaId,
    required String vendaId,
  })? debugBuscarParticipacaoOverride;

  static FirebaseFirestore get _firestore =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  /// Última falha de [processarConfirmacaoPagamento] (para mensagem específica na UI).
  static String? ultimaFalhaProcessamento;

  /// Se a última confirmação enviou número da sorte ao cliente (campanha válida).
  static bool ultimaNotificacaoComNumeroSorte = false;

  /// Processa todas as ações após confirmação de pagamento
  ///
  /// Este método deve ser chamado quando:
  /// - Webhook do Mercado Pago confirma pagamento (status: approved)
  /// - Webhook de outras gateways confirma pagamento
  /// - Admin confirma pagamento manual
  ///
  /// [lojaId] - ID da loja
  /// [vendaId] - Key da venda no Hive
  /// [customer] - Dados do cliente (nome, email, telefone)
  /// [items] - Lista de itens vendidos
  /// [valorTotal] - Valor total da compra
  /// [formaPagamento] - Forma de pagamento (PIX, CARTÃO, etc)
  /// [cupomRoletaCodigo] - Código do cupom ganho na roleta (se houver)
  /// [cupomRoletaDesconto] - Desconto do cupom da roleta (%)
  static Future<bool> processarConfirmacaoPagamento({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required double valorTotal,
    required String formaPagamento,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    /// Quando true, estoque já foi baixado (ex.: via [VendasService.registrarVendaMulti]
    /// coordenado com Sale Intent). Grava marcador e pula nova baixa.
    bool estoqueJaBaixado = false,
  }) async {
    ultimaFalhaProcessamento = null;
    ultimaNotificacaoComNumeroSorte = false;
    try {
      debugPrint(
        '[CATALOGO_POS_PAGAMENTO_START] vendaId=$vendaId lojaId=$lojaId '
        'valorTotal=$valorTotal itens=${items.length} formaPagamento=$formaPagamento',
      );
      debugPrint(
        '🎯 [PÓS-PAGAMENTO] Iniciando processamento para venda: $vendaId | lojaId=$lojaId | valorTotal=$valorTotal',
      );

      final firestore = FirebaseFirestore.instance;
      final baixaRef = firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(vendaId);

      final baixaSnap = await baixaRef.get();
      final data = baixaSnap.data();
      final baixaJaAplicada = baixaSnap.exists && (data?['baixaAplicada'] == true);
      final efeitosJaProcessados = baixaSnap.exists && (data?['posPagamentoProcessado'] == true);

      if (baixaJaAplicada && efeitosJaProcessados) {
        debugPrint(
          'ℹ️ [PÓS-PAGAMENTO] Requisição idempotente detectada; baixa e efeitos já processados. '
          'lojaId=$lojaId, vendaId=$vendaId',
        );
        return true;
      }

      if (baixaJaAplicada) {
        debugPrint(
          'ℹ️ [ESTOQUE_BAIXA] Baixa já aplicada anteriormente; pulando nova baixa. lojaId=$lojaId, vendaId=$vendaId',
        );
      } else if (estoqueJaBaixado) {
        debugPrint(
          'ℹ️ [ESTOQUE_BAIXA] Estoque já baixado via venda coordenada; gravando marcador sem nova baixa. '
          'lojaId=$lojaId, vendaId=$vendaId',
        );
        await baixaRef.set({
          'baixaAplicada': true,
          'lojaId': lojaId,
          'vendaId': vendaId,
          'origem': 'pos_pagamento_estoque_ja_baixado',
          'valorTotal': valorTotal,
          'quantidadeItens': items.length,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        debugPrint(
          '[CATALOGO_POS_PAGAMENTO_BAIXA_START] vendaId=$vendaId lojaId=$lojaId itens=${items.length}',
        );
        debugPrint(
          '🔁 [ESTOQUE_BAIXA] Iniciando baixa transacional de estoque via pós-pagamento. lojaId=$lojaId, vendaId=$vendaId, itens=${items.length}',
        );

        // 1. Baixar estoque dos produtos (regra: baixa antes de marcar como pago)
        await _baixarEstoque(lojaId, items, vendaId: vendaId);

        await baixaRef.set({
          'baixaAplicada': true,
          'lojaId': lojaId,
          'vendaId': vendaId,
          'origem': 'pos_pagamento',
          'valorTotal': valorTotal,
          'quantidadeItens': items.length,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint(
          '✅ [ESTOQUE_BAIXA] Baixa registrada como aplicada. lojaId=$lojaId, vendaId=$vendaId',
        );
      }

      // 2. Atualizar status da venda para "pago"
      await _atualizarStatusVenda(lojaId, vendaId);

      // 3. Número da sorte: só com participação persistida em campanha válida.
      ({
        String? numero,
        bool canonico,
        bool incluirNaNotificacao,
        String? campanhaId,
        String? participacaoId,
      }) numeroResolvido;
      try {
        numeroResolvido = await resolverNumeroSorteParaPosPagamento(
          lojaId: lojaId,
          vendaId: vendaId,
          estoqueJaBaixado: estoqueJaBaixado,
          customer: customer,
          valorTotal: valorTotal,
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PÓS-PAGAMENTO] Falha ao resolver sorteio — sem número '
          '(type=${e.runtimeType}) | lojaId=$lojaId | vendaId=$vendaId',
        );
        numeroResolvido = (
          numero: null,
          canonico: false,
          incluirNaNotificacao: false,
          campanhaId: null,
          participacaoId: null,
        );
      }
      final numeroSorte = numeroResolvido.numero ?? '';
      ultimaNotificacaoComNumeroSorte = numeroResolvido.incluirNaNotificacao;
      if (numeroSorte.isNotEmpty) {
        try {
          await _salvarNumeroSorte(
            lojaId: lojaId,
            vendaId: vendaId,
            numeroSorte: numeroSorte,
            customer: customer,
            valorTotal: valorTotal,
            campanhaId: numeroResolvido.campanhaId,
            pularColecaoNumerosSorte: numeroResolvido.canonico,
          );
        } catch (e) {
          debugPrint(
            '⚠️ [PÓS-PAGAMENTO] Falha não-bloqueante ao salvar número da sorte '
            '(type=${e.runtimeType}) | lojaId=$lojaId | vendaId=$vendaId',
          );
        }
      }

      // 4. Ativar prêmio da roleta (já é não-bloqueante internamente, mantém await)
      await _ativarPremioRoleta(
        lojaId: lojaId,
        vendaId: vendaId,
      );

      // 5. Enviar notificações (Email e WhatsApp)
      final camposSorteio = numeroSorte.isNotEmpty &&
              numeroResolvido.incluirNaNotificacao
          ? camposSorteioEstruturados(
              lojaId: lojaId,
              vendaId: vendaId,
              campanhaId: numeroResolvido.campanhaId,
              participacaoId: numeroResolvido.participacaoId,
              numeroSorte: numeroSorte,
            )
          : null;
      await _enviarNotificacoes(
        lojaId: lojaId,
        vendaId: vendaId,
        customer: customer,
        numeroSorte: numeroSorte,
        cupomRoletaCodigo: cupomRoletaCodigo,
        cupomRoletaDesconto: cupomRoletaDesconto,
        valorTotal: valorTotal,
        incluirNumeroSorte: camposSorteio != null,
        camposSorteio: camposSorteio,
      );

      try {
        await baixaRef.set({
          'posPagamentoProcessado': true,
          'posPagamentoProcessadoAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint(
          '✅ [PÓS-PAGAMENTO] Marcado posPagamentoProcessado=true para vendaId=$vendaId | lojaId=$lojaId',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PÓS-PAGAMENTO] Falha ao marcar posPagamentoProcessado (type=${e.runtimeType}) '
          '| lojaId=$lojaId | vendaId=$vendaId',
        );
      }

      debugPrint('✅ [PÓS-PAGAMENTO] Processamento concluído com sucesso!');
      return true;
    } catch (e, st) {
      ultimaFalhaProcessamento = e.toString();
      debugPrint(
        '[CATALOGO_POS_PAGAMENTO_FAIL] vendaId=$vendaId lojaId=$lojaId '
        'erro=$e type=${e.runtimeType}',
      );
      debugPrint(
        '❌ [PÓS-PAGAMENTO] Erro ao processar (type=${e.runtimeType}) | lojaId=$lojaId | vendaId=$vendaId | $e',
      );
      debugPrint('$st');
      return false;
    }
  }

  /// Atualiza o status da venda para "pago"
  static Future<void> _atualizarStatusVenda(String lojaId, String vendaId) async {
    try {
      // Atualizar no serviço de catálogo
      await CatalogoVendaService.atualizarStatusPedido(
        lojaId: lojaId,
        vendaId: vendaId,
        status: 'pago',
      );

      // FASE 3: Box por loja (HiveBoxNames.vendas(lojaId)) — lojaId já recebido no fluxo
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final key = int.tryParse(vendaId);
      final venda = key != null ? vendasBox.get(key) : vendasBox.get(vendaId);
      if (venda != null) {
        venda.observacao = '${venda.observacao}\n[PAGO em ${DateTime.now()}]';
        await venda.save();
      }
      if (kDebugMode) debugPrint('📌 [HIVE_BOX] pos_pagamento vendasBox lojaId=$lojaId');

      debugPrint('✅ Status da venda atualizado para: pago');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar status da venda (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Baixa o estoque dos produtos vendidos via transação Firestore (atômico).
  /// Usa a mesma expansão de combo que a nova venda ([VendaComboEstoqueExpansion]), incluindo
  /// [itensComboComSelecao] e [extraValor] por componente.
  static Future<void> _baixarEstoque(
    String lojaId,
    List<Map<String, dynamic>> items, {
    String? vendaId,
  }) async {
    final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

    final docIdsParaHive = <String>{};
    for (final raw in items) {
      var pid = (raw['productId'] ?? raw['id'] ?? raw['produtosId'] ?? '')
          .toString()
          .trim();
      if (pid.isEmpty) {
        final slug = (raw['slug'] ?? '').toString().trim();
        if (slug.isNotEmpty) {
          final resolved = await ProdutosFirestoreService.findEstoqueProdutoDocIdBySlug(
            lojaId: lojaId,
            slug: slug,
          );
          if (resolved != null) pid = resolved;
        }
      }
      if (pid.isNotEmpty) docIdsParaHive.add(pid);
    }
    if (docIdsParaHive.isNotEmpty) {
      await ProdutosFirestoreService.ensureEstoqueProdutoDocsInHive(
        lojaId: lojaId,
        produtosBox: produtosBox,
        firebaseDocIds: docIdsParaHive,
        forceRefreshFromRemoto: true,
      );
    }

    final (vendaItens, comboPorIndice) =
        VendaComboEstoqueExpansion.carrinhoMapsParaVendaItensComComboSelecao(items);

    if (vendaItens.isEmpty) {
      debugPrint(
        '⚠️ [ESTOQUE_BAIXA] Nenhum item válido após mapear carrinho. lojaId=$lojaId',
      );
      throw Exception(
        'Nenhum item válido para baixa de estoque. '
        'Não é possível confirmar o pagamento sem baixar o estoque.',
      );
    }

    final (itensParaEstoque, produtosEncontrados, _) =
        VendaComboEstoqueExpansion.expandirCombos(
      itens: vendaItens,
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: comboPorIndice,
    );

    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    for (final tx in txItems) {
      debugPrint(
        '[CATALOGO_TX_ITEM] vendaId=$vendaId lojaId=$lojaId '
        'produtoNome=${tx['nome']} productId=${tx['productId']} '
        'tamanho=${tx['tamanho']} cor=${tx['cor']} '
        'extra=${tx['extraValor'] ?? ''} quantidade=${tx['quantidade']}',
      );
    }

    if (txItems.isEmpty) {
      debugPrint(
        '⚠️ [ESTOQUE_BAIXA] Lista de transação vazia após expansão. lojaId=$lojaId',
      );
      throw Exception(
        'Nenhum item válido para baixa de estoque. '
        'Não é possível confirmar o pagamento sem baixar o estoque.',
      );
    }

    List<EstoqueTransactionResult> txResults;
    try {
      txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: lojaId,
        itens: txItems,
      );
    } catch (e, st) {
      debugPrint(
        '[CATALOGO_POS_PAGAMENTO_BAIXA_FAIL] vendaId=$vendaId lojaId=$lojaId '
        'erro=$e type=${e.runtimeType}',
      );
      debugPrint('$st');
      rethrow;
    }

    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaId, txResults);

    List<EstoqueTransactionResult> txResultsComboCap = const [];
    try {
      for (final result in txResults) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaId,
          result: result,
        );
      }
      txResultsComboCap = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda:
            ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ [HIVE_BOX] pos_pagamento: Hive indisponível ao atualizar após transação (type=${e.runtimeType}) | lojaId=$lojaId',
        );
      }
    }

    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lojaId,
      produtosBox: produtosBox,
      resultadosPrincipais: txResults,
      resultadosComboExtra: txResultsComboCap,
    );

    debugPrint(
      '✅ [ESTOQUE_BAIXA] Estoque baixado com sucesso para todos os produtos. lojaId=$lojaId, itens=${txResults.length}',
    );
  }

  /// Número da sorte só existe com participação persistida em campanha válida:
  /// - admin (`estoqueJaBaixado`): reutiliza participação canônica do CampaignEngine;
  /// - senão: [CampanhaSorteioGate] (exatamente 1 campanha ativa da loja, período
  ///   validado no servidor). Sem campanha / falha de consulta ⇒ `numero == null`.
  @visibleForTesting
  static Future<
      ({
        String? numero,
        bool canonico,
        bool incluirNaNotificacao,
        String? campanhaId,
        String? participacaoId,
      })> resolverNumeroSorteParaPosPagamento({
    required String lojaId,
    required String vendaId,
    required bool estoqueJaBaixado,
    Map<String, dynamic> customer = const {},
    double valorTotal = 0,
  }) async {
    if (estoqueJaBaixado) {
      final participacao = debugBuscarParticipacaoOverride != null
          ? await debugBuscarParticipacaoOverride!(
              lojaId: lojaId,
              vendaId: vendaId,
            )
          : await CampaignEngineService.buscarPorVendaId(
              lojaId: lojaId,
              vendaId: vendaId,
            );
      final canonico = participacao?.numero ?? '';
      if (canonico.isNotEmpty && participacao?.status == 'valido') {
        debugPrint(
          'ℹ️ [PÓS-PAGAMENTO] Número canônico reutilizado da campanha '
          '| lojaId=$lojaId | vendaId=$vendaId',
        );
        return (
          numero: canonico,
          canonico: true,
          incluirNaNotificacao: false,
          campanhaId: participacao?.campanhaId,
          participacaoId: participacao?.id,
        );
      }
    }

    final validada = await CampanhaSorteioGate.registrarParticipacaoValidada(
      lojaId: lojaId,
      vendaId: vendaId,
      valorCompra: valorTotal,
      dadosParticipante: {
        'clienteNome': customer['nome']?.toString() ?? 'Cliente',
        'clienteEmail': customer['email']?.toString(),
        'clienteTelefone': customer['telefone']?.toString(),
        'clienteId':
            customer['id']?.toString() ?? customer['clienteId']?.toString(),
        'origem': 'catalogo',
      },
    );
    if (validada == null) {
      debugPrint(
        'ℹ️ [PÓS-PAGAMENTO] Sem campanha de sorteio válida — sem número da sorte '
        '| lojaId=$lojaId | vendaId=$vendaId',
      );
      return (
        numero: null,
        canonico: false,
        incluirNaNotificacao: false,
        campanhaId: null,
        participacaoId: null,
      );
    }
    return (
      numero: validada.numero,
      canonico: !validada.criadaAgora,
      incluirNaNotificacao: validada.criadaAgora,
      campanhaId: validada.campanhaId,
      participacaoId: validada.participacaoId,
    );
  }

  /// Campos que o servidor (`sendEmail` / `sendWhatsAppOrderConfirmation`) exige para
  /// aceitar notificação de sorteio. Algum ausente ⇒ `null` (notificação sem sorteio).
  @visibleForTesting
  static Map<String, String>? camposSorteioEstruturados({
    required String lojaId,
    required String vendaId,
    required String? campanhaId,
    required String? participacaoId,
    required String numeroSorte,
  }) {
    final campos = {
      'notificationType': 'raffle_participation',
      'lojaId': lojaId.trim(),
      'saleId': vendaId.trim(),
      'campaignId': (campanhaId ?? '').trim(),
      'participationId': (participacaoId ?? '').trim(),
      'luckyNumber': numeroSorte.trim(),
    };
    if (campos.values.any((v) => v.isEmpty)) return null;
    return campos;
  }

  /// Salva o número da sorte no Firestore
  static Future<void> _salvarNumeroSorte({
    required String lojaId,
    required String vendaId,
    required String numeroSorte,
    required Map<String, dynamic> customer,
    required double valorTotal,
    String? campanhaId,
    bool pularColecaoNumerosSorte = false,
  }) async {
    try {
      if (!pularColecaoNumerosSorte) {
        await _firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('numerosSorte')
            .add({
          'numero': numeroSorte,
          'vendaId': vendaId,
          if (campanhaId != null && campanhaId.isNotEmpty)
            'campanhaId': campanhaId,
          'cliente': {
            'nome': customer['nome'],
            'email': customer['email'],
            'telefone': customer['telefone'],
          },
          'valorCompra': valorTotal,
          'dataGeracao': FieldValue.serverTimestamp(),
          'ativo': true,
        });
      } else {
        debugPrint(
          'ℹ️ [PÓS-PAGAMENTO] Coleção numerosSorte omitida; participantes é canônico. '
          'vendaId=$vendaId',
        );
      }

      // Atualizar o pedido com o número da sorte
      final pedidoRef = await _pedidoRepository.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );

      if (pedidoRef != null) {
        await pedidoRef.update({
          'numeroSorte': numeroSorte,
        });
      }

      debugPrint('🎲 Número da sorte gerado e salvo: $numeroSorte');
    } catch (e) {
      debugPrint('❌ Erro ao salvar número da sorte (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Quando há participação canônica (CampaignEngine), o número da sorte
  /// é enviado pelo owner da campanha (CF). PosPagamento preserva só o operacional.
  @visibleForTesting
  static bool deveOmitirNumeroSorteNotificacaoCliente({
    required bool participacaoCanonica,
  }) =>
      participacaoCanonica;

  /// Envia notificações por Email e WhatsApp
  static Future<void> _enviarNotificacoes({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
    bool incluirNumeroSorte = true,
    Map<String, String>? camposSorteio,
  }) async {
    try {
      final email = customer['email']?.toString();
      final telefone = customer['telefone']?.toString();
      final nome = customer['nome']?.toString() ?? 'Cliente';

      // Buscar configurações da loja
      final lojaDoc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .get();

      if (!lojaDoc.exists) {
        debugPrint('⚠️ Loja não encontrada, pulando notificações');
        return;
      }

      final lojaData = lojaDoc.data()!;
      final lojaNome = lojaData['nome']?.toString() ?? 'Loja';

      // Enviar Email (servidor deriva destinatário/conteúdo do pedido)
      if (email != null && email.isNotEmpty) {
        await _enviarEmail(
          lojaId: lojaId,
          vendaId: vendaId,
          camposSorteio: incluirNumeroSorte ? camposSorteio : null,
        );
      }

      // Enviar WhatsApp (usa Cloud Function + config Canais Meta)
      if (telefone != null && telefone.isNotEmpty) {
        await _enviarWhatsApp(
          lojaId: lojaId,
          vendaId: vendaId,
          telefone: telefone,
          nome: nome,
          lojaNome: lojaNome,
          numeroSorte: numeroSorte,
          cupomRoletaCodigo: cupomRoletaCodigo,
          cupomRoletaDesconto: cupomRoletaDesconto,
          valorTotal: valorTotal,
          incluirNumeroSorte: incluirNumeroSorte,
          camposSorteio: camposSorteio,
        );
      }

      debugPrint('✅ Notificações enviadas com sucesso!');
    } catch (e) {
      debugPrint('❌ Erro ao enviar notificações (type=${e.runtimeType})');
      // Não lança exceção para não bloquear o fluxo
    }
  }

  /// Confirmação de pedido por e-mail (`sendEmail` tipado; servidor monta o conteúdo).
  static Future<void> _enviarEmail({
    required String lojaId,
    required String vendaId,
    Map<String, String>? camposSorteio,
  }) async {
    try {
      final r = await EmailService.enviar(
        EmailService.payloadConfirmacaoPedido(
          lojaId: lojaId,
          vendaId: vendaId,
          camposSorteio: camposSorteio,
        ),
      );
      if (EmailService.foiEnviado(r.statusCode, r.body)) {
        debugPrint('📧 Email de confirmação enviado | vendaId=$vendaId');
      } else {
        debugPrint(
          '❌ Email de confirmação não enviado: ${r.statusCode} '
          '${EmailService.codigoResposta(r.body) ?? ''}',
        );
      }
    } catch (e) {
      debugPrint('❌ Exceção ao enviar email (type=${e.runtimeType})');
    }
  }

  /// Envia mensagem via WhatsApp (Cloud Function + config Canais Meta).
  /// Se existir pedido no Firestore (por vendaId), envia confirmação completa no formato
  /// tipo DELIGELI: saudação, nº pedido, itens, forma de pagamento, tempo de entrega, endereço, total e número da sorte.
  static Future<void> _enviarWhatsApp({
    required String lojaId,
    required String vendaId,
    required String telefone,
    required String nome,
    required String lojaNome,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
    bool incluirNumeroSorte = true,
    Map<String, String>? camposSorteio,
  }) async {
    try {
      final temCupom = cupomRoletaCodigo != null && cupomRoletaCodigo.isNotEmpty;
      final blocoSorteio = incluirNumeroSorte
          ? '''

---
🎲 *Seu Número da Sorte:* *$numeroSorte*
✅ Você está participando da nossa promoção!
'''
          : '';

      // Tentar buscar pedido para montar mensagem de confirmação completa (formato tipo DELIGELI)
      String mensagem = '';
      try {
        final pedido = await _pedidoRepository.findFirstByField(
          flowType: PedidoFlowType.pedidos,
          lojaId: lojaId,
          field: 'vendaId',
          value: vendaId,
        );

        if (pedido != null) {
          final numeroPedido = pedido['id'].toString();
          final cliente = pedido['cliente'] as Map<String, dynamic>? ?? {};
          final itens = (pedido['itens'] as List<dynamic>?) ?? [];
          final formaPagamento = (pedido['pagamento'] ?? '').toString();
          final total = (pedido['total'] as num?)?.toDouble() ?? valorTotal;
          final endereco =
              (cliente['enderecoFormatado'] ?? cliente['endereco'] ?? '')
                  .toString();

          final itensLinhas = itens.map<String>((e) {
            final map = e is Map
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{};
            final qtd = (map['quantidade'] as num?)?.toInt() ?? 1;
            final nomeItem = (map['nome'] ?? map['name'] ?? '').toString();
            return '➡ ${qtd}x $nomeItem';
          }).join('\n');

          const tempoEntregaPadrao = '45 - 60min';
          final formaPagamentoExibir = formaPagamento.isEmpty ? 'Não informado' : formaPagamento;

          mensagem = '''
Olá $nome, aqui é o atendente virtual da *${lojaNome.toUpperCase()}*.

Vim te avisar que seu pedido foi realizado com sucesso e já está em preparo. 😊
Fique tranquilo(a) que vou enviar as atualizações do status do seu pedido por aqui.

*Nº do pedido* $numeroPedido

*Itens:*
$itensLinhas

*Forma de pagamento:* $formaPagamentoExibir

*Tempo de entrega:* $tempoEntregaPadrao

*Local de entrega:* ${endereco.isEmpty ? 'Não informado' : endereco}

*Total do pedido:* R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}
$blocoSorteio
${temCupom ? '''
🎁 *Cupom da Roleta:* *$cupomRoletaCodigo* (${cupomRoletaDesconto?.toStringAsFixed(0)}% OFF) - Válido por 60 dias.
''' : ''}
Obrigado por comprar conosco! 💜
''';
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('pos_pagamento: erro ao buscar pedido para mensagem (type=${e.runtimeType})');
        }
      }

      if (mensagem.isEmpty) {
        // Fallback: mensagem apenas com número da sorte (comportamento anterior)
        mensagem = incluirNumeroSorte
            ? '''
🎉 *Parabéns, $nome!*

Obrigado por sua compra na *$lojaNome*!

🎲 *Seu Número da Sorte:*
*$numeroSorte*

✅ Você está participando da nossa promoção!

${temCupom ? '''
🎁 *Você também ganhou na Roleta da Sorte!*

Cupom de *${cupomRoletaDesconto?.toStringAsFixed(0)}% OFF* para sua próxima compra:

*$cupomRoletaCodigo*

📅 Válido por 60 dias
🔄 Use na próxima compra
''' : ''}

Obrigado por comprar conosco! 💜
'''
            : '''
✅ *Pedido confirmado, $nome!*

Obrigado por sua compra na *$lojaNome*!

${temCupom ? '''
🎁 *Você também ganhou na Roleta da Sorte!*

Cupom de *${cupomRoletaDesconto?.toStringAsFixed(0)}% OFF* para sua próxima compra:

*$cupomRoletaCodigo*

📅 Válido por 60 dias
🔄 Use na próxima compra
''' : ''}

Obrigado por comprar conosco! 💜
''';
      }

      // Enviar via Cloud Function que usa canais/whatsapp (WhatsApp Cloud API)
      final projectId = Firebase.app().options.projectId;
      final response = await http.post(
        Uri.parse('https://southamerica-east1-$projectId.cloudfunctions.net/sendWhatsAppOrderConfirmation'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (incluirNumeroSorte) ...?camposSorteio,
          'lojaId': lojaId,
          'phone': telefone,
          'message': mensagem,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📱 WhatsApp enviado para: $telefone');
      } else {
        debugPrint('❌ Erro ao enviar WhatsApp: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Exceção ao enviar WhatsApp (type=${e.runtimeType})');
    }
  }

  /// ✅ Ativa o prêmio da roleta após confirmação de pagamento
  ///
  /// Esta função é chamada automaticamente após o pagamento ser confirmado.
  /// Ela marca o prêmio como "ativo" e "válido", permitindo seu uso na próxima compra.
  ///
  /// Para brindes: não há ativação, o brinde é entregue junto com o pedido
  /// Para cupons/frete grátis: são ativados e ficam válidos para próxima compra
  static Future<void> _ativarPremioRoleta({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Buscar o pedido
      final pedidoRef = await _pedidoRepository.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );

      if (pedidoRef == null) {
        debugPrint('⚠️ Pedido não encontrado, não há prêmio para ativar');
        return;
      }

      final pedidoData = (await pedidoRef.get()).data() ?? {};
      final premioRoleta =
          firestoreStringDynamicMapOrNull(pedidoData['premioRoleta']);

      if (premioRoleta == null) {
        debugPrint('ℹ️ Pedido não tem prêmio da roleta');
        return;
      }

      final tipo = premioRoleta['tipo']?.toString() ?? 'nenhum';

      if (tipo == 'nenhum') {
        debugPrint('ℹ️ Prêmio é do tipo "nenhum", não requer ativação');
        return;
      }

      // ✅ Ativar prêmio
      await pedidoRef.update({
        'premioRoleta.status': 'ativo',
        'premioRoleta.valido': true,
        'premioRoleta.dataAtivacao': FieldValue.serverTimestamp(),
      });

      // ✅ Se for cupom ou frete grátis, salvar em dois locais:
      // 1) estoque_clientes (admin/histórico por telefone) — DOMÍNIO ADMIN, não perfil catálogo
      // 2) clientes_catalogo (cupons roleta por email) — USO ESPECÍFICO
      if (tipo == 'desconto' || tipo == 'frete_gratis') {
        final clienteData = pedidoData['cliente'] as Map<String, dynamic>?;
        final telefone = (clienteData?['telefone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final email = (clienteData?['email'] ?? '').toString().trim().toLowerCase();

        if (telefone.isNotEmpty) {
          // 1) estoque_clientes (admin) — side-effect para historico admin
          final clienteRef = firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('estoque_clientes')
              .doc(telefone);

          final clienteDoc = await clienteRef.get();

          if (clienteDoc.exists) {
            await clienteRef.update({
              'cuponsRoleta': FieldValue.arrayUnion([
                {
                  'codigo': premioRoleta['codigo'],
                  'tipo': tipo,
                  'valor': premioRoleta['valor'] ?? 0.0,
                  'descricao': premioRoleta['descricao'],
                  'dataGanho': premioRoleta['dataGanho'],
                  'dataAtivacao': FieldValue.serverTimestamp(),
                  'vendaOrigem': vendaId,
                  'usado': false,
                  'dataUso': null,
                }
              ]),
            });
            debugPrint('🎁 Cupom da roleta ativado (estoque_clientes): ${premioRoleta['codigo']}');
          }
        }

        // 2) clientes_catalogo (USO ESPECÍFICO: cupons roleta por email) – "Meus Cupons"
        if (email.isNotEmpty) {
          final codigo = (premioRoleta['codigo'] ?? '').toString();
          if (codigo.isNotEmpty) {
            final dataExpiracao = DateTime.now().add(const Duration(days: 60));
            await firestore
                .collection('lojas')
                .doc(lojaId)
                .collection(FSPaths.clientesCatalogoCol)
                .doc(email)
                .collection('cupons')
                .doc(codigo)
                .set({
              'codigo': codigo,
              'descricao': premioRoleta['descricao'] ?? '',
              'tipo': tipo,
              'valor': (premioRoleta['valor'] as num?)?.toDouble() ?? 0.0,
              'dataGanho': premioRoleta['dataGanho'],
              'dataExpiracao': Timestamp.fromDate(dataExpiracao),
              'usado': false,
              'ativo': true,
              'origem': 'roleta_sorte',
            });
            debugPrint('🎁 Cupom da roleta salvo no perfil do cliente (catálogo): $codigo');
          }
        }
      }

      debugPrint('✅ Prêmio da roleta ativado: tipo=$tipo, código=${premioRoleta['codigo']}');
    } catch (e) {
      debugPrint('❌ Erro ao ativar prêmio da roleta (type=${e.runtimeType})');
      // Não lança exceção para não bloquear o fluxo principal
    }
  }
}
