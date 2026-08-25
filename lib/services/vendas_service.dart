// lib/services/vendas_service.dart
//
// Serviço de vendas para a tela "Nova Venda"
// ATUALIZADO: Agora sincroniza estoque no Firestore após baixar variações
import 'dart:async';

import 'package:collection/collection.dart'; // firstWhereOrNull
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../models/conta_receber.dart';
import '../core/conta_receber_identity.dart';
import '../core/conta_receber_venda_vinculo.dart' as crv;
import '../core/nova_venda_ui_release_policy.dart';
import '../core/loja_ativa_resolver.dart';
import '../core/logger.dart';
import '../core/safe_cast.dart';
import '../core/strict_product_resolution.dart';
import '../utils/text_utils.dart';
import '../services/campaign_engine_service.dart'; // 🎯 integração com campanhas/sorteio (centralizado)
import '../services/clientes_firestore_service.dart'; // 🔹 sincronização de clientes
import '../services/vendas_firestore_service.dart'; // 🔹 sincronização com Firestore
import 'catalogo_web_apos_estoque_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';
import 'movimentacao_estoque_service.dart';
import 'venda_combo_estoque_expansion.dart';
import 'venda_custo_mercadoria.dart';
import 'venda_edicao_estoque_diff.dart';
import 'venda_estoque_remoto_prep_service.dart';
import 'venda_operation_journal_service.dart';
import 'sale_intent_service.dart';
import 'conta_receber_service.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_venda_backfill.dart';

/// Persistência Hive falhou e o estorno pré-Hive do estoque remoto também falhou.
class VendaPersistenciaInconsistenciaCritica implements Exception {
  const VendaPersistenciaInconsistenciaCritica({
    required this.erroPersistencia,
    required this.erroEstorno,
  });

  final Object erroPersistencia;
  final Object erroEstorno;

  @override
  String toString() =>
      'Falha ao persistir venda local e falha ao restaurar estoque remoto. '
      'Persistência: $erroPersistencia. '
      'Estorno: $erroEstorno. '
      'Verifique o estoque na nuvem antes de tentar novamente.';
}

/// Venda e conta a receber locais OK; sincronização remota da CR ficou pendente.
/// Não é falha de persistência local — a UI deve fechar como salva e avisar sync.
class VendaSalvaComPendenciaSyncException implements Exception {
  const VendaSalvaComPendenciaSyncException([this.message = defaultMessage]);

  static const String defaultMessage =
      'Venda salva. A conta a receber ficou pendente de sincronização '
      'e será necessário tentar sincronizar novamente.';

  final String message;

  static bool isPendenciaMessage(String? raw) {
    final m = raw?.trim() ?? '';
    if (m.isEmpty) return false;
    return m == defaultMessage ||
        m.contains('conta a receber ficou pendente de sincronização');
  }

  @override
  String toString() => message;
}

class VendasService {
  @visibleForTesting
  static Future<dynamic> Function(Box<Venda> box, Venda venda)?
      debugVendasBoxAddOverride;

  /// Somente testes — simula falha em [estornarBaixaPosFalhaAntesDePersistirVendaHive].
  @visibleForTesting
  static Future<void> Function()? debugForcarFalhaEstornoPreHiveRollback;

  /// Somente testes — simula falha em [devolverEstoqueParaVendaRemovida] no rollback fiado.
  @visibleForTesting
  static Future<void> Function()? debugForcarFalhaEstornoPosFiadoRollback;

  /// Somente testes — substitui [_persistirContasReceberNaBox] para simular falha fiado.
  @visibleForTesting
  static Future<void> Function({
    required Box<ContaReceber> crBox,
    required List<ContaReceber> contas,
    required String lojaId,
    required String vendaIdVinculo,
    required int? vendaHiveKey,
  })? debugPersistirContasReceberNaBoxOverride;

  /// Somente testes — barreira determinística imediatamente antes da baixa remota.
  @visibleForTesting
  static Future<void> Function()? debugAntesBaixaEstoqueBarrier;

  /// Somente testes — simula crash após baixa remota e antes de vendasBox.add.
  @visibleForTesting
  static Future<void> Function()? debugAfterRemoteStockAppliedBeforeHivePersist;

  /// Somente testes — simula crash após Hive persistido e antes de complete remoto.
  @visibleForTesting
  static Future<void> Function()?
      debugAfterHiveSalePersistedBeforeSaleIntentComplete;

  /// Somente testes — substitui syncCliente no caminho de [editarVendaMulti].
  @visibleForTesting
  static Future<void> Function(Cliente cliente, {required String lojaId})?
      debugEditarVendaSyncClienteOverride;

  /// Somente testes — substitui syncVenda no caminho de [editarVendaMulti].
  @visibleForTesting
  static Future<bool> Function(Venda venda, {required String lojaId})?
      debugEditarVendaSyncVendaOverride;

  /// Somente testes — falha a transição local de CR após a validação de auditoria.
  @visibleForTesting
  static Future<void> Function()? debugForcarFalhaTransicaoCrLocalEdicao;

  /// Somente testes — falha o delta de estoque na edição antes de [venda.save].
  @visibleForTesting
  static Future<void> Function()? debugForcarFalhaEstoqueEdicaoAntesSave;

  /// Somente testes — após TX de estoque commitada, antes de retornar ao [editarVendaMulti]/venda.save].
  @visibleForTesting
  static Future<void> Function()? debugAposReconcileEstoqueEdicaoAntesVendaSave;

  static const String mensagemNaoPodeRemoverFiadoComRecebimentosParciais =
      'Não é possível remover o fiado: existem recebimentos parciais nesta venda.';

  static final Map<String, Future<Venda>> _registrarVendaCoalesce = {};

  @visibleForTesting
  static void debugOperacoesEmAndamentoClearForTests() {
    _registrarVendaCoalesce.clear();
  }

  static String _chaveCoalesceRegistrarVenda({
    String? lojaId,
    required String clienteNome,
    required List<VendaItem> itens,
    required double dinheiro,
    required double pix,
    required double cartao,
    required double frete,
    required double descontoPct,
    required String observacao,
    required bool isFiado,
    String? idFirebaseToReuse,
    String? saleIntentId,
    required int quantidadeParcelasFiado,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
  }) {
    final intent = (saleIntentId ?? '').trim();
    if (intent.isNotEmpty) return 'intent:$intent';

    final reuse = (idFirebaseToReuse ?? '').trim();
    if (reuse.isNotEmpty) return 'reuse:$reuse';

    final linhas = itens.map((it) {
      final pid = (it.productId ?? '').trim();
      return '$pid|${it.produtoNome.trim()}|${it.quantidade}|'
          '${it.precoUnitario}|${it.tamanho.trim()}|${it.cor.trim()}';
    }).toList()
      ..sort();
    final comboJson =
        VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
      itensComboSelecaoPorIndice,
    );
    return [
      'loja:${(lojaId ?? '').trim()}',
      'cli:${clienteNome.trim()}',
      'pay:$dinheiro,$pix,$cartao',
      'frete:$frete',
      'desc:$descontoPct',
      'fiado:$isFiado',
      'parc:$quantidadeParcelasFiado',
      'obs:${observacao.trim()}',
      if (comboJson != null && comboJson.isNotEmpty) 'combo:$comboJson',
      'itens:${linhas.join(';')}',
    ].join('|');
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  static String _fmt2(double v) => v.toStringAsFixed(2);

  static bool _vendaOrigemCatalogo(Venda venda) {
    final o = (venda.origemVenda ?? '').trim().toLowerCase();
    return o == 'catalogo_web' || o.startsWith('catalogo');
  }

  static List<double> _parcelarValores(double total, int parcelas) {
    final qtd = parcelas.clamp(1, 48);
    final totalCentavos = (total * 100).round();
    final base = totalCentavos ~/ qtd;
    final resto = totalCentavos % qtd;
    return List<double>.generate(
      qtd,
      (i) => (base + (i < resto ? 1 : 0)) / 100.0,
    );
  }

  /// Valida parâmetros de venda fiada antes de baixar estoque ou gravar venda.
  /// Lança [ArgumentError] com mensagem clara para a UI.
  static void validarParametrosVendaFiada({
    required bool isFiado,
    DateTime? dataVencimentoFiado,
    required String clienteNome,
    required double total,
    int quantidadeParcelasFiado = 1,
    double totalPagoAgora = 0,
  }) {
    if (!isFiado) return;
    if (clienteNome.trim().isEmpty) {
      throw ArgumentError('Selecione um cliente para venda fiada.');
    }
    if (total <= 0) {
      throw ArgumentError('Informe o valor da venda fiada.');
    }
    if (totalPagoAgora > total + 0.01) {
      throw ArgumentError('Pagamento informado maior que o total da venda.');
    }
    final saldoFiado = calcularSaldoFiado(
      total: total,
      totalPagoAgora: totalPagoAgora,
    );
    if (saldoFiado <= 0.01) return;
    if (dataVencimentoFiado == null) {
      throw ArgumentError('Informe a data de vencimento da venda fiada.');
    }
    if (quantidadeParcelasFiado < 1) {
      throw ArgumentError('Informe o número de parcelas da venda fiada.');
    }
  }

  /// Saldo que vira conta a receber em venda fiada ou mista.
  static double calcularSaldoFiado({
    required double total,
    required double totalPagoAgora,
  }) =>
      crv.calcularSaldoFiadoVenda(total: total, totalPagoAgora: totalPagoAgora);

  /// Atualiza histórico do cliente sem abortar a venda (HiveList pode falhar no web).
  static void _adicionarVendaHistoricoClienteSeguro({
    required Cliente cliente,
    required Venda venda,
    required Box<Venda> vendasBox,
    required String lojaId,
  }) {
    try {
      cliente.adicionarHistorico(
        venda,
        lojaId: lojaId,
        vendasBoxName: vendasBox.name,
      );
    } catch (e, st) {
      debugPrint(
        '⚠️ [VENDAS-SERVICE] Histórico do cliente não atualizado (type=${e.runtimeType}): $e',
      );
      debugPrint('$st');
    }
  }

  static Future<void> _excluirVendaHiveSeguro(
    Box<Venda> vendasBox,
    Venda venda,
    int? vendaHiveKey,
  ) async {
    final key = vendaHiveKey ?? hiveKeyOrNull(venda.key);
    if (key != null) {
      await vendasBox.delete(key);
      return;
    }
    try {
      await venda.delete();
    } catch (e) {
      debugPrint(
        '⚠️ [VENDAS-SERVICE] Falha ao excluir venda do Hive (type=${e.runtimeType}): $e',
      );
    }
  }

  /// ID estável da venda para vínculo financeiro (conta a receber, exclusão).
  static String idVendaEstavelParaVinculo(Venda venda) =>
      crv.idVendaEstavelParaContaReceber(venda);

  static bool contaReceberVinculadaAVenda({
    required ContaReceber conta,
    required String lojaId,
    int? vendaKey,
    String? vendaIdFirebase,
  }) =>
      crv.contaReceberVinculadaAVenda(
        conta: conta,
        lojaId: lojaId,
        vendaKey: vendaKey,
        vendaIdFirebase: vendaIdFirebase,
      );

  /// Resolve chave Hive após [Box.add] — no Web o retorno/[HiveObject.key] pode falhar.
  static int? resolverVendaHiveKeyAposAdd({
    required Box<Venda> vendasBox,
    required Venda venda,
    required dynamic addedKey,
  }) {
    final fromAdded = hiveKeyOrNull(addedKey);
    if (fromAdded != null) return fromAdded;

    final fromVendaKey = hiveKeyOrNull(venda.key);
    if (fromVendaKey != null) return fromVendaKey;

    if (addedKey != null) {
      try {
        final loaded = vendasBox.get(addedKey);
        if (loaded != null) {
          final k = hiveKeyOrNull(loaded.key) ?? hiveKeyOrNull(addedKey);
          if (k != null) return k;
        }
      } catch (_) {}
    }

    final idV = idVendaEstavelParaVinculo(venda);
    if (idV.isNotEmpty) {
      for (final boxKey in vendasBox.keys) {
        final vk = hiveKeyOrNull(boxKey);
        if (vk == null) continue;
        final vv = vendasBox.get(boxKey);
        if (vv != null && idVendaEstavelParaVinculo(vv) == idV) {
          return vk;
        }
      }
    }

    return null;
  }

  static void _garantirIdFirebaseVendaAntesDeSalvar({
    required Venda venda,
    String? idFirebaseToReuse,
  }) {
    if (idFirebaseToReuse != null && idFirebaseToReuse.trim().isNotEmpty) {
      venda.idFirebase = idFirebaseToReuse.trim();
      return;
    }
    if (idVendaEstavelParaVinculo(venda).isNotEmpty) return;
    venda.idFirebase = VendasFirestoreService.resolveFirestoreVendaDocId(venda);
  }

  static Venda? _findVendaHivePorIdFirebase(
    Box<Venda> vendasBox,
    String operationId,
    String lojaId,
  ) {
    final id = operationId.trim();
    if (id.isEmpty) return null;
    for (final v in vendasBox.values) {
      if (v.lojaId == lojaId && (v.idFirebase ?? '').trim() == id) {
        return v;
      }
    }
    return null;
  }

  static Future<void> _coordinatedSaleIntentRevertBestEffort({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) async {
    try {
      await SaleIntentService.revert(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        operationId: operationId,
      );
    } catch (e) {
      debugPrint('[VENDAS-SERVICE] sale intent revert best-effort: $e');
    }
  }

  static Future<void> _coordinatedSaleIntentCriticalBestEffort({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) async {
    try {
      await SaleIntentService.markCritical(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        operationId: operationId,
      );
    } catch (e) {
      debugPrint('[VENDAS-SERVICE] sale intent critical best-effort: $e');
    }
  }

  static Future<SaleIntentStatus> _coordinatedSaleIntentAdvance({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
    required SaleIntentStatus current,
    required SaleIntentStatus target,
  }) async {
    if (current == target || current.isTerminal) return current;
    try {
      final SaleIntentReservation updated;
      switch (target) {
        case SaleIntentStatus.stockApplied:
          updated = await SaleIntentService.markStockApplied(
            lojaId: lojaId,
            saleIntentId: saleIntentId,
            operationId: operationId,
          );
        case SaleIntentStatus.salePersisted:
          updated = await SaleIntentService.markSalePersisted(
            lojaId: lojaId,
            saleIntentId: saleIntentId,
            operationId: operationId,
          );
        case SaleIntentStatus.completed:
          updated = await SaleIntentService.complete(
            lojaId: lojaId,
            saleIntentId: saleIntentId,
            operationId: operationId,
          );
        default:
          return current;
      }
      return updated.status;
    } on SaleIntentInvalidStateTransitionException {
      return current;
    }
  }

  static List<Map<String, dynamic>> _itensDevolucaoComboCap(
    List<EstoqueTransactionResult> results,
  ) {
    return [
      for (final r in results)
        if (r.quantidadeDebitada > 0 && !r.ajusteCapComboSomenteHive)
          {
            'productId': r.produtoId,
            if (r.produtoSlug != null && r.produtoSlug!.trim().isNotEmpty)
              'slug': r.produtoSlug,
            'nome': r.produtoNome,
            'quantidade': r.quantidadeDebitada,
          },
    ];
  }

  /// Estorna baixa remota quando a venda ainda não foi persistida no Hive.
  @visibleForTesting
  static Future<void> estornarBaixaPosFalhaAntesDePersistirVendaHive({
    required String lojaId,
    required Box<Produto> produtosBox,
    required String vendaIdEstorno,
    required List<Map<String, dynamic>> txItems,
    required List<EstoqueTransactionResult> txResultsComboCap,
  }) async {
    final itensDevolucao = <Map<String, dynamic>>[
      ...txItems,
      ..._itensDevolucaoComboCap(txResultsComboCap),
    ];

    await ComboKitStockService.reverterAjusteCapComboSomenteHive(
      lojaId: lojaId,
      produtosBox: produtosBox,
      results: txResultsComboCap,
    );

    if (itensDevolucao.isEmpty) return;

    final forcarFalha = debugForcarFalhaEstornoPreHiveRollback;
    if (forcarFalha != null) {
      await forcarFalha();
    }

    final results =
        await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: itensDevolucao,
      vendaIdParaIdempotencia: vendaIdEstorno,
      estornoOrigemCatalogo: 'venda_persistencia_falhou',
    );
    for (final result in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lojaId,
        result: result,
      );
    }
  }

  static bool _podeVincularContaReceberAVenda({
    required int? vendaHiveKey,
    required String vendaIdEstavel,
  }) {
    if (vendaHiveKey != null) return true;
    return vendaIdEstavel.isNotEmpty;
  }

  static int _vendaKeyParaContaReceber(int? vendaHiveKey) {
    return vendaHiveKey ?? -1;
  }

  static String _vendaIdFirebaseParaContaReceber(String vendaIdEstavel) {
    return vendaIdEstavel.trim();
  }

  static String _mensagemErroContaReceberSegura(Object e) {
    if (e is ArgumentError) {
      final msg = e.message?.toString().trim() ?? '';
      if (msg.isNotEmpty) return msg;
    }
    if (e is HiveError) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
    }
    if (e is StateError) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
    }
    final raw = e.toString().trim();
    if (raw.isNotEmpty && !raw.startsWith('Instance of')) return raw;
    return 'erro ${e.runtimeType}';
  }

  static void _logContaReceberFiado({
    required String tag,
    required String lojaId,
    String? clienteId,
    String? clienteNome,
    double? totalVenda,
    double? valorPago,
    double? valorFiado,
    String? formaPagamento,
    int? parcelas,
    DateTime? vencimento,
    int? vendaKey,
    String? vendaIdFirebase,
    Object? erro,
    StackTrace? stack,
  }) {
    debugPrint(
      '[$tag] lojaId=$lojaId '
      'clienteId=${clienteId ?? '-'} '
      'clienteNome=${clienteNome ?? '-'} '
      'totalVenda=${totalVenda != null ? _fmt2(totalVenda) : '-'} '
      'valorPago=${valorPago != null ? _fmt2(valorPago) : '-'} '
      'valorFiado=${valorFiado != null ? _fmt2(valorFiado) : '-'} '
      'formaPagamento=${formaPagamento ?? '-'} '
      'parcelas=${parcelas ?? '-'} '
      'vencimento=${vencimento?.toIso8601String() ?? '-'} '
      'vendaKey=${vendaKey ?? '-'} '
      'vendaIdFirebase=${vendaIdFirebase ?? '-'}'
      '${erro != null ? ' erro=$erro' : ''}',
    );
    if (stack != null) debugPrint('$stack');
  }

  /// Timeout só para sync remota de CR (não aplica a Hive local).
  static const Duration _remoteCrSyncTimeout = Duration(seconds: 15);

  static Future<void> _persistirContasReceberNaBox({
    required Box<ContaReceber> crBox,
    required List<ContaReceber> contas,
    required String lojaId,
    required String vendaIdVinculo,
    required int? vendaHiveKey,
    bool remoteBestEffort = false,
  }) async {
    final dbg = debugPersistirContasReceberNaBoxOverride;
    if (dbg != null) {
      await dbg(
        crBox: crBox,
        contas: contas,
        lojaId: lojaId,
        vendaIdVinculo: vendaIdVinculo,
        vendaHiveKey: vendaHiveKey,
      );
      return;
    }

    var falhasFirestore = 0;
    for (var i = 0; i < contas.length; i++) {
      final conta = contas[i];
      // LOCAL_RECEIVABLE_COMMIT_POINT — Hive add/save (obrigatório).
      await crBox.add(conta);
      try {
        await conta.save();
      } catch (e) {
        debugPrint(
          '⚠️ [VENDAS-SERVICE] conta.save após add falhou (parcela ${i + 1}, type=${e.runtimeType})',
        );
        if (!conta.isInBox) {
          rethrow;
        }
      }
      normalizarContaReceberId(conta);
      final docId = resolveContaReceberDocId(conta);
      // REMOTE_CR_SYNC_START_POINT — só após commit local da parcela.
      try {
        final Future<bool> upsertFuture =
            ContaReceberFirestoreService.upsertContaReceber(
          conta,
          lastWriteOrigin: 'venda_fiada',
        );
        final bool publicado;
        if (remoteBestEffort) {
          publicado = await upsertFuture.timeout(
            _remoteCrSyncTimeout,
            onTimeout: () {
              debugPrint(
                '⚠️ [VENDAS-SERVICE] conta Firestore upsert TIMEOUT '
                'parcela ${i + 1} docId=$docId lojaId=$lojaId '
                'limite=${_remoteCrSyncTimeout.inSeconds}s',
              );
              return false;
            },
          );
        } else {
          publicado = await upsertFuture;
        }
        if (!publicado) {
          falhasFirestore++;
          debugPrint(
            '⚠️ [VENDAS-SERVICE] conta Firestore upsert FALHOU parcela ${i + 1} '
            'docId=$docId lojaId=$lojaId',
          );
        }
      } catch (e) {
        falhasFirestore++;
        debugPrint(
          '⚠️ [VENDAS-SERVICE] conta Firestore upsert EXCEÇÃO parcela ${i + 1} '
          'docId=$docId lojaId=$lojaId type=${e.runtimeType}',
        );
        if (!remoteBestEffort) {
          rethrow;
        }
      }
    }
    if (falhasFirestore > 0) {
      debugPrint(
        '⚠️ [VENDAS-SERVICE] $falhasFirestore conta(s) não publicadas no Firestore '
        'lojaId=$lojaId vendaIdFirebase=$vendaIdVinculo '
        'remoteBestEffort=$remoteBestEffort',
      );
      if (remoteBestEffort) {
        throw const VendaSalvaComPendenciaSyncException();
      }
      throw StateError(
        'Não foi possível publicar $falhasFirestore parcela(s) no servidor. '
        'Verifique a conexão e tente novamente.',
      );
    }
    debugPrint(
      '[CONTA_RECEBER_CREATE_OK] [VENDAS-SERVICE] contas_receber criadas qtd=${contas.length} lojaId=$lojaId '
      'vendaKey=${_vendaKeyParaContaReceber(vendaHiveKey)} '
      'vendaIdFirebase=$vendaIdVinculo box=${crBox.name} total=${crBox.length}',
    );
  }

  static double _resolverCustoItem(Produto produto, VendaItem item) {
    final custoVariacao = produto.custoUnitarioVariacao(
      item.tamanho,
      item.cor,
      item.extraValor,
    );
    if (custoVariacao > 0) return custoVariacao;
    if (produto.custoReal > 0) return produto.custoReal;
    return custoVariacao;
  }

  /// Remove contas a receber criadas para esta venda ([vendaKey] Hive e/ou [vendaIdFirebase]).
  static Future<void> removerContasReceberVinculadasAVenda({
    required String lojaId,
    int? vendaKey,
    String? vendaIdFirebase,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    final idV = (vendaIdFirebase ?? '').trim();
    debugPrint(
      '[VENDAS-DELETE][INICIO] vendaId=$idV lojaId=$loja vendaKey=$vendaKey',
    );
    try {
      await ContaReceberService.cancelarContasReceberDaVenda(
        lojaId: loja,
        vendaKey: vendaKey,
        vendaIdFirebase: idV.isEmpty ? null : idV,
        motivo: 'venda_excluida',
      );
      debugPrint('[VENDAS-DELETE][OK] vendaId=$idV');
    } catch (e) {
      debugPrint('[VENDAS-SERVICE] removerContasReceberVinculadasAVenda: $e');
    }
  }

  /// Após desfazer exclusão de venda fiada: recria 1 título com o total (parcelas múltiplas viram um resumo).
  static Future<void> recriarContaReceberFiadoAposUndoSeAplicavel({
    required Venda venda,
    required String lojaId,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    if (!venda.formasPagamento.toLowerCase().contains('fiado')) return;
    final vk = hiveKeyOrNull(venda.key);
    final idV = idVendaEstavelParaVinculo(venda);
    if (vk == null && idV.isEmpty) return;
    final match = RegExp(
      r'Vencimento:\s*(\d{2})/(\d{2})/(\d{4})',
      caseSensitive: false,
    ).firstMatch(venda.formasPagamento);
    late DateTime venc;
    if (match != null) {
      venc = DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
      );
    } else {
      venc = DateTime.now().add(const Duration(days: 30));
    }
    final crBox = await ContaReceberService.openBoxLoja(loja);
    final totalPago =
        venda.pagamentoDinheiro + venda.pagamentoPix + venda.pagamentoCartao;
    final saldo = calcularSaldoFiado(
      total: venda.total,
      totalPagoAgora: totalPago,
    );
    if (saldo <= 0.01) return;
    final conta = ContaReceber(
      lojaId: loja,
      clienteNome: venda.clienteNome,
      valor: saldo,
      valorOriginal: saldo,
      dataVencimento: venc,
      dataVenda: venda.data,
      vendaKey: _vendaKeyParaContaReceber(vk),
      vendaIdFirebase: _vendaIdFirebaseParaContaReceber(idV),
      observacao: venda.observacao.trim().isEmpty
          ? 'Venda fiada'
          : venda.observacao.trim(),
    );
    await crBox.add(conta);
    await conta.save();
    await ContaReceberFirestoreService.upsertContaReceber(
      conta,
      lastWriteOrigin: 'undo_venda',
    );
  }

  /// Procura o produto no estoque por productId (preferencial), slug ou nome.
  /// Ordem: 1) productId/idFirebase, 2) slug, 3) nome.
  /// Loga [PRODUTO_FALLBACK] quando resolver por slug ou nome (observabilidade).
  static Produto? encontrarProdutoNoEstoque({
    required Box<Produto> produtosBox,
    String? productId,
    String? slug,
    String? nome,
    String? lojaId,
  }) {
    final idTrim = productId?.trim();
    final lowSlug = slug?.trim().toLowerCase();
    final lowNome = nome?.trim().toLowerCase();

    Iterable<Produto> lista = produtosBox.values;
    if (lojaId != null && lojaId.isNotEmpty) {
      lista = lista.where((p) => p.lojaId == lojaId);
    }

    // 1) productId / idFirebase (ou slug canônico antes do primeiro sync)
    if (idTrim != null && idTrim.isNotEmpty) {
      final p =
          lista.firstWhereOrNull((prod) => prod.idFirebase.trim() == idTrim) ??
              lista.firstWhereOrNull((prod) => prod.slug.trim() == idTrim);
      if (p != null) return p;
    }

    // 2) slug
    if (lowSlug != null && lowSlug.isNotEmpty) {
      final p = lista.firstWhereOrNull(
        (prod) => (prod.slug).trim().toLowerCase() == lowSlug,
      );
      if (p != null) {
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por slug | lojaId=$lojaId | slug=$lowSlug | nome=${p.nome} | productId=${p.idFirebase}',
        );
        return p;
      }
    }

    // 3) nome
    if (lowNome != null && lowNome.isNotEmpty) {
      final matches = lista
          .where((prod) => prod.nome.trim().toLowerCase() == lowNome)
          .toList();
      if (matches.length == 1) {
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por nome | lojaId=$lojaId | nome=$lowNome | productId=${matches.single.idFirebase} | matches=1',
        );
        reportProductResolvedByName(
          lojaId: lojaId ?? '',
          fluxo: 'encontrarProdutoNoEstoque',
          nome: lowNome,
          slug: lowSlug,
          productIdRecebido: idTrim,
        );
        return matches.single;
      }
      if (matches.length > 1) {
        debugPrint(
          '[PRODUTO_FALLBACK] Nome ambíguo | lojaId=$lojaId | nome=$lowNome | matches=${matches.length}',
        );
        reportProductResolvedByName(
          lojaId: lojaId ?? '',
          fluxo: 'encontrarProdutoNoEstoque_ambiguo',
          nome: lowNome,
          slug: lowSlug,
          productIdRecebido: idTrim,
        );
        return matches.first;
      }
    }

    return null;
  }

  static bool _vendaPareceIncluirKitOuComboReceita({
    required List<VendaItem> itens,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) {
    for (final it in itens) {
      final p = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: it.productId,
        nome: it.produtoNome,
        lojaId: lojaId,
      );
      if (p == null) continue;
      if (p.ehCombo ||
          p.temComboConfigEfetivo ||
          (p.itensCombo != null && p.itensCombo!.isNotEmpty)) {
        return true;
      }
    }
    return false;
  }

  /// Mapas para [EstoqueTransactionService.devolverEstoqueTransactionBatch]: só **componentes**;
  /// nunca o produto kit virtual (cabeçalho com `linhaContaCustoMercadoria == false` ou `ehCombo`).
  static List<Map<String, dynamic>> _montarItensFirestoreDevolucaoAgrupados({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
    required String vendaIdLog,
  }) {
    final itensVenda = venda.itens;
    if (itensVenda == null || itensVenda.isEmpty) return [];

    final rawJson = venda.itensComboSelecaoJson;
    final selecaoPersistida =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(rawJson);
    final snapKeys = selecaoPersistida?.keys.toList() ?? <int>[];
    final jsonVazio = rawJson == null || rawJson.trim().isEmpty;
    debugPrint(
      '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog json_vazio=$jsonVazio keys=$snapKeys',
    );
    if (!jsonVazio && selecaoPersistida == null) {
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog aviso=json_presente_mas_parse_falhou',
      );
    }

    final (
      itensDevolucao,
      produtosEnc,
      linhaFlags,
    ) = VendaComboEstoqueExpansion.expandirCombos(
      itens: itensVenda,
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: selecaoPersistida,
    );

    final Map<
        String,
        ({
          String? productId,
          String? slug,
          String nomeOriginal,
          String tam,
          String cor,
          String extra,
          int qtd,
        })> agrupado = {};

    for (var i = 0; i < itensDevolucao.length; i++) {
      if (i >= linhaFlags.length || i >= produtosEnc.length) break;
      if (!linhaFlags[i]) {
        debugPrint(
          '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=cabecalho_kit_skip nome=${itensDevolucao[i].produtoNome}',
        );
        continue;
      }
      if (produtosEnc[i].ehCombo) {
        debugPrint(
          '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=produto_combo_skip nome=${produtosEnc[i].nome}',
        );
        continue;
      }
      final it = itensDevolucao[i];
      final pComp = produtosEnc[i];
      final pidLog = (it.productId ?? '').trim().isNotEmpty
          ? it.productId!.trim()
          : pComp.idFirebase.trim();
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=componente produtoId=$pidLog nome=${it.produtoNome} qtd=${it.quantidade}',
      );
      final pid =
          (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
      final slugComp = pComp.slug.trim().isNotEmpty ? pComp.slug.trim() : null;
      final nomeLower = it.produtoNome.trim().toLowerCase();
      final nomeOriginal = it.produtoNome.trim();
      final tam = it.tamanho.trim();
      final cor = it.cor.trim();
      final extra = it.extraValor.trim();
      final key = '${pid ?? ''}\x00$nomeLower\x00$tam\x00$cor\x00$extra';
      final existing = agrupado[key];
      if (existing != null) {
        agrupado[key] = (
          productId: existing.productId,
          slug: existing.slug ?? slugComp,
          nomeOriginal: existing.nomeOriginal,
          tam: existing.tam,
          cor: existing.cor,
          extra: existing.extra,
          qtd: existing.qtd + it.quantidade,
        );
      } else {
        agrupado[key] = (
          productId: pid,
          slug: slugComp,
          nomeOriginal: nomeOriginal,
          tam: tam,
          cor: cor,
          extra: extra,
          qtd: it.quantidade,
        );
      }
    }

    final maps = agrupado.entries
        .where((e) => e.value.qtd > 0)
        .map(
          (e) => {
            'productId': e.value.productId,
            if (e.value.slug != null && e.value.slug!.trim().isNotEmpty)
              'slug': e.value.slug!.trim(),
            'nome': e.value.nomeOriginal,
            'quantidade': e.value.qtd,
            'tamanho': e.value.tam,
            'cor': e.value.cor,
            if (e.value.extra.isNotEmpty) 'extraValor': e.value.extra,
          },
        )
        .toList();

    debugPrint(
      '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog componentes_count=${maps.length}',
    );

    if (maps.isEmpty &&
        _vendaPareceIncluirKitOuComboReceita(
          itens: itensVenda,
          produtosBox: produtosBox,
          lojaId: lojaId,
        )) {
      debugPrint(
        '[COMBO-DEVOLUCAO] sem_componentes motivo=expansao_filtrou_tudo_ou_receita_indisponivel vendaId=$vendaIdLog',
      );
      throw StateError(
        'Devolução de estoque do kit: não há linhas de componentes para devolver. '
        'Sincronize o app ou verifique se a receita do combo ainda existe no cadastro.',
      );
    }

    return maps;
  }

  /// Fallback: monta itens de devolução pela mesma expansão de combo/variação da baixa.
  static List<Map<String, dynamic>> _montarItensDevolucaoViaExpansaoVenda({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) {
    final itensVenda = venda.itens;
    if (itensVenda == null || itensVenda.isEmpty) return [];

    final selecao =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
      venda.itensComboSelecaoJson,
    );
    final (
      itensExp,
      produtosEnc,
      linhaFlags,
    ) = VendaComboEstoqueExpansion.expandirCombos(
      itens: itensVenda,
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: selecao,
    );

    final itensFiltrados = <VendaItem>[];
    final prodFiltrados = <Produto>[];
    for (var i = 0; i < itensExp.length; i++) {
      if (i >= linhaFlags.length || i >= produtosEnc.length) break;
      if (!linhaFlags[i]) continue;
      if (produtosEnc[i].ehCombo) continue;
      itensFiltrados.add(itensExp[i]);
      prodFiltrados.add(produtosEnc[i]);
    }
    if (itensFiltrados.isEmpty) return [];

    return VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensFiltrados,
      produtosEncontrados: prodFiltrados,
    );
  }

  /// Linhas canônicas de estoque (componentes de combo expandidos) para diff na edição.
  static List<Map<String, dynamic>> montarLinhasEstoqueCanonicasParaEdicao({
    required List<VendaItem> itens,
    required Box<Produto> produtosBox,
    required String lojaId,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
    String? itensComboSelecaoJson,
  }) {
    final comboJson = itensComboSelecaoJson ??
        VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
          itensComboSelecaoPorIndice,
        );
    final vTemp = Venda(
      clienteNome: '_edicao_diff_',
      produtosDescricao: '',
      quantidade: itens.length,
      preco: 0,
      total: 0,
      formasPagamento: '',
      data: DateTime.now(),
      tamanho: '',
      vendedor: 'App',
      observacao: '',
      itens: itens,
      itensComboSelecaoJson: comboJson,
      lojaId: lojaId,
    );
    return _resolverItensDevolucaoParaVenda(
      venda: vTemp,
      produtosBox: produtosBox,
      lojaId: lojaId,
      vendaIdLog: 'edicao_diff',
    );
  }

  /// Validação pré-salvamento na UI: edição administrativa pula estoque; mudança de itens valida só o delta de baixa.
  static VendaEdicaoValidacaoPreSalvamentoUi
      resolverValidacaoEstoquePreSalvamentoEdicao({
    required Venda vendaOriginal,
    required List<VendaItem> itensNovos,
    required Box<Produto> produtosBox,
    required String lojaId,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
  }) {
    final comboJsonNovo =
        VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
      itensComboSelecaoPorIndice,
    );
    if (VendaEdicaoEstoqueDiff.itensVendaEquivalentes(
      antigos: vendaOriginal.itens ?? <VendaItem>[],
      novos: itensNovos,
      comboJsonAntigo: vendaOriginal.itensComboSelecaoJson,
      comboJsonNovo: comboJsonNovo,
    )) {
      return const VendaEdicaoValidacaoPreSalvamentoUi(
        pularValidacaoEstoque: true,
        linhasValidarBaixa: [],
      );
    }

    final linhasAntigas = montarLinhasEstoqueCanonicasParaEdicao(
      itens: vendaOriginal.itens ?? <VendaItem>[],
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoJson: vendaOriginal.itensComboSelecaoJson,
    );
    final linhasNovas = montarLinhasEstoqueCanonicasParaEdicao(
      itens: itensNovos,
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
      itensComboSelecaoJson: comboJsonNovo,
    );
    final delta = VendaEdicaoEstoqueDiff.calcularDelta(
      linhasAntigas: linhasAntigas,
      linhasNovas: linhasNovas,
    );

    return VendaEdicaoValidacaoPreSalvamentoUi(
      pularValidacaoEstoque: false,
      linhasValidarBaixa: delta.baixar,
    );
  }

  /// Soma [valorPago] nas contas a receber vinculadas à venda (baixas parciais).
  static Future<double> valorPagoParcialContasVenda({
    required Venda venda,
    required String lojaId,
  }) async {
    final vk = hiveKeyOrNull(venda.key);
    if (vk == null && idVendaEstavelParaVinculo(venda).isEmpty) return 0;

    final loja = lojaId.trim();
    if (loja.isEmpty) return 0;

    try {
      final crBox = await ContaReceberService.openBoxLoja(loja);
      var pagoContas = 0.0;
      for (final c in crBox.values) {
        if (contaReceberVinculadaAVenda(
          conta: c,
          lojaId: loja,
          vendaKey: vk,
          vendaIdFirebase: idVendaEstavelParaVinculo(venda),
        )) {
          pagoContas += c.valorPago;
        }
      }
      return pagoContas;
    } catch (_) {
      return 0;
    }
  }

  /// Valor já recebido (pagamentos na venda + baixas parciais nas contas vinculadas).
  static Future<double> valorJaRecebidoNaVenda({
    required Venda venda,
    required String lojaId,
  }) async {
    final pagamentosVenda =
        venda.pagamentoDinheiro + venda.pagamentoPix + venda.pagamentoCartao;
    return pagamentosVenda +
        await valorPagoParcialContasVenda(venda: venda, lojaId: lojaId);
  }

  static Future<void> validarEdicaoNaoReduzAbaixoValorRecebido({
    required Venda vendaOriginal,
    required double novoTotal,
    required String lojaId,
  }) async {
    final pagoParcialContas = await valorPagoParcialContasVenda(
      venda: vendaOriginal,
      lojaId: lojaId,
    );
    if (pagoParcialContas <= 0.01) return;

    final recebido = await valorJaRecebidoNaVenda(
      venda: vendaOriginal,
      lojaId: lojaId,
    );
    if (novoTotal + 0.01 < recebido) {
      throw ArgumentError(
        'Não é possível reduzir a venda abaixo do valor já recebido.',
      );
    }
  }

  static bool _edicaoRequerRemocaoContasReceber({
    required bool isFiado,
    required double saldoFiado,
  }) =>
      !isFiado || saldoFiado <= 0.01;

  static void _assertContasReceberRemoviveisSemRecebimentosParciais(
    Iterable<ContaReceber> contas,
  ) {
    if (contas.any((c) => c.valorPago > 0.01)) {
      throw ArgumentError(mensagemNaoPodeRemoverFiadoComRecebimentosParciais);
    }
  }

  static Future<List<ContaReceber>> _contasReceberVinculadasAVenda({
    required Venda venda,
    required String lojaId,
  }) async {
    final vk = hiveKeyOrNull(venda.key);
    final vendaIdVinculo = idVendaEstavelParaVinculo(venda);
    if (vk == null && vendaIdVinculo.isEmpty) return const [];

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    return crBox.values
        .where(
          (c) => contaReceberVinculadaAVenda(
            conta: c,
            lojaId: lojaId,
            vendaKey: vk,
            vendaIdFirebase: vendaIdVinculo,
          ),
        )
        .toList();
  }

  /// Auditoria pré-mutação: não apagar CR com baixas se a edição removeria o fiado.
  static Future<void> _validarRemocaoContasReceberAntesDeMutarVenda({
    required Venda vendaOriginal,
    required String lojaId,
    required bool isFiado,
    required double saldoFiado,
  }) async {
    if (!_edicaoRequerRemocaoContasReceber(
      isFiado: isFiado,
      saldoFiado: saldoFiado,
    )) {
      return;
    }
    final contas = await _contasReceberVinculadasAVenda(
      venda: vendaOriginal,
      lojaId: lojaId,
    );
    _assertContasReceberRemoviveisSemRecebimentosParciais(contas);
  }

  static double _saldoFiadoPreviewEdicao({
    required bool isFiado,
    required double totalPreview,
    required double dinheiro,
    required double pix,
    required double cartao,
  }) {
    var d = dinheiro;
    var p = pix;
    var c = cartao;
    if (!isFiado && d == 0 && p == 0 && c == 0) {
      d = totalPreview;
    }
    final totalPagoAgora = d + p + c;
    return isFiado
        ? calcularSaldoFiado(
            total: totalPreview,
            totalPagoAgora: totalPagoAgora,
          )
        : 0.0;
  }

  static Future<void> _syncClienteAposEdicaoLocal({
    required Cliente cliente,
    required String lojaId,
  }) async {
    final override = debugEditarVendaSyncClienteOverride;
    if (override != null) {
      await override(cliente, lojaId: lojaId);
      return;
    }
    await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
  }

  static Future<bool> _syncVendaAposEdicaoLocal({
    required Venda venda,
    required String lojaId,
  }) async {
    final override = debugEditarVendaSyncVendaOverride;
    if (override != null) {
      return override(venda, lojaId: lojaId);
    }
    return VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
  }

  static void _agendarSyncRemotoAposEdicaoLocal({
    required Cliente cliente,
    required Venda venda,
    required String lojaEfetiva,
    required bool isFiado,
    required double saldoFiado,
    void Function(String message)? onSyncError,
  }) {
    unawaited(() async {
      try {
        await _syncClienteAposEdicaoLocal(
          cliente: cliente,
          lojaId: lojaEfetiva,
        );
      } catch (e) {
        debugPrint(
          '⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})',
        );
        try {
          onSyncError?.call('Cliente não sincronizado. Verifique a conexão.');
        } catch (e2) {
          debugPrint(
            '⚠️ [VENDA-EDICAO] onSyncError cliente falhou (type=${e2.runtimeType})',
          );
        }
      }
      try {
        final ok = await _syncVendaAposEdicaoLocal(
          venda: venda,
          lojaId: lojaEfetiva,
        );
        if (!ok) {
          try {
            onSyncError?.call(
              'Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.',
            );
          } catch (e2) {
            debugPrint(
              '⚠️ [VENDA-EDICAO] onSyncError venda falhou (type=${e2.runtimeType})',
            );
          }
        } else if (isFiado && saldoFiado > 0.01) {
          try {
            await ContaReceberVendaBackfillService
                .republicarContasVinculadasAVenda(
              lojaId: lojaEfetiva,
              venda: venda,
            );
          } catch (e) {
            debugPrint(
              '⚠️ [VENDAS-SERVICE] Falha ao republicar contas fiado (edição) (type=${e.runtimeType})',
            );
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ Erro inesperado ao sincronizar venda com Firestore (type=${e.runtimeType})',
        );
        try {
          onSyncError?.call(
            'Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.',
          );
        } catch (e2) {
          debugPrint(
            '⚠️ [VENDA-EDICAO] onSyncError venda falhou (type=${e2.runtimeType})',
          );
        }
      }
    }());
  }

  /// Aplica delta de estoque da edição de forma atômica (devolver+baixar num TX).
  /// Retorna a operationKey do journal (completar após [venda.save]), ou null se sem movimento.
  static Future<String?> _aplicarDeltaEstoqueEdicaoVenda({
    required String lojaId,
    required Box<Produto> produtosBox,
    required VendaEdicaoDeltaEstoque delta,
    required String vendedor,
    required String vendaIdLog,
  }) async {
    if (delta.semMovimento) {
      debugPrint('[VENDA-EDICAO] sem_movimento_estoque vendaId=$vendaIdLog');
      return null;
    }

    final itensAssinados =
        VendaEdicaoEstoqueDiff.linhasAssinadasCanonicas(delta);
    if (itensAssinados.isEmpty) {
      debugPrint(
        '[VENDA-EDICAO] delta_liquido_zero vendaId=$vendaIdLog',
      );
      return null;
    }

    final deltaHash = VendaEdicaoEstoqueDiff.computeCanonicalDeltaHash(delta);
    final operationId = VendaEdicaoEstoqueDiff.buildEditStockOperationId(
      vendaId: vendaIdLog,
      deltaHash: deltaHash,
    );
    final operationKey = VendaOperationJournalService.buildOperationKey(
      lojaId: lojaId,
      stockEffectHash: deltaHash,
      saleIntentId:
          VendaEdicaoEstoqueDiff.buildEditStockJournalSaleIntentId(vendaIdLog),
    );

    await VendaOperationJournalService.reserveOrRecover(
      lojaId: lojaId,
      operationKey: operationKey,
      stockEffectHash: deltaHash,
      requiredOperationId: operationId,
    );

    await debugForcarFalhaEstoqueEdicaoAntesSave?.call();

    debugPrint(
      '[VENDA-EDICAO] reconcile_atomico count=${itensAssinados.length} '
      'vendaId=$vendaIdLog operationId=$operationId',
    );

    final reconcile = await EstoqueTransactionService
        .reconciliarEdicaoEstoqueTransactionBatch(
      lojaId: lojaId,
      itensAssinados: itensAssinados,
      operationId: operationId,
      deltaHash: deltaHash,
    );

    var resultados = <EstoqueTransactionResult>[];
    if (reconcile.alreadyApplied) {
      debugPrint(
        '[VENDA-EDICAO] reconcile_alreadyApplied operationId=$operationId',
      );
      await EstoqueTransactionService.projetarHiveAposReconcileAlreadyApplied(
        lojaId: lojaId,
        produtosBox: produtosBox,
        itensAssinados: itensAssinados,
      );
    } else {
      resultados = reconcile.transactionResults;
      final teveBaixa = itensAssinados.any(
        (m) => ((m['quantidade'] as num?)?.toInt() ?? 0) < 0,
      );
      if (teveBaixa) {
        await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(
          lojaId,
          resultados,
        );
      }
      for (final r in resultados) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaId,
          result: r,
        );
      }
    }

    final teveDevolucao = itensAssinados.any(
      (m) => ((m['quantidade'] as num?)?.toInt() ?? 0) > 0,
    );
    final teveBaixaLinha = itensAssinados.any(
      (m) => ((m['quantidade'] as num?)?.toInt() ?? 0) < 0,
    );

    if (teveDevolucao) {
      final pisoResults =
          await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );
      resultados = [...resultados, ...pisoResults];
    }
    if (teveBaixaLinha) {
      final tetoResults = await ComboKitStockService
          .aplicarTetoEstoqueComboAposBaixaSemAbortarVenda(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda:
            ComboKitStockService.produtoIdsDeResultadosBaixa(
          resultados.where((r) => r.quantidadeDebitada > 0).toList(),
        ),
      );
      resultados = [...resultados, ...tetoResults];
    }

    if (resultados.isNotEmpty || reconcile.alreadyApplied) {
      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: lojaId,
        produtosBox: produtosBox,
        resultadosPrincipais: resultados,
        resultadosComboExtra: const [],
      );
    }

    for (final r in resultados) {
      final debitada = r.quantidadeDebitada;
      if (debitada > 0) {
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'saida',
          quantidade: debitada,
          motivo: 'Venda (edição)',
          usuario: vendedor,
        ).catchError((_) {});
      } else if (debitada < 0) {
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'entrada',
          quantidade: debitada.abs(),
          motivo: 'Devolução (edição venda)',
          usuario: vendedor,
          vendaId: vendaIdLog,
        ).catchError((_) {});
      }
    }

    await debugAposReconcileEstoqueEdicaoAntesVendaSave?.call();

    return operationKey;
  }

  static Future<void> _atualizarContasReceberAposEdicaoVenda({
    required Venda venda,
    required String lojaId,
    required bool isFiado,
    required double saldoFiado,
    required DateTime? dataVencimentoFiado,
    required int quantidadeParcelasFiado,
    required int intervaloParcelasDias,
    required String observacao,
    required String clienteNome,
    required bool itensEquivalentes,
    required double totalAnterior,
  }) async {
    final vk = hiveKeyOrNull(venda.key);
    final vendaIdVinculo = idVendaEstavelParaVinculo(venda);
    if (vk == null && vendaIdVinculo.isEmpty) return;

    final crBox = await ContaReceberService.openBoxLoja(lojaId);

    final contasVinculadas = crBox.values
        .where(
          (c) => contaReceberVinculadaAVenda(
            conta: c,
            lojaId: lojaId,
            vendaKey: vk,
            vendaIdFirebase: vendaIdVinculo,
          ),
        )
        .toList();

    if (_edicaoRequerRemocaoContasReceber(
      isFiado: isFiado,
      saldoFiado: saldoFiado,
    )) {
      _assertContasReceberRemoviveisSemRecebimentosParciais(contasVinculadas);
      await debugForcarFalhaTransicaoCrLocalEdicao?.call();
      for (final c in contasVinculadas) {
        await c.delete();
      }
      return;
    }

    if (dataVencimentoFiado == null) {
      throw ArgumentError('Informe a data de vencimento da venda fiada.');
    }

    if (contasVinculadas.isEmpty) {
      final qtdParcelas = safeInt(
        quantidadeParcelasFiado.clamp(1, 48),
        fallback: 1,
      );
      final intervalo = safeInt(
        intervaloParcelasDias.clamp(1, 120),
        fallback: 30,
      );
      final valoresParcelas = _parcelarValores(saldoFiado, qtdParcelas);
      final contasNovas = <ContaReceber>[];
      for (var i = 0; i < qtdParcelas; i++) {
        final venc = dataVencimentoFiado.add(Duration(days: i * intervalo));
        contasNovas.add(
          ContaReceber(
            lojaId: lojaId,
            clienteNome: clienteNome,
            valor: valoresParcelas[i],
            valorOriginal: valoresParcelas[i],
            dataVencimento: venc,
            dataVenda: venda.data,
            vendaKey: _vendaKeyParaContaReceber(vk),
            vendaIdFirebase: _vendaIdFirebaseParaContaReceber(vendaIdVinculo),
            observacao: qtdParcelas > 1
                ? 'Parcela ${i + 1}/$qtdParcelas${observacao.trim().isNotEmpty ? ' - ${observacao.trim()}' : ''}'
                : (observacao.trim().isEmpty
                    ? 'Venda fiada'
                    : observacao.trim()),
            parcelaNumero: i + 1,
            parcelaTotal: qtdParcelas,
          ),
        );
      }
      await _persistirContasReceberNaBox(
        crBox: crBox,
        contas: contasNovas,
        lojaId: lojaId,
        vendaIdVinculo: vendaIdVinculo,
        vendaHiveKey: vk,
        // Edição: CR remota best-effort após Hive local (create mantém throw+rollback).
        remoteBestEffort: true,
      );
      return;
    }

    final totalPagoContas = contasVinculadas.fold<double>(
      0,
      (s, c) => s + c.valorPago,
    );
    final novoSaldoAberto = (saldoFiado - totalPagoContas).clamp(
      0.0,
      double.infinity,
    );

    if (itensEquivalentes && (totalAnterior - venda.total).abs() < 0.01) {
      for (final c in contasVinculadas) {
        c.clienteNome = clienteNome;
        c.dataVenda = venda.data;
        if (contasVinculadas.length == 1 && c.valorPago <= 0.01) {
          c.dataVencimento = dataVencimentoFiado;
        }
        await c.save();
      }
      return;
    }

    if (contasVinculadas.length == 1) {
      final c = contasVinculadas.single;
      c.clienteNome = clienteNome;
      c.dataVenda = venda.data;
      c.valor = novoSaldoAberto;
      c.valorOriginal = novoSaldoAberto + c.valorPago;
      c.dataVencimento = dataVencimentoFiado;
      c.normalizarCamposFinanceiros();
      await c.save();
      return;
    }

    // Várias parcelas: ajusta saldo proporcional preservando histórico de pagamentos.
    final saldoAnterior = contasVinculadas.fold<double>(
      0,
      (s, c) => s + c.valor,
    );
    if (saldoAnterior <= 0.01) return;
    final fator = novoSaldoAberto / saldoAnterior;
    for (final c in contasVinculadas) {
      c.clienteNome = clienteNome;
      c.dataVenda = venda.data;
      final novoValor = (c.valor * fator);
      c.valor = novoValor;
      c.valorOriginal = novoValor + c.valorPago;
      c.normalizarCamposFinanceiros();
      await c.save();
    }
  }

  /// Resolve itens para devolução: agrupado → expansão → texto legado.
  static List<Map<String, dynamic>> _resolverItensDevolucaoParaVenda({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
    required String vendaIdLog,
  }) {
    final itensVenda = venda.itens;
    if (itensVenda != null && itensVenda.isNotEmpty) {
      var maps = _montarItensFirestoreDevolucaoAgrupados(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaIdLog: vendaIdLog,
      );
      if (maps.isEmpty) {
        maps = _montarItensDevolucaoViaExpansaoVenda(
          venda: venda,
          produtosBox: produtosBox,
          lojaId: lojaId,
        );
        if (maps.isNotEmpty) {
          debugPrint(
            '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog fallback=expansao_venda count=${maps.length}',
          );
        }
      }
      if (maps.isNotEmpty) return maps;
      debugPrint(
        '[VENDA_DELETE] itens_estruturados_sem_maps vendaId=$vendaIdLog linhas=${itensVenda.length}',
      );
    }

    final itensFallback = <Map<String, dynamic>>[];
    final linhas = venda.produtosDescricao.split('\n');
    for (var linha in linhas) {
      try {
        if (!linha.contains(' x ')) continue;
        final partes = linha.split(' x ');
        if (partes.length < 2) continue;
        final qtd = int.tryParse(partes[0].trim()) ?? 1;
        if (qtd <= 0) continue;
        final restante = partes[1].split(' - R\$');
        var nome = restante.isNotEmpty ? restante.first.trim() : '';
        if (nome.isEmpty) continue;
        if (nome.contains(' - ')) nome = nome.split(' - ').first.trim();
        if (nome.isEmpty) continue;
        itensFallback.add({'nome': nome, 'quantidade': qtd});
      } catch (_) {}
    }
    return itensFallback;
  }

  /// Logs [COMBO-DEVOLUCAO-ITEM] / [COMBO-DEVOLUCAO-RESULT]; falha se `count==0` sem idempotência prévia.
  static Future<List<EstoqueTransactionResult>> _devolverEstoqueComLogsCombo({
    required String lojaId,
    required String vendaId,
    required List<Map<String, dynamic>> itens,
    String estornoOrigemCatalogo = 'venda_delete',
  }) async {
    for (final m in itens) {
      debugPrint(
        '[COMBO-DEVOLUCAO-ITEM] productId=${m['productId']} slug=${m['slug']} nome=${m['nome']} qtd=${m['quantidade']}',
      );
    }
    final results =
        await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: itens,
      vendaIdParaIdempotencia: vendaId,
      estornoOrigemCatalogo: estornoOrigemCatalogo,
    );
    final ids = results.map((r) => r.produtoId).join(',');
    debugPrint(
      '[COMBO-DEVOLUCAO-RESULT] vendaId=$vendaId count=${results.length} ids=$ids',
    );
    if (results.isEmpty && itens.isNotEmpty) {
      final ja = await EstoqueTransactionService.devolucaoVendaJaAplicada(
        lojaId,
        vendaId,
      );
      if (!ja) {
        throw StateError(
          '[COMBO-DEVOLUCAO-RESULT] count=0 com itens=${itens.length} e sem idempotência local — devolução não aplicada.',
        );
      }
    }
    return results;
  }

  /// Garante e retorna o cliente (cria se não existir), respeitando a loja.
  /// Se [clienteExistente] for fornecido, usa esse cliente (evita matching errado).
  static Cliente _getOrCreateCliente({
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required String lojaId,
    Cliente? clienteExistente, // Cliente já identificado (ex: da Nova Venda)
  }) {
    if (clienteExistente != null) {
      // ignore: experimental_member_use
      clienteExistente.historico ??= HiveList(vendasBox);
      return clienteExistente;
    }

    final lower = clienteNome.trim().toLowerCase();

    final existente = clientesBox.values.firstWhereOrNull(
      (c) => c.lojaId == lojaId && c.nome.trim().toLowerCase() == lower,
    );

    if (existente != null) {
      // ignore: experimental_member_use
      existente.historico ??= HiveList(vendasBox);
      return existente;
    }

    final novo = Cliente(
      nome: capitalizeWords(clienteNome.trim()),
      telefone: '',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: lojaId,
      historico: HiveList(vendasBox), // ignore: experimental_member_use
    );
    clientesBox.add(novo);
    return novo;
  }

  // ---------------------------
  // Registrar venda de 1 item
  // ---------------------------

  static Future<Venda> registrarVenda({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required Produto produto,
    int quantidade = 1,
    String tamanho = '',
    String cor = '',
    String formaPagamento = 'dinheiro',
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId, // 🔹 multi-loja
  }) {
    final item = VendaItem(
      produtoNome: produto.nome,
      quantidade: quantidade,
      precoUnitario: produto.precoFinal,
      tamanho: tamanho,
      cor: cor,
      productId:
          produto.idFirebase.trim().isNotEmpty ? produto.idFirebase : null,
      custoUnitario: produto.custoUnitarioVariacao(tamanho, cor),
    );

    if (dinheiro == 0 && pix == 0 && cartao == 0) {
      final totalPrevisto =
          (produto.precoFinal * quantidade) * (1 - descontoPct / 100) + frete;
      switch (formaPagamento.toLowerCase()) {
        case 'pix':
          pix = totalPrevisto;
          break;
        case 'cartao':
        case 'cartão':
          cartao = totalPrevisto;
          break;
        default:
          dinheiro = totalPrevisto;
      }
    }

    return registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: clienteNome,
      itens: [item],
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
      vendedor: vendedor,
      observacao: observacao,
      frete: frete,
      descontoPct: descontoPct,
      lojaId: lojaId, // 🔹 repassa
    );
  }

  // ---------------------------
  // Registrar venda multi-itens
  // ---------------------------

  static Future<Venda> registrarVendaMulti({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required List<VendaItem> itens,
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String? vendedorUid,
    String? vendedorNome,
    String? vendedorEmail,
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId,
    Cliente? clienteExistente,
    String? idFirebaseToReuse,
    void Function(String message)? onSyncError,
    bool isFiado = false,
    DateTime? dataVencimentoFiado,
    int quantidadeParcelasFiado = 1,
    int intervaloParcelasDias = 30,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
    void Function(String? numeroSorte)? onNumeroSorteGerado,
    String? saleIntentId,
    String? saleIntentOrigin,
    void Function()? onLocalPersistUiReady,
  }) {
    final chave = _chaveCoalesceRegistrarVenda(
      lojaId: lojaId,
      clienteNome: clienteExistente?.nome ?? clienteNome,
      itens: itens,
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
      frete: frete,
      descontoPct: descontoPct,
      observacao: observacao,
      isFiado: isFiado,
      idFirebaseToReuse: idFirebaseToReuse,
      saleIntentId: saleIntentId,
      quantidadeParcelasFiado: quantidadeParcelasFiado,
      itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
    );

    final placeholder = Completer<Venda>();
    final promessa = placeholder.future;
    final existente = _registrarVendaCoalesce.putIfAbsent(
      chave,
      () => promessa,
    );
    if (!identical(existente, promessa)) return existente;

    (() async {
      try {
        final venda = await _registrarVendaMultiCorpo(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: clienteNome,
          itens: itens,
          dinheiro: dinheiro,
          pix: pix,
          cartao: cartao,
          vendedor: vendedor,
          vendedorUid: vendedorUid,
          vendedorNome: vendedorNome,
          vendedorEmail: vendedorEmail,
          observacao: observacao,
          frete: frete,
          descontoPct: descontoPct,
          lojaId: lojaId,
          clienteExistente: clienteExistente,
          idFirebaseToReuse: idFirebaseToReuse,
          onSyncError: onSyncError,
          isFiado: isFiado,
          dataVencimentoFiado: dataVencimentoFiado,
          quantidadeParcelasFiado: quantidadeParcelasFiado,
          intervaloParcelasDias: intervaloParcelasDias,
          itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
          onNumeroSorteGerado: onNumeroSorteGerado,
          saleIntentId: saleIntentId,
          saleIntentOrigin: saleIntentOrigin,
          onLocalPersistUiReady: onLocalPersistUiReady,
        );
        if (!placeholder.isCompleted) placeholder.complete(venda);
      } catch (e, st) {
        if (!placeholder.isCompleted) placeholder.completeError(e, st);
      } finally {
        _registrarVendaCoalesce.remove(chave);
      }
    }());

    return promessa;
  }

  static Future<Venda> _registrarVendaMultiCorpo({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required List<VendaItem> itens,
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String? vendedorUid,
    String? vendedorNome,
    String? vendedorEmail,
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId, // 🔹 multi-loja
    Cliente?
        clienteExistente, // 🔹 quando já identificado (evita matching errado)
    String?
        idFirebaseToReuse, // 🔹 em edição: reutiliza o id da venda antiga (evita duplicata)
    void Function(String message)?
        onSyncError, // 🔹 feedback ao usuário quando sync Firestore falhar
    bool isFiado = false, // 🔹 venda fiada: gera conta a receber
    DateTime? dataVencimentoFiado, // 🔹 vencimento da conta (quando isFiado)
    int quantidadeParcelasFiado = 1, // 🔹 número de parcelas do fiado
    int intervaloParcelasDias = 30, // 🔹 intervalo em dias entre parcelas
    Map<int, List<Map<String, dynamic>>>?
        itensComboSelecaoPorIndice, // 🔹 seleção do cliente para combos
    void Function(String? numeroSorte)? onNumeroSorteGerado,
    String? saleIntentId,
    String? saleIntentOrigin,
    void Function()? onLocalPersistUiReady,
  }) async {
    if (itens.isEmpty) {
      throw Exception('Nenhum item informado.');
    }

    final lojaEfetiva = await LojaAtivaResolver.requireActive(
      origem: 'VendasService.registrarVendaMulti',
    );
    if (lojaId != null &&
        lojaId.trim().isNotEmpty &&
        lojaId.trim() != lojaEfetiva) {
      logW(
        '[VENDAS-SERVICE][LOJA] param=${lojaId.trim()} ignorado; '
        'usando loja ativa=$lojaEfetiva',
      );
    }
    logD('[VENDAS-SERVICE][LOJA] lojaId=$lojaEfetiva');

    validarParametrosVendaFiada(
      isFiado: isFiado,
      dataVencimentoFiado: dataVencimentoFiado,
      clienteNome: clienteExistente?.nome ?? clienteNome,
      total: itens.fold<double>(
                0.0,
                (acc, it) => acc + (it.precoUnitario * it.quantidade),
              ) *
              (1 - descontoPct / 100) +
          frete,
      quantidadeParcelasFiado: quantidadeParcelasFiado,
      totalPagoAgora: dinheiro + pix + cartao,
    );

    // 1) Sincroniza produtos das linhas antes de expandir (preenche idFirebase para match)
    final produtosDasLinhas = <Produto>[];
    for (final item in itens) {
      final p = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: item.productId,
        nome: item.produtoNome,
        lojaId: lojaEfetiva,
      );
      if (p != null) produtosDasLinhas.add(p);
    }
    if (produtosDasLinhas.isNotEmpty) {
      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaEfetiva,
        produtos: produtosDasLinhas,
      );
    }

    // 2) expande combos e encontra produtos (para baixa de estoque)
    final (
      itensParaEstoque,
      produtosEncontrados,
      linhaContaCustoMercadoria,
    ) = VendaComboEstoqueExpansion.expandirCombos(
      itens: itens,
      produtosBox: produtosBox,
      lojaId: lojaEfetiva,
      itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
    );

    // 2) cliente
    final cliente = _getOrCreateCliente(
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: clienteNome,
      lojaId: lojaEfetiva,
      clienteExistente: clienteExistente,
    );

    final explicitExp = List<bool>.generate(
      itensParaEstoque.length,
      (i) => itensParaEstoque[i].custoUnitario != null,
    );
    for (var i = 0; i < itensParaEstoque.length; i++) {
      final itemExp = itensParaEstoque[i];
      final pExp = produtosEncontrados[i];
      itemExp.custoUnitario = _resolverCustoItem(pExp, itemExp);
    }
    final explicitOrig = List<bool>.generate(
      itens.length,
      (i) => itens[i].custoUnitario != null,
    );
    final produtosLinhaOriginal = <Produto>[];
    for (var k = 0; k < itens.length; k++) {
      final itemOriginal = itens[k];
      final pLocal = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: itemOriginal.productId,
        nome: itemOriginal.produtoNome,
        lojaId: lojaEfetiva,
      );
      produtosLinhaOriginal.add(pLocal ?? Produto.vazio());
      if (pLocal != null) {
        itemOriginal.custoUnitario = _resolverCustoItem(pLocal, itemOriginal);
      }
    }

    // 3) baixa estoque via transação Firestore (OBRIGATÓRIO - sem fallback Hive)
    // Usa itensParaEstoque (combos já expandidos) para dar baixa em cada produto individual
    // Exige tamanho/cor quando o produto tem estoque por variação para baixa correta no Firestore
    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    final stockEffectHash =
        EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
    final coordinatedIntentId = (saleIntentId ?? '').trim();
    final isCoordinatedPdv = coordinatedIntentId.isNotEmpty;
    final operationKey = VendaOperationJournalService.buildOperationKey(
      lojaId: lojaEfetiva,
      stockEffectHash: stockEffectHash,
      saleIntentId: isCoordinatedPdv ? coordinatedIntentId : null,
    );

    final coordinatedOrigin =
        (saleIntentOrigin ?? SaleIntentOrigins.pdvManual).trim();
    SaleIntentReservation? saleIntentReservation;
    var saleIntentStatus = SaleIntentStatus.reserved;

    if (isCoordinatedPdv) {
      debugPrint(
        '[H1-TRACE] stage=before_sale_intent_reserve '
        'lojaId=$lojaEfetiva intentId=$coordinatedIntentId',
      );
      saleIntentReservation = await SaleIntentService.reserveOrJoin(
        lojaId: lojaEfetiva,
        saleIntentId: coordinatedIntentId,
        origin: coordinatedOrigin,
        stockEffectHash: stockEffectHash,
      );
      saleIntentStatus = saleIntentReservation.status;
      debugPrint(
        '[H1-TRACE] stage=after_sale_intent_reserve '
        'status=${saleIntentStatus.wireValue} '
        'opId=${saleIntentReservation.operationId}',
      );

      final earlyOpId = saleIntentReservation.operationId;
      final vendaJaPersistida = _findVendaHivePorIdFirebase(
        vendasBox,
        earlyOpId,
        lojaEfetiva,
      );
      if (saleIntentStatus == SaleIntentStatus.completed &&
          vendaJaPersistida != null) {
        return vendaJaPersistida;
      }
    }

    final journalEntry = await VendaOperationJournalService.reserveOrRecover(
      lojaId: lojaEfetiva,
      operationKey: operationKey,
      stockEffectHash: stockEffectHash,
      requiredOperationId:
          isCoordinatedPdv ? saleIntentReservation!.operationId : null,
      explicitOperationId: isCoordinatedPdv ? null : idFirebaseToReuse?.trim(),
    );
    final idFirebaseReservado = journalEntry.operationId;
    debugPrint(
      '[H1-TRACE] stage=after_journal_reserve '
      'opId=$idFirebaseReservado key=$operationKey',
    );
    assert(
      !isCoordinatedPdv ||
          idFirebaseReservado == saleIntentReservation!.operationId,
      'journal deve usar operationId remoto oficial',
    );
    List<EstoqueTransactionResult> txResults = [];
    List<EstoqueTransactionResult> txResultsComboCap = [];
    var baixaEstoqueConcluida = false;
    var baixaEstoqueAplicadaNestaExecucao = false;
    late Venda venda;
    late final dynamic addedKey;
    late final double subtotal;
    late final double total;
    late final double totalPagoAgora;
    late final double saldoFiado;
    late final String formasPagamentoTexto;

    try {
      debugPrint(
        '[H1-TRACE] stage=before_prep_remoto lojaId=$lojaEfetiva '
        'produtos=${produtosEncontrados.length}',
      );
      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaEfetiva,
        produtos: produtosEncontrados,
      );
      debugPrint('[H1-TRACE] stage=after_prep_remoto lojaId=$lojaEfetiva');

      await debugAntesBaixaEstoqueBarrier?.call();

      debugPrint(
        '[H1-TRACE] stage=before_batch_idempotent '
        'lojaId=$lojaEfetiva itemCount=${txItems.length} '
        'coordinated=$isCoordinatedPdv stockPath=batch_idempotent',
      );
      debugPrint(
        '[M39-ESTOQUE-VENDA] stage=start lojaId=$lojaEfetiva '
        'sellerUid=${(vendedorUid ?? '').trim()} '
        'itemCount=${txItems.length} operationId=$idFirebaseReservado '
        'saleIntentId=$coordinatedIntentId',
      );
      for (final it in txItems) {
        final pid =
            (it['productId'] ?? it['produtoId'] ?? it['id'] ?? '').toString();
        final qtd = it['quantidade'] ?? it['qtd'] ?? '';
        final tam = (it['tamanho'] ?? it['size'] ?? '').toString().trim();
        final cor = (it['cor'] ?? it['color'] ?? '').toString().trim();
        final extra =
            (it['extraValor'] ?? it['variacaoExtra'] ?? '').toString().trim();
        final stockKey = EstoqueTransactionService.stockItemKey(
          lojaId: lojaEfetiva,
          produtoId: pid,
          tamanho: tam,
          cor: cor,
          variacaoExtra: extra,
        );
        debugPrint(
          '[M39-ESTOQUE-VARIACAO] stage=start vendaId=$idFirebaseReservado '
          'produtoId=$pid variacaoId=${[
            if (tam.isNotEmpty) tam,
            if (cor.isNotEmpty) cor,
            if (extra.isNotEmpty) extra
          ].join('/')} sku= stockItemKey=$stockKey '
          'qtdVendida=$qtd operationId=$idFirebaseReservado',
        );
        debugPrint(
          '[M39-ESTOQUE-VENDA] produtoId=$pid qtdVendida=$qtd '
          'tamanho=$tam cor=$cor sellerUid=${(vendedorUid ?? '').trim()}',
        );
      }
      final baixaOp = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: lojaEfetiva,
        itens: txItems,
        operationId: idFirebaseReservado,
      );
      debugPrint(
        '[H1-TRACE] stage=after_batch_idempotent '
        'lojaId=$lojaEfetiva opId=$idFirebaseReservado '
        'baixaAplicada=${baixaOp.baixaAplicadaNestaExecucao}',
      );
      debugPrint(
        '[M39-ESTOQUE-VENDA] stage=firestore '
        'applied=${baixaOp.baixaAplicadaNestaExecucao} '
        'alreadyApplied=${baixaOp.baixaJaAplicadaAnteriormente} '
        'operationId=$idFirebaseReservado',
      );
      txResults = baixaOp.transactionResults;
      baixaEstoqueConcluida = true;
      baixaEstoqueAplicadaNestaExecucao = baixaOp.baixaAplicadaNestaExecucao;

      if (isCoordinatedPdv && saleIntentStatus == SaleIntentStatus.reserved) {
        saleIntentStatus = await _coordinatedSaleIntentAdvance(
          lojaId: lojaEfetiva,
          saleIntentId: coordinatedIntentId,
          operationId: idFirebaseReservado,
          current: saleIntentStatus,
          target: SaleIntentStatus.stockApplied,
        );
      }

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(
        lojaEfetiva,
        txResults,
      );

      for (final result in txResults) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaEfetiva,
          result: result,
        );
        debugPrint(
          '[M39-ESTOQUE-VENDA] stage=hive produtoId=${result.produtoId} '
          'qtdVendida=${result.quantidadeDebitada} '
          'qtdDepois=${result.quantidadeTotalAtualizada}',
        );
      }
      debugPrint('[M39-ESTOQUE-VENDA] stage=done vendaOp=$idFirebaseReservado');

      txResultsComboCap = await ComboKitStockService
          .aplicarTetoEstoqueComboAposBaixaSemAbortarVenda(
        lojaId: lojaEfetiva,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda:
            ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
      );

      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: lojaEfetiva,
        produtosBox: produtosBox,
        resultadosPrincipais: txResults,
        resultadosComboExtra: txResultsComboCap,
      );

      // 3.1) Histórico de movimentação – registra saída por item (não bloqueia)
      for (final result in txResults) {
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaEfetiva,
          produtoId: result.produtoId,
          produtoNome: result.produtoNome,
          tipo: 'saida',
          quantidade: result.quantidadeDebitada,
          motivo: 'Venda',
          usuario: vendedor,
        ).catchError((_) {});
      }
      for (final result in txResultsComboCap) {
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaEfetiva,
          produtoId: result.produtoId,
          produtoNome: result.produtoNome,
          tipo: 'saida',
          quantidade: result.quantidadeDebitada,
          motivo: 'Venda (ajuste kit combo)',
          usuario: vendedor,
        ).catchError((_) {});
      }

      // 4) subtotal / total
      subtotal = itens.fold<double>(
        0.0,
        (acc, it) => acc + (it.precoUnitario * it.quantidade),
      );
      total = subtotal * (1 - descontoPct / 100) + frete;

      // 5) custo de mercadoria (custo real) e taxa legado APK — separados; combo = só componentes
      final custoProdutos = VendaCustoMercadoria.somarCustoReal(
        itens: itensParaEstoque,
        produtos: produtosEncontrados,
        linhaContaCustoMercadoria: linhaContaCustoMercadoria,
      );
      VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
        itens: itensParaEstoque,
        produtos: produtosEncontrados,
        linhaContaCustoMercadoria: linhaContaCustoMercadoria,
        tinhaCustoUnitarioExplicitoAntesDoResolver: explicitExp,
      );
      VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
        itens: itens,
        produtos: produtosLinhaOriginal,
        linhaContaCustoMercadoria: List<bool>.filled(itens.length, true),
        tinhaCustoUnitarioExplicitoAntesDoResolver: explicitOrig,
      );
      final origensAtivas = <String?>[];
      for (var i = 0; i < itensParaEstoque.length; i++) {
        if (linhaContaCustoMercadoria[i]) {
          origensAtivas.add(itensParaEstoque[i].origemCustoItem);
        }
      }
      final origemCustoVenda = VendaCustoMercadoria.agregarOrigemCustoVenda(
        custoProdutos: custoProdutos,
        origensLinhasAtivas: origensAtivas,
      );
      final totalUnidades = VendaCustoMercadoria.unidadesMercadoria(
        itens: itensParaEstoque,
        linhaContaCustoMercadoria: linhaContaCustoMercadoria,
      );
      final taxas = VendaCustoMercadoria.taxasLegadoVendaApk(
        custoMercadoria: custoProdutos,
        unidadesMercadoria: totalUnidades,
      );

      // 6) se nenhum pagamento foi informado e não for fiado, joga tudo em dinheiro
      if (!isFiado && dinheiro == 0 && pix == 0 && cartao == 0) {
        dinheiro = total;
      }

      totalPagoAgora = dinheiro + pix + cartao;
      saldoFiado = isFiado
          ? calcularSaldoFiado(total: total, totalPagoAgora: totalPagoAgora)
          : 0.0;

      // 7) textos
      final linhas = itens.map((it) {
        final variacoes = <String>[];
        if (it.tamanho.isNotEmpty) variacoes.add('Tam: ${it.tamanho}');
        if (it.cor.isNotEmpty) variacoes.add('Cor: ${it.cor}');
        if (it.variacaoExtraResumo.isNotEmpty) {
          variacoes.add(it.variacaoExtraResumo);
        }
        final variacoesStr =
            variacoes.isNotEmpty ? ' (${variacoes.join(', ')})' : '';
        return "${it.quantidade} x ${it.produtoNome}$variacoesStr - R\$ ${_fmt2(it.precoUnitario)}";
      }).join('\n');

      final produtosDescricao = "$linhas\n"
          "Frete: R\$ ${_fmt2(frete)}\n"
          "Desconto: ${descontoPct.toStringAsFixed(0)}%\n"
          "Total: R\$ ${_fmt2(total)}";

      final vencStr = dataVencimentoFiado != null
          ? 'Vencimento: ${dataVencimentoFiado.day.toString().padLeft(2, '0')}/${dataVencimentoFiado.month.toString().padLeft(2, '0')}/${dataVencimentoFiado.year}'
          : '';
      final linhasPagamento = <String>[
        if (dinheiro > 0) "Pagamento Dinheiro: R\$ ${_fmt2(dinheiro)}",
        if (pix > 0) "Pagamento Pix: R\$ ${_fmt2(pix)}",
        if (cartao > 0) "Pagamento Cartão: R\$ ${_fmt2(cartao)}",
      ];
      if (isFiado && saldoFiado > 0.01) {
        var fiadoLinha = 'Fiado - R\$ ${_fmt2(saldoFiado)}. $vencStr';
        if (quantidadeParcelasFiado > 1) {
          fiadoLinha +=
              ' Parcelas fiado: $quantidadeParcelasFiado. Intervalo: $intervaloParcelasDias dias.';
        }
        linhasPagamento.add(fiadoLinha);
      } else if (isFiado && linhasPagamento.isEmpty) {
        linhasPagamento.add('Fiado - R\$ ${_fmt2(total)}. $vencStr');
      }
      formasPagamentoTexto = linhasPagamento.join('\n');

      // 8) cria venda (com todos os itens + clienteId estável)
      venda = Venda(
        clienteNome: cliente.nome,
        produtosDescricao: "$produtosDescricao\n$formasPagamentoTexto",
        quantidade: itens.length,
        preco: subtotal,
        total: total,
        formasPagamento: formasPagamentoTexto,
        data: DateTime.now(),
        tamanho: '',
        vendedor: vendedor,
        frete: frete,
        desconto: descontoPct,
        observacao: observacao.trim(),
        itens: itens,
        pagamentoDinheiro: dinheiro,
        pagamentoPix: pix,
        pagamentoCartao: cartao,
        taxas: taxas,
        custoProdutos: custoProdutos,
        descontoValor: subtotal * (descontoPct / 100),
        lojaId: lojaEfetiva,
        clienteId: cliente.key?.toString() ?? cliente.idFirebase,
        origemCusto: origemCustoVenda,
        itensComboSelecaoJson:
            VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
          itensComboSelecaoPorIndice,
        ),
        vendedorUid:
            (vendedorUid ?? '').trim().isEmpty ? null : vendedorUid!.trim(),
        vendedorNome:
            (vendedorNome ?? '').trim().isEmpty ? null : vendedorNome!.trim(),
        vendedorEmail: (vendedorEmail ?? '').trim().isEmpty
            ? null
            : vendedorEmail!.trim().toLowerCase(),
      );

      // Em edição: reutiliza idFirebase da venda antiga (evita duplicata no Firestore)
      _garantirIdFirebaseVendaAntesDeSalvar(
        venda: venda,
        idFirebaseToReuse: idFirebaseReservado,
      );

      debugPrint(
        '💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R\$ ${_fmt2(dinheiro)}, Pix: R\$ ${_fmt2(pix)}, Cartão: R\$ ${_fmt2(cartao)}, Total: R\$ ${_fmt2(total)}',
      );
      debugPrint(
        '📤 [SYNC-DEBUG] VendasService.salvarVenda → lojaId=$lojaEfetiva | cliente=${cliente.nome} | total=R\$ ${_fmt2(total)}',
      );

      await debugAfterRemoteStockAppliedBeforeHivePersist?.call();

      final vendaExistentePorOpId = _findVendaHivePorIdFirebase(
        vendasBox,
        idFirebaseReservado,
        lojaEfetiva,
      );
      if (vendaExistentePorOpId != null) {
        venda = vendaExistentePorOpId;
        addedKey = venda.key;
        if (isCoordinatedPdv &&
            saleIntentStatus == SaleIntentStatus.stockApplied &&
            !(isFiado && saldoFiado > 0.01)) {
          saleIntentStatus = await _coordinatedSaleIntentAdvance(
            lojaId: lojaEfetiva,
            saleIntentId: coordinatedIntentId,
            operationId: idFirebaseReservado,
            current: saleIntentStatus,
            target: SaleIntentStatus.salePersisted,
          );
        }
      } else {
        addedKey = debugVendasBoxAddOverride != null
            ? await debugVendasBoxAddOverride!(vendasBox, venda)
            : await vendasBox.add(venda);

        if (isCoordinatedPdv &&
            saleIntentStatus == SaleIntentStatus.stockApplied &&
            !(isFiado && saldoFiado > 0.01)) {
          saleIntentStatus = await _coordinatedSaleIntentAdvance(
            lojaId: lojaEfetiva,
            saleIntentId: coordinatedIntentId,
            operationId: idFirebaseReservado,
            current: saleIntentStatus,
            target: SaleIntentStatus.salePersisted,
          );
        }
      }

      await VendaOperationJournalService.complete(
        lojaId: lojaEfetiva,
        operationKey: operationKey,
      );
    } catch (e, st) {
      if (e is VendaOperationInterruptedException) {
        rethrow;
      }
      if (baixaEstoqueConcluida && baixaEstoqueAplicadaNestaExecucao) {
        Object? erroEstorno;
        try {
          await estornarBaixaPosFalhaAntesDePersistirVendaHive(
            lojaId: lojaEfetiva,
            produtosBox: produtosBox,
            vendaIdEstorno: idFirebaseReservado,
            txItems: txItems,
            txResultsComboCap: txResultsComboCap,
          );
        } catch (estE) {
          erroEstorno = estE;
          debugPrint('[VENDAS-SERVICE] Estorno pós-falha antes de Hive: $estE');
        }
        if (erroEstorno != null) {
          await VendaOperationJournalService.markCritical(
            lojaId: lojaEfetiva,
            operationKey: operationKey,
          );
          if (isCoordinatedPdv) {
            await _coordinatedSaleIntentCriticalBestEffort(
              lojaId: lojaEfetiva,
              saleIntentId: coordinatedIntentId,
              operationId: idFirebaseReservado,
            );
          }
          Error.throwWithStackTrace(
            VendaPersistenciaInconsistenciaCritica(
              erroPersistencia: e,
              erroEstorno: erroEstorno,
            ),
            st,
          );
        }
        await VendaOperationJournalService.revert(
          lojaId: lojaEfetiva,
          operationKey: operationKey,
        );
        if (isCoordinatedPdv) {
          await _coordinatedSaleIntentRevertBestEffort(
            lojaId: lojaEfetiva,
            saleIntentId: coordinatedIntentId,
            operationId: idFirebaseReservado,
          );
        }
      }
      rethrow;
    }
    try {
      await venda.save();
    } catch (_) {}
    final vendaHiveKey = resolverVendaHiveKeyAposAdd(
      vendasBox: vendasBox,
      venda: venda,
      addedKey: addedKey,
    );
    final vendaIdVinculo = idVendaEstavelParaVinculo(venda);

    final vIdSnapshot = vendaIdVinculo.isNotEmpty
        ? vendaIdVinculo
        : 'hive_${vendaHiveKey ?? venda.key}';
    final snapRaw = venda.itensComboSelecaoJson;
    final snapKeys =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
              snapRaw,
            )?.keys.toList() ??
            <int>[];
    final snapVazio = snapRaw == null || snapRaw.trim().isEmpty;
    debugPrint(
      '[COMBO-SNAPSHOT-SAVE] vendaId=$vIdSnapshot json_vazio=$snapVazio keys=$snapKeys',
    );

    // 8.1) se fiado com saldo, criar conta a receber (falha = rollback venda + estoque)
    if (isFiado && saldoFiado > 0.01) {
      final vencimento = dataVencimentoFiado;
      if (vencimento == null) {
        try {
          await devolverEstoqueParaVendaRemovida(
            venda: venda,
            produtosBox: produtosBox,
            lojaId: lojaEfetiva,
          );
        } catch (estE) {
          debugPrint(
            '⚠️ [VENDAS-SERVICE] Falha ao estornar estoque (fiado sem vencimento): $estE',
          );
        }
        await _excluirVendaHiveSeguro(vendasBox, venda, vendaHiveKey);
        throw ArgumentError('Informe a data de vencimento da venda fiada.');
      }
      if (!_podeVincularContaReceberAVenda(
        vendaHiveKey: vendaHiveKey,
        vendaIdEstavel: vendaIdVinculo,
      )) {
        try {
          await devolverEstoqueParaVendaRemovida(
            venda: venda,
            produtosBox: produtosBox,
            lojaId: lojaEfetiva,
          );
        } catch (estE) {
          debugPrint(
            '⚠️ [VENDAS-SERVICE] Falha ao estornar estoque (fiado sem chave Hive): $estE',
          );
        }
        await _excluirVendaHiveSeguro(vendasBox, venda, vendaHiveKey);
        debugPrint(
          '⚠️ [VENDAS-SERVICE] Fiado sem vínculo: addedKey=$addedKey venda.key=${venda.key} idFirebase=$vendaIdVinculo',
        );
        throw ArgumentError(
          'Não foi possível vincular a venda à conta a receber. Tente novamente.',
        );
      }
      try {
        _logContaReceberFiado(
          tag: 'CONTA_RECEBER_CREATE_START',
          lojaId: lojaEfetiva,
          clienteId: cliente.key?.toString() ?? cliente.idFirebase,
          clienteNome: cliente.nome,
          totalVenda: total,
          valorPago: totalPagoAgora,
          valorFiado: saldoFiado,
          formaPagamento: formasPagamentoTexto,
          parcelas: quantidadeParcelasFiado,
          vencimento: vencimento,
          vendaKey: vendaHiveKey,
          vendaIdFirebase: vendaIdVinculo,
        );
        final crBox = await ContaReceberService.openBoxLoja(lojaEfetiva);
        final qtdParcelas = safeInt(
          quantidadeParcelasFiado.clamp(1, 48),
          fallback: 1,
        );
        final intervalo = safeInt(
          intervaloParcelasDias.clamp(1, 120),
          fallback: 30,
        );
        final valoresParcelas = _parcelarValores(saldoFiado, qtdParcelas);
        final contasNovas = <ContaReceber>[];
        for (var i = 0; i < qtdParcelas; i++) {
          final venc = vencimento.add(Duration(days: i * intervalo));
          contasNovas.add(
            ContaReceber(
              lojaId: lojaEfetiva,
              clienteNome: cliente.nome,
              valor: valoresParcelas[i],
              valorOriginal: valoresParcelas[i],
              dataVencimento: venc,
              dataVenda: venda.data,
              vendaKey: _vendaKeyParaContaReceber(vendaHiveKey),
              vendaIdFirebase: _vendaIdFirebaseParaContaReceber(vendaIdVinculo),
              observacao: qtdParcelas > 1
                  ? 'Parcela ${i + 1}/$qtdParcelas${observacao.trim().isNotEmpty ? ' - ${observacao.trim()}' : ''}'
                  : (observacao.trim().isEmpty
                      ? 'Venda fiada'
                      : observacao.trim()),
              parcelaNumero: i + 1,
              parcelaTotal: qtdParcelas,
            ),
          );
        }
        await _persistirContasReceberNaBox(
          crBox: crBox,
          contas: contasNovas,
          lojaId: lojaEfetiva,
          vendaIdVinculo: vendaIdVinculo,
          vendaHiveKey: vendaHiveKey,
        );
        if (isCoordinatedPdv &&
            saleIntentStatus == SaleIntentStatus.stockApplied) {
          saleIntentStatus = await _coordinatedSaleIntentAdvance(
            lojaId: lojaEfetiva,
            saleIntentId: coordinatedIntentId,
            operationId: idFirebaseReservado,
            current: saleIntentStatus,
            target: SaleIntentStatus.salePersisted,
          );
        }
      } catch (e, st) {
        final detalheErro = _mensagemErroContaReceberSegura(e);
        _logContaReceberFiado(
          tag: 'VENDA_FIADA_CONTA_RECEBER_FAIL',
          lojaId: lojaEfetiva,
          clienteId: cliente.key?.toString() ?? cliente.idFirebase,
          clienteNome: cliente.nome,
          totalVenda: total,
          valorPago: totalPagoAgora,
          valorFiado: saldoFiado,
          formaPagamento: formasPagamentoTexto,
          parcelas: quantidadeParcelasFiado,
          vencimento: vencimento,
          vendaKey: vendaHiveKey,
          vendaIdFirebase: vendaIdVinculo,
          erro: e,
          stack: st,
        );
        debugPrint(
          '⚠️ [VENDAS-SERVICE] Erro ao criar conta a receber '
          '(type=${e.runtimeType}) detalhe=$detalheErro',
        );
        final msgUsuario = detalheErro.contains('conta a receber') ||
                detalheErro.contains('ContaReceber')
            ? detalheErro
            : 'Não foi possível gerar a conta a receber. $detalheErro';
        onSyncError?.call(msgUsuario);
        Object? erroEstorno;
        try {
          final forcar = debugForcarFalhaEstornoPosFiadoRollback;
          if (forcar != null) await forcar();
          await devolverEstoqueParaVendaRemovida(
            venda: venda,
            produtosBox: produtosBox,
            lojaId: lojaEfetiva,
          );
        } catch (estE) {
          erroEstorno = estE;
          debugPrint(
            '⚠️ [VENDAS-SERVICE] Falha ao estornar estoque após erro no fiado: $estE',
          );
        }
        if (erroEstorno != null) {
          if (isCoordinatedPdv) {
            await _coordinatedSaleIntentCriticalBestEffort(
              lojaId: lojaEfetiva,
              saleIntentId: coordinatedIntentId,
              operationId: idFirebaseReservado,
            );
          }
          Error.throwWithStackTrace(
            VendaPersistenciaInconsistenciaCritica(
              erroPersistencia: e,
              erroEstorno: erroEstorno,
            ),
            st,
          );
        }
        await _excluirVendaHiveSeguro(vendasBox, venda, vendaHiveKey);
        if (isCoordinatedPdv) {
          await _coordinatedSaleIntentRevertBestEffort(
            lojaId: lojaEfetiva,
            saleIntentId: coordinatedIntentId,
            operationId: idFirebaseReservado,
          );
        }
        if (VendaComboEstoqueExpansion.isErroVariacaoObrigatoria(e)) {
          rethrow;
        }
        if (e is ArgumentError) {
          final msg = e.message?.toString().trim() ?? '';
          if (msg.contains('vincular a venda à conta a receber') ||
              msg.contains('vencimento')) {
            rethrow;
          }
        }
        throw ArgumentError(msgUsuario);
      }
    }

    await debugAfterHiveSalePersistedBeforeSaleIntentComplete?.call();

    // R4.2 — checkpoint UI após Hive+Journal(+fiado); sync/campanha seguem depois.
    final fiadoAtivo = isFiado && saldoFiado > 0.01;
    final salePersistedOrSkipped = !isCoordinatedPdv ||
        saleIntentStatus == SaleIntentStatus.salePersisted ||
        saleIntentStatus == SaleIntentStatus.completed;
    if (onLocalPersistUiReady != null &&
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: fiadoAtivo,
          fiadoReceivableReady: true,
          saleIntentPersistedOrSkipped: salePersistedOrSkipped,
        )) {
      try {
        debugPrint('[M39-VENDA-PERF] stage=ui_release');
        onLocalPersistUiReady();
      } catch (e) {
        debugPrint('[VENDAS-SERVICE] onLocalPersistUiReady falhou: $e');
      }
    }

    if (isCoordinatedPdv &&
        saleIntentStatus == SaleIntentStatus.salePersisted) {
      try {
        saleIntentStatus = await _coordinatedSaleIntentAdvance(
          lojaId: lojaEfetiva,
          saleIntentId: coordinatedIntentId,
          operationId: idFirebaseReservado,
          current: saleIntentStatus,
          target: SaleIntentStatus.completed,
        );
      } catch (e) {
        debugPrint(
          '[VENDAS-SERVICE] sale intent complete best-effort falhou: $e',
        );
      }
    }

    // 9) histórico do cliente (não aborta venda se HiveList falhar no web)
    _adicionarVendaHistoricoClienteSeguro(
      cliente: cliente,
      venda: venda,
      vendasBox: vendasBox,
      lojaId: lojaEfetiva,
    );

    // 9.1) sincroniza cliente com Firestore
    try {
      await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaEfetiva);
    } catch (e) {
      debugPrint(
        '⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})',
      );
      onSyncError?.call('Cliente não sincronizado. Verifique a conexão.');
    }

    // 10) sincroniza venda com Firestore
    try {
      final ok = await VendasFirestoreService.syncVenda(
        venda,
        lojaId: lojaEfetiva,
      );
      if (!ok) {
        debugPrint(
          '⚠️ [VENDAS-SERVICE] Venda não sincronizada com Firestore (lojaId=$lojaEfetiva, key=${venda.key})',
        );
        onSyncError?.call(
          'Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.',
        );
      } else if (isFiado && saldoFiado > 0.01) {
        try {
          final rep = await ContaReceberVendaBackfillService
              .republicarContasVinculadasAVenda(
            lojaId: lojaEfetiva,
            venda: venda,
          );
          if (rep > 0) {
            debugPrint(
              '[VENDAS-SERVICE] contas_receber republicadas pós-sync qtd=$rep vendaId=$vendaIdVinculo',
            );
          }
        } catch (e) {
          debugPrint(
            '⚠️ [VENDAS-SERVICE] Falha ao republicar contas fiado (type=${e.runtimeType})',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ Erro inesperado ao sincronizar venda com Firestore (type=${e.runtimeType})',
      );
      onSyncError?.call(
        'Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.',
      );
    }

    // 11) 🎯 Registra participação em campanhas de sorteio (CENTRALIZADO)
    try {
      final resultado = await CampaignEngineService.onVendaConcluida(
        lojaId: lojaEfetiva,
        venda: venda,
        vendaId: venda.key?.toString(),
        clienteNome: cliente.nome,
        clienteId: cliente.key?.toString(),
        telefone: cliente.telefone, // 🔥 Adicionado para WhatsApp
        email: cliente.email, // 🔥 Adicionado para Email
        valorTotal: total,
        origem: 'manual',
        nomeLoja: lojaEfetiva,
      );

      if (resultado.sucesso) {
        debugPrint(
          '🎫 [VENDA-MANUAL] Número da sorte gerado: ${resultado.numero}',
        );
        onNumeroSorteGerado?.call(resultado.numero);
      } else if (resultado.erro != null) {
        debugPrint('ℹ️ [VENDA-MANUAL] Campanha: ${resultado.erro}');
      }
    } catch (e) {
      debugPrint('⚠️ [VENDA-MANUAL] Campanha/sorteio: ${e.runtimeType}');
    }

    return venda;
  }

  // ---------------------------
  // Editar venda (delta de estoque)
  // ---------------------------

  /// Atualiza venda existente aplicando delta de estoque só quando itens mudam.
  static Future<Venda> editarVendaMulti({
    required Venda vendaOriginal,
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required List<VendaItem> itens,
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String? vendedorUid,
    String? vendedorNome,
    String? vendedorEmail,
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId,
    Cliente? clienteExistente,
    void Function(String message)? onSyncError,
    bool isFiado = false,
    DateTime? dataVencimentoFiado,
    int quantidadeParcelasFiado = 1,
    int intervaloParcelasDias = 30,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
    DateTime? dataVenda,
  }) async {
    if (itens.isEmpty) {
      throw Exception('Nenhum item informado.');
    }

    if (lojaId == null || lojaId.trim().isEmpty) {
      throw ArgumentError('lojaId é obrigatório para editar venda multi-loja');
    }
    final String lojaEfetiva = lojaId.trim();

    final subtotalPreview = itens.fold<double>(
      0.0,
      (acc, it) => acc + (it.precoUnitario * it.quantidade),
    );
    final totalPreview = subtotalPreview * (1 - descontoPct / 100) + frete;

    validarParametrosVendaFiada(
      isFiado: isFiado,
      dataVencimentoFiado: dataVencimentoFiado,
      clienteNome: clienteExistente?.nome ?? clienteNome,
      total: totalPreview,
      quantidadeParcelasFiado: quantidadeParcelasFiado,
      totalPagoAgora: dinheiro + pix + cartao,
    );

    await validarEdicaoNaoReduzAbaixoValorRecebido(
      vendaOriginal: vendaOriginal,
      novoTotal: totalPreview,
      lojaId: lojaEfetiva,
    );

    final saldoFiadoPreview = _saldoFiadoPreviewEdicao(
      isFiado: isFiado,
      totalPreview: totalPreview,
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
    );
    await _validarRemocaoContasReceberAntesDeMutarVenda(
      vendaOriginal: vendaOriginal,
      lojaId: lojaEfetiva,
      isFiado: isFiado,
      saldoFiado: saldoFiadoPreview,
    );

    final comboJsonNovo =
        VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
      itensComboSelecaoPorIndice,
    );
    final itensAntigos = vendaOriginal.itens ?? <VendaItem>[];
    final itensEquivalentes = VendaEdicaoEstoqueDiff.itensVendaEquivalentes(
      antigos: itensAntigos,
      novos: itens,
      comboJsonAntigo: vendaOriginal.itensComboSelecaoJson,
      comboJsonNovo: comboJsonNovo,
    );

    final vendaId = (vendaOriginal.idFirebase ?? '').trim().isNotEmpty
        ? vendaOriginal.idFirebase!.trim()
        : 'hive_${vendaOriginal.key}';

    String? editStockJournalKey;

    if (!itensEquivalentes) {
      final linhasAntigas = montarLinhasEstoqueCanonicasParaEdicao(
        itens: itensAntigos,
        produtosBox: produtosBox,
        lojaId: lojaEfetiva,
        itensComboSelecaoJson: vendaOriginal.itensComboSelecaoJson,
      );
      final linhasNovas = montarLinhasEstoqueCanonicasParaEdicao(
        itens: itens,
        produtosBox: produtosBox,
        lojaId: lojaEfetiva,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
        itensComboSelecaoJson: comboJsonNovo,
      );

      final (
        itensParaEstoque,
        produtosEncontrados,
        _,
      ) = VendaComboEstoqueExpansion.expandirCombos(
        itens: itens,
        produtosBox: produtosBox,
        lojaId: lojaEfetiva,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
      );
      VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
        itensParaEstoque: itensParaEstoque,
        produtosEncontrados: produtosEncontrados,
      );

      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: linhasAntigas,
        linhasNovas: linhasNovas,
      );

      if (!delta.semMovimento) {
        final produtosDasLinhas = <Produto>[];
        for (final item in itens) {
          final p = encontrarProdutoNoEstoque(
            produtosBox: produtosBox,
            productId: item.productId,
            nome: item.produtoNome,
            lojaId: lojaEfetiva,
          );
          if (p != null) produtosDasLinhas.add(p);
        }
        if (produtosDasLinhas.isNotEmpty) {
          await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
            lojaId: lojaEfetiva,
            produtos: produtosDasLinhas,
          );
        }
        editStockJournalKey = await _aplicarDeltaEstoqueEdicaoVenda(
          lojaId: lojaEfetiva,
          produtosBox: produtosBox,
          delta: delta,
          vendedor: vendedor,
          vendaIdLog: vendaId,
        );
      }
    } else {
      debugPrint(
        '[VENDA-EDICAO] itens_equivalentes sem_movimento_estoque vendaId=$vendaId',
      );
    }

    final cliente = _getOrCreateCliente(
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: clienteNome,
      lojaId: lojaEfetiva,
      clienteExistente: clienteExistente,
    );

    final (
      itensParaCusto,
      produtosEncCusto,
      linhaContaCustoMercadoria,
    ) = VendaComboEstoqueExpansion.expandirCombos(
      itens: itens,
      produtosBox: produtosBox,
      lojaId: lojaEfetiva,
      itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
    );

    final explicitExp = List<bool>.generate(
      itensParaCusto.length,
      (i) => itensParaCusto[i].custoUnitario != null,
    );
    for (var i = 0; i < itensParaCusto.length; i++) {
      itensParaCusto[i].custoUnitario = _resolverCustoItem(
        produtosEncCusto[i],
        itensParaCusto[i],
      );
    }

    final explicitOrig = List<bool>.generate(
      itens.length,
      (i) => itens[i].custoUnitario != null,
    );
    final produtosLinhaOriginal = <Produto>[];
    for (var k = 0; k < itens.length; k++) {
      final itemOriginal = itens[k];
      final pLocal = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: itemOriginal.productId,
        nome: itemOriginal.produtoNome,
        lojaId: lojaEfetiva,
      );
      produtosLinhaOriginal.add(pLocal ?? Produto.vazio());
      if (pLocal != null) {
        itemOriginal.custoUnitario = _resolverCustoItem(pLocal, itemOriginal);
      }
    }

    final subtotal = itens.fold<double>(
      0.0,
      (acc, it) => acc + (it.precoUnitario * it.quantidade),
    );
    final total = subtotal * (1 - descontoPct / 100) + frete;
    final totalAnterior = vendaOriginal.total;

    if (!isFiado && dinheiro == 0 && pix == 0 && cartao == 0) {
      dinheiro = total;
    }

    final totalPagoAgora = dinheiro + pix + cartao;
    final saldoFiado = isFiado
        ? calcularSaldoFiado(total: total, totalPagoAgora: totalPagoAgora)
        : 0.0;

    final linhas = itens.map((it) {
      final variacoes = <String>[];
      if (it.tamanho.isNotEmpty) variacoes.add('Tam: ${it.tamanho}');
      if (it.cor.isNotEmpty) variacoes.add('Cor: ${it.cor}');
      if (it.variacaoExtraResumo.isNotEmpty) {
        variacoes.add(it.variacaoExtraResumo);
      }
      final variacoesStr =
          variacoes.isNotEmpty ? ' (${variacoes.join(', ')})' : '';
      return "${it.quantidade} x ${it.produtoNome}$variacoesStr - R\$ ${_fmt2(it.precoUnitario)}";
    }).join('\n');

    final produtosDescricao = "$linhas\n"
        "Frete: R\$ ${_fmt2(frete)}\n"
        "Desconto: ${descontoPct.toStringAsFixed(0)}%\n"
        "Total: R\$ ${_fmt2(total)}";

    final vencStr = dataVencimentoFiado != null
        ? 'Vencimento: ${dataVencimentoFiado.day.toString().padLeft(2, '0')}/${dataVencimentoFiado.month.toString().padLeft(2, '0')}/${dataVencimentoFiado.year}'
        : '';
    final linhasPagamento = <String>[
      if (dinheiro > 0) "Pagamento Dinheiro: R\$ ${_fmt2(dinheiro)}",
      if (pix > 0) "Pagamento Pix: R\$ ${_fmt2(pix)}",
      if (cartao > 0) "Pagamento Cartão: R\$ ${_fmt2(cartao)}",
    ];
    if (isFiado && saldoFiado > 0.01) {
      var fiadoLinha = 'Fiado - R\$ ${_fmt2(saldoFiado)}. $vencStr';
      if (quantidadeParcelasFiado > 1) {
        fiadoLinha +=
            ' Parcelas fiado: $quantidadeParcelasFiado. Intervalo: $intervaloParcelasDias dias.';
      }
      linhasPagamento.add(fiadoLinha);
    } else if (isFiado && linhasPagamento.isEmpty) {
      linhasPagamento.add('Fiado - R\$ ${_fmt2(total)}. $vencStr');
    }
    final formasPagamentoTexto = linhasPagamento.join('\n');

    final custoProdutos = VendaCustoMercadoria.somarCustoReal(
      itens: itensParaCusto,
      produtos: produtosEncCusto,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
    );
    VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
      itens: itensParaCusto,
      produtos: produtosEncCusto,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
      tinhaCustoUnitarioExplicitoAntesDoResolver: explicitExp,
    );
    VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
      itens: itens,
      produtos: produtosLinhaOriginal,
      linhaContaCustoMercadoria: List<bool>.filled(itens.length, true),
      tinhaCustoUnitarioExplicitoAntesDoResolver: explicitOrig,
    );
    final origensAtivas = <String?>[];
    for (var i = 0; i < itensParaCusto.length; i++) {
      if (linhaContaCustoMercadoria[i]) {
        origensAtivas.add(itensParaCusto[i].origemCustoItem);
      }
    }
    final origemCustoVenda = VendaCustoMercadoria.agregarOrigemCustoVenda(
      custoProdutos: custoProdutos,
      origensLinhasAtivas: origensAtivas,
    );
    final totalUnidades = VendaCustoMercadoria.unidadesMercadoria(
      itens: itensParaCusto,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
    );
    final taxas = VendaCustoMercadoria.taxasLegadoVendaApk(
      custoMercadoria: custoProdutos,
      unidadesMercadoria: totalUnidades,
    );

    final venda = vendaOriginal;
    venda.clienteNome = cliente.nome;
    venda.produtosDescricao = "$produtosDescricao\n$formasPagamentoTexto";
    venda.quantidade = itens.length;
    venda.preco = subtotal;
    venda.total = total;
    venda.formasPagamento = formasPagamentoTexto;
    venda.data = dataVenda ?? venda.data;
    venda.tamanho = '';
    venda.vendedor = vendedor;
    if (vendedorUid != null && vendedorUid.trim().isNotEmpty) {
      venda.vendedorUid = vendedorUid.trim();
    }
    if (vendedorNome != null && vendedorNome.trim().isNotEmpty) {
      venda.vendedorNome = vendedorNome.trim();
    }
    if (vendedorEmail != null && vendedorEmail.trim().isNotEmpty) {
      venda.vendedorEmail = vendedorEmail.trim().toLowerCase();
    }
    venda.frete = frete;
    venda.desconto = descontoPct;
    venda.observacao = observacao.trim();
    venda.itens = itens;
    venda.pagamentoDinheiro = dinheiro;
    venda.pagamentoPix = pix;
    venda.pagamentoCartao = cartao;
    venda.taxas = taxas;
    venda.custoProdutos = custoProdutos;
    venda.descontoValor = subtotal * (descontoPct / 100);
    venda.lojaId = lojaEfetiva;
    venda.clienteId = cliente.key?.toString() ?? cliente.idFirebase;
    venda.origemCusto = origemCustoVenda;
    venda.itensComboSelecaoJson = comboJsonNovo;

    await venda.save();

    if (editStockJournalKey != null) {
      await VendaOperationJournalService.complete(
        lojaId: lojaEfetiva,
        operationKey: editStockJournalKey,
      );
    }

    VendaSalvaComPendenciaSyncException? pendenciaCrRemota;
    try {
      await _atualizarContasReceberAposEdicaoVenda(
        venda: venda,
        lojaId: lojaEfetiva,
        isFiado: isFiado,
        saldoFiado: saldoFiado,
        dataVencimentoFiado: dataVencimentoFiado,
        quantidadeParcelasFiado: quantidadeParcelasFiado,
        intervaloParcelasDias: intervaloParcelasDias,
        observacao: observacao,
        clienteNome: cliente.nome,
        itensEquivalentes: itensEquivalentes,
        totalAnterior: totalAnterior,
      );
    } on VendaSalvaComPendenciaSyncException catch (e) {
      // LOCAL_SALE + LOCAL_CR já commitados — remotes best-effort; propaga aviso.
      pendenciaCrRemota = e;
    }

    // Local sale+CR OK: remotes não fazem parte da fronteira de sucesso da UI.
    _agendarSyncRemotoAposEdicaoLocal(
      cliente: cliente,
      venda: venda,
      lojaEfetiva: lojaEfetiva,
      isFiado: isFiado,
      saldoFiado: saldoFiado,
      onSyncError: onSyncError,
    );

    if (pendenciaCrRemota != null) {
      throw pendenciaCrRemota;
    }

    return venda;
  }

  // ---------------------------
  // Desfazer venda
  // ---------------------------

  static Future<void> desfazerVenda({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required Venda venda,
  }) async {
    // Evitar fallback 'default': usar loja da venda ou do nome da box (vendas_lojaId).
    String lojaId = (venda.lojaId ?? '').trim().isNotEmpty
        ? venda.lojaId!.trim()
        : (vendasBox.name.startsWith('vendas_')
            ? vendasBox.name.substring(7)
            : '');
    if (lojaId.isEmpty) {
      return; // Não desfazer sem loja definida (evita operar na loja errada).
    }

    // devolve estoque (transacional, idempotente)
    final vendaIdMarcador =
        EstoqueTransactionService.vendaIdMarcadorCatalogoFromKey(venda.key);
    final marcador = vendaIdMarcador != null
        ? await EstoqueTransactionService.lerMarcadorBaixaPagamento(
            lojaId,
            vendaIdMarcador,
          )
        : EstoqueBaixaPagamentoMarcador.ausente;
    final skipEstornoCatalogo = (marcador.existe &&
            (marcador.estornoAplicado || !marcador.baixaAplicada)) ||
        (_vendaOrigemCatalogo(venda) && !marcador.existe);
    if (marcador.existe && marcador.estornoAplicado) {
      debugPrint(
        '[DESFAZER-VENDA] estorno_ja_aplicado_remoto vendaIdMarcador=$vendaIdMarcador',
      );
    } else if (marcador.existe && !marcador.baixaAplicada) {
      debugPrint(
        '[DESFAZER-VENDA] sem_baixa_catalogo skip estorno vendaIdMarcador=$vendaIdMarcador',
      );
    }

    var devolucaoResults = <EstoqueTransactionResult>[];
    if (!skipEstornoCatalogo) {
      final vendaIdFallback = (venda.idFirebase ?? '').trim().isNotEmpty
          ? venda.idFirebase!.trim()
          : 'hive_${venda.key}';
      final vendaId =
          await EstoqueTransactionService.resolverVendaIdIdempotenciaDevolucao(
        lojaId: lojaId,
        vendaIdMarcadorCatalogo: vendaIdMarcador,
        vendaIdFallback: vendaIdFallback,
      );
      final itensDevolucao = _resolverItensDevolucaoParaVenda(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaIdLog: vendaId,
      );
      if (itensDevolucao.isNotEmpty) {
        try {
          final results = await _devolverEstoqueComLogsCombo(
            lojaId: lojaId,
            vendaId: vendaId,
            itens: itensDevolucao,
            estornoOrigemCatalogo: 'desfazer_venda',
          );
          devolucaoResults = results;
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
          if (results.isNotEmpty) {
            debugPrint(
              '✅ Estoque devolvido (transacional): ${results.length} itens',
            );
          }
        } catch (e, st) {
          debugPrint(
            '[DESFAZER-VENDA] Falha na devolução de estoque — venda NÃO removida (Firestore/Hive intactos). Erro: $e',
          );
          Error.throwWithStackTrace(e, st);
        }
      } else if (venda.itens != null && venda.itens!.isNotEmpty) {
        throw StateError(
          'Não foi possível devolver o estoque desta venda. '
          'Verifique se os produtos ainda existem no cadastro.',
        );
      }
    }

    final vendaIdLog = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    var pisoResults = <EstoqueTransactionResult>[];
    try {
      pisoResults =
          await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );
      for (final r in pisoResults) {
        final q = r.quantidadeDebitada.abs();
        if (q <= 0) continue;
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'entrada',
          quantidade: q,
          motivo: 'Devolução (ajuste kit combo)',
          usuario: 'App',
          vendaId: vendaIdLog,
        ).catchError((_) {});
      }
    } catch (e) {
      debugPrint(
        '⚠️ [COMBO_PISO] Falha ao sincronizar estoque do combo após devolução: $e',
      );
    }

    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lojaId,
      produtosBox: produtosBox,
      resultadosPrincipais: devolucaoResults,
      resultadosComboExtra: pisoResults,
    );

    final vkContas = hiveKeyOrNull(venda.key);
    await removerContasReceberVinculadasAVenda(
      lojaId: lojaId,
      vendaKey: vkContas,
      vendaIdFirebase: idVendaEstavelParaVinculo(venda),
    );

    // remove do histórico (apenas se cliente existir na box - evita erro em vendas catálogo sem cliente)
    final Cliente? cliente = clientesBox.values.firstWhereOrNull(
      (c) => c.lojaId == venda.lojaId && c.nome == venda.clienteNome,
    );

    if (cliente != null && cliente.historico != null) {
      cliente.historico!.removeWhere(
        (h) => identical(h, venda) || h.key == venda.key,
      );
      await cliente.save();

      // ✅ SINCRONIZAR cliente atualizado com Firestore
      try {
        await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
      } catch (e) {
        debugPrint(
          '⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})',
        );
      }
    }

    // ✅ DELETAR do Firestore (estoque_vendas) para não voltar na sync
    try {
      if (venda.idFirebase != null && venda.idFirebase!.isNotEmpty) {
        await VendasFirestoreService.deleteVenda(
          venda.idFirebase!,
          lojaId: lojaId,
        );
        debugPrint('✅ Venda deletada do Firestore: ${venda.idFirebase}');
      } else {
        debugPrint('⚠️ Venda sem idFirebase, não pode deletar do Firestore');
      }
    } catch (e) {
      debugPrint(
        '⚠️ Erro ao deletar venda do Firestore (type=${e.runtimeType})',
      );
    }

    // Deletar do Hive (local)
    await venda.delete();
  }

  /// Devolve estoque ao remover venda (soft delete imediato ou exclusão permanente).
  /// Idempotente por vendaId em [EstoqueTransactionService.devolverEstoqueTransactionBatch].
  static Future<void> devolverEstoqueParaVendaRemovida({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
    String estornoOrigem = 'venda_delete',
    int? vendaHiveKeyMarcador,
  }) async {
    final vendaIdMarcador = vendaHiveKeyMarcador != null &&
            vendaHiveKeyMarcador >= 0
        ? vendaHiveKeyMarcador.toString()
        : EstoqueTransactionService.vendaIdMarcadorCatalogoFromKey(venda.key);
    final marcador = vendaIdMarcador != null
        ? await EstoqueTransactionService.lerMarcadorBaixaPagamento(
            lojaId,
            vendaIdMarcador,
          )
        : EstoqueBaixaPagamentoMarcador.ausente;

    if (marcador.existe && marcador.estornoAplicado) {
      debugPrint(
        '[VENDA_DELETE] estorno_ja_aplicado_remoto vendaIdMarcador=$vendaIdMarcador',
      );
      return;
    }
    if (marcador.existe && !marcador.baixaAplicada) {
      debugPrint(
        '[VENDA_DELETE] sem_baixa_catalogo skip estorno vendaIdMarcador=$vendaIdMarcador',
      );
      return;
    }
    if (_vendaOrigemCatalogo(venda) && !marcador.existe) {
      debugPrint(
        '[VENDA_DELETE] catalogo_sem_marcador skip estorno hiveKey=$vendaIdMarcador',
      );
      return;
    }

    final vendaIdFallback = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    final vendaId =
        await EstoqueTransactionService.resolverVendaIdIdempotenciaDevolucao(
      lojaId: lojaId,
      vendaIdMarcadorCatalogo: vendaIdMarcador,
      vendaIdFallback: vendaIdFallback,
    );
    debugPrint(
      '[VENDA_DELETE] devolucao_estoque_inicio vendaId=$vendaId '
      'marcador=$vendaIdMarcador baixa=${marcador.baixaAplicada}',
    );

    var devolucaoResultsExclusao = <EstoqueTransactionResult>[];
    final itensDevolucaoExclusao = _resolverItensDevolucaoParaVenda(
      venda: venda,
      produtosBox: produtosBox,
      lojaId: lojaId,
      vendaIdLog: vendaId,
    );
    if (itensDevolucaoExclusao.isNotEmpty) {
      try {
        final results = await _devolverEstoqueComLogsCombo(
          lojaId: lojaId,
          vendaId: vendaId,
          itens: itensDevolucaoExclusao,
          estornoOrigemCatalogo: estornoOrigem,
        );
        devolucaoResultsExclusao = results;
        for (final r in results) {
          await EstoqueTransactionService.atualizarHiveAposTransacao(
            produtosBox: produtosBox,
            lojaId: lojaId,
            result: r,
          );
        }
      } catch (e, st) {
        debugPrint(
          '[VENDA_DELETE] devolucao_estoque_falhou vendaId=$vendaId erro=$e',
        );
        debugPrint('[VENDA_DELETE] exclusao_abortada_por_estoque (lote itens)');
        Error.throwWithStackTrace(e, st);
      }
    } else if (venda.itens != null && venda.itens!.isNotEmpty) {
      debugPrint(
        '[VENDA_DELETE] exclusao_abortada_por_estoque (sem itens resolvidos) vendaId=$vendaId',
      );
      throw StateError(
        'Não foi possível devolver o estoque desta venda. '
        'Verifique se os produtos ainda existem no cadastro.',
      );
    }

    var pisoResultsExclusao = <EstoqueTransactionResult>[];
    try {
      pisoResultsExclusao =
          await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );
      for (final r in pisoResultsExclusao) {
        final q = r.quantidadeDebitada.abs();
        if (q <= 0) continue;
        await MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'entrada',
          quantidade: q,
          motivo: 'Devolução (ajuste kit combo)',
          usuario: 'App',
          vendaId: vendaId,
        );
      }
    } catch (e, st) {
      debugPrint(
        '[VENDA_DELETE] devolucao_estoque_falhou vendaId=$vendaId (piso combo / mov.) erro=$e',
      );
      debugPrint('[VENDA_DELETE] exclusao_abortada_por_estoque');
      Error.throwWithStackTrace(e, st);
    }

    try {
      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: lojaId,
        produtosBox: produtosBox,
        resultadosPrincipais: devolucaoResultsExclusao,
        resultadosComboExtra: pisoResultsExclusao,
      );
    } catch (e, st) {
      debugPrint(
        '[VENDA_DELETE] catalogo_pos_estoque_falhou vendaId=$vendaId erro=$e — exclusao_abortada',
      );
      Error.throwWithStackTrace(e, st);
    }

    debugPrint('[VENDA_DELETE] devolucao_estoque_sucesso vendaId=$vendaId');
    await EstoqueTransactionService.marcarDevolucaoLocalEmTodosIds(lojaId, [
      vendaId,
      if ((vendaIdMarcador ?? '').trim().isNotEmpty) vendaIdMarcador!,
      if ((venda.idFirebase ?? '').trim().isNotEmpty) venda.idFirebase!.trim(),
      if (vendaHiveKeyMarcador != null && vendaHiveKeyMarcador >= 0)
        'hive_$vendaHiveKeyMarcador',
    ]);
  }

  /// Reaplica baixa de estoque após desfazer exclusão (devolução já tinha sido feita no soft delete).
  static Future<void> reaplicarBaixaEstoquePosUndoExclusaoVenda({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    if (venda.itens == null || venda.itens!.isEmpty) {
      debugPrint(
        '[VENDA_UNDO] Sem itens estruturados; não reaplica baixa automática',
      );
      return;
    }
    final selecaoUndo =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
      venda.itensComboSelecaoJson,
    );
    if (selecaoUndo != null) {
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=${(venda.idFirebase ?? '').trim().isNotEmpty ? venda.idFirebase! : 'hive_${venda.key}'} undo_baixa fonte=itensComboSelecaoJson',
      );
    }
    final (
      itensParaBaixa,
      produtosEnc,
      linhaFlags,
    ) = VendaComboEstoqueExpansion.expandirCombos(
      itens: venda.itens!,
      produtosBox: produtosBox,
      lojaId: lid,
      itensComboSelecaoPorIndice: selecaoUndo,
    );
    final itensS = <VendaItem>[];
    final prodS = <Produto>[];
    for (var i = 0; i < itensParaBaixa.length; i++) {
      if (i >= linhaFlags.length || i >= produtosEnc.length) break;
      if (!linhaFlags[i]) continue;
      if (produtosEnc[i].ehCombo) continue;
      itensS.add(itensParaBaixa[i]);
      prodS.add(produtosEnc[i]);
    }
    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensS,
      produtosEncontrados: prodS,
    );
    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensS,
      produtosEncontrados: prodS,
    );
    if (txItems.isEmpty) return;

    final txResults =
        await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lid,
      itens: txItems,
    );
    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(
      lid,
      txResults,
    );
    for (final result in txResults) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lid,
        result: result,
      );
    }
    final txCap = await ComboKitStockService
        .aplicarTetoEstoqueComboAposBaixaSemAbortarVenda(
      lojaId: lid,
      produtosBox: produtosBox,
      produtoIdsDebitadosNaVenda:
          ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
    );
    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lid,
      produtosBox: produtosBox,
      resultadosPrincipais: txResults,
      resultadosComboExtra: txCap,
    );
  }

  /// Executa limpeza remota após a janela de undo do soft delete.
  /// A devolução de estoque já ocorre em [SoftDeleteService.scheduleVendaDelete].
  /// [estoqueJaEstornadoNoSchedule] evita 2º estorno; fallback só se o schedule não estornou.
  static Future<void> executarExclusaoPermanente({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
    int? vendaHiveKeyOriginal,
    bool estoqueJaEstornadoNoSchedule = false,
  }) async {
    final marcadorId = vendaHiveKeyOriginal != null && vendaHiveKeyOriginal >= 0
        ? vendaHiveKeyOriginal.toString()
        : EstoqueTransactionService.vendaIdMarcadorCatalogoFromKey(venda.key);
    final idFb = (venda.idFirebase ?? '').trim();
    final candidatos = <String>[
      if ((marcadorId ?? '').trim().isNotEmpty) marcadorId!.trim(),
      if (idFb.isNotEmpty) idFb,
      if (vendaHiveKeyOriginal != null && vendaHiveKeyOriginal >= 0)
        'hive_$vendaHiveKeyOriginal',
    ];

    final jaEstornado = estoqueJaEstornadoNoSchedule ||
        await EstoqueTransactionService.devolucaoVendaJaAplicadaEmQualquerId(
          lojaId,
          candidatos,
        );

    if (jaEstornado) {
      debugPrint(
        '[VENDA_DELETE] permanent_skip_estorno '
        'scheduleFlag=$estoqueJaEstornadoNoSchedule ids=$candidatos',
      );
    } else {
      debugPrint('[VENDA_DELETE] permanent_estorno_fallback ids=$candidatos');
      await devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyMarcador: vendaHiveKeyOriginal,
      );
    }

    if (venda.idFirebase != null && venda.idFirebase!.isNotEmpty) {
      await VendasFirestoreService.deleteVenda(
        venda.idFirebase!,
        lojaId: lojaId,
      );
    }
  }
}
