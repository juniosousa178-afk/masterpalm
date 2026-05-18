// lib/services/vendas_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import '../core/venda_origem_custo.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../core/mp_venda_identity.dart';
import '../core/venda_metrics_filter.dart';
import 'store_resolver_facade.dart';
import 'sync_queue_service.dart';

/// Serviço para sincronizar vendas com Firestore
class VendasFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Monta [Venda] a partir de um mapa Firestore (retrocompatível com campos ausentes).
  static Venda vendaFromFirestoreMap(
    Map<String, dynamic> data,
    String docId,
    String lojaId,
  ) {
    final itensRaw = data['itens'] as List? ?? [];
    final itens = itensRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final pid = m['productId'] as String?;
      return VendaItem(
        produtoNome: m['produtoNome'] as String? ?? '',
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0.0,
        tamanho: m['tamanho'] as String? ?? '',
        cor: m['cor'] as String? ?? '',
        productId: pid != null && pid.trim().isNotEmpty ? pid : null,
        variacaoExtraResumo: (m['variacaoExtraResumo'] ?? '').toString().trim(),
        extraValor: (m['extraValor'] ?? '').toString().trim(),
        custoUnitario: (m['custoUnitario'] as num?)?.toDouble(),
        origemCustoItem: VendaOrigemCusto.normalizarOuNull(
          (m['origemCustoItem'] as String?)?.trim(),
        ),
      );
    }).toList();

    return Venda(
      clienteNome: data['clienteNome'] ?? '',
      produtosDescricao: data['produtosDescricao'] ?? '',
      quantidade: (data['quantidade'] as num?)?.toInt() ?? itens.length,
      preco: (data['preco'] as num?)?.toDouble() ?? 0.0,
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      formasPagamento: data['formasPagamento'] ?? '',
      data: (data['data'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      tamanho: data['tamanho'] ?? '',
      vendedor: data['vendedor'] ?? '',
      frete: (data['frete'] as num?)?.toDouble() ?? 0.0,
      desconto: (data['desconto'] as num?)?.toDouble() ?? 0.0,
      observacao: data['observacao'] ?? '',
      itens: itens.isNotEmpty ? itens : null,
      pagamentoDinheiro: (data['pagamentoDinheiro'] as num?)?.toDouble() ?? 0.0,
      pagamentoPix: (data['pagamentoPix'] as num?)?.toDouble() ?? 0.0,
      pagamentoCartao: (data['pagamentoCartao'] as num?)?.toDouble() ?? 0.0,
      taxas: (data['taxas'] as num?)?.toDouble() ?? 0.0,
      custoProdutos: (data['custoProdutos'] as num?)?.toDouble() ?? 0.0,
      descontoValor: (data['descontoValor'] as num?)?.toDouble() ?? 0.0,
      lojaId: lojaId,
      idFirebase: docId,
      clienteId: data['clienteId'] as String?,
      statusVenda: data['statusVenda'] as String?,
      cancelada: data['cancelada'] == true,
      estornada: data['estornada'] == true,
      origemVenda: data['origemVenda'] as String?,
      paymentId: data['paymentId'] as String?,
      orderId: data['orderId'] as String?,
      prePedidoId: (data['prePedidoId'] ?? data['origemPrePedido']) as String?,
      pedidoId: data['pedidoId'] as String?,
      origemCusto: VendaOrigemCusto.normalizarOuNull(
        (data['origemCusto'] as String?)?.trim(),
      ),
      itensComboSelecaoJson: () {
        final s = (data['itensComboSelecaoJson'] ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }(),
    );
  }

  /// Evita duplicar no Hive a mesma venda MP (paymentId + pedido).
  static bool localVendaJaExisteParaDocFirestore(
    Box<Venda> vendasBox,
    Map<String, dynamic> data,
  ) {
    final pay = (data['paymentId'] ?? '').toString().trim();
    final orig = (data['origemPrePedido'] ?? data['prePedidoId'] ?? data['orderId'] ?? '')
        .toString()
        .trim();
    if (pay.isEmpty || orig.isEmpty) return false;
    return vendasBox.values.any((v) {
      final vp = (v.paymentId ?? '').trim();
      final vo = (v.prePedidoId ?? v.orderId ?? '').trim();
      return vp == pay && vo == orig;
    });
  }

  static bool _isUuidVendaId(String s) =>
      s.contains('-') && s.length >= 36;

  /// Resolve docId em estoque_vendas sem sobrescrever UUID ou id MP canônico.
  static String resolveFirestoreVendaDocId(Venda v) {
    final existing = v.idFirebase?.trim() ?? '';
    if (existing.isNotEmpty) {
      if (_isUuidVendaId(existing)) return existing;
      if (isMpCanonicalVendaDocId(existing)) return existing;
      final asNum = int.tryParse(existing);
      if (asNum != null && existing.length < 12) {
        // legado: key Hive — não usar como docId estável
      } else {
        return existing;
      }
    }
    final orderKey = (v.prePedidoId ?? v.orderId ?? '').trim();
    final pay = (v.paymentId ?? '').trim();
    if (orderKey.isNotEmpty && pay.isNotEmpty) {
      final canonical =
          mpVendaFirestoreDocumentId(orderId: orderKey, paymentId: pay);
      logD(
        '[MP-IDEMPOTENCIA] docId canônico MP → $canonical (orderId=$orderKey)',
      );
      return canonical;
    }
    return const Uuid().v4();
  }

  /// Sincroniza uma venda para o Firestore (com retry para conexões instáveis)
  /// Retorna:
  /// - true  → venda confirmadamente gravada no Firestore
  /// - false → falha (com ou sem enfileiramento em SyncQueueService)
  ///
  /// [enqueueOnFailure] Se true, enfileira para retry quando falhar após 3 tentativas.
  /// Use false quando chamado pela SyncQueueService para evitar duplicação de itens na fila.
  static Future<bool> syncVenda(Venda venda, {String? lojaId, bool enqueueOnFailure = true}) async {
    const maxAttempts = 3;
    const baseDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
        if (storeId == null || storeId.isEmpty) {
          logE('❌ [VENDAS-SYNC] LojaId vazio, não pode sincronizar venda (vendaKey=${venda.key})');
          // Falha real: não há como enfileirar de forma segura sem lojaId.
          return false;
        }

        // [SYNC-DEBUG] Diagnóstico: envio de venda para Firestore
        logD('[SYNC-VENDAS] 📤 syncVenda ENVIANDO → lojaId=$storeId | cliente=${venda.clienteNome} | total=R\$${venda.total.toStringAsFixed(2)} | data=${venda.data}');

        final existingRaw = venda.idFirebase?.trim() ?? '';
        final wasUuid = _isUuidVendaId(existingRaw);
        final wasMp = isMpCanonicalVendaDocId(existingRaw);
        final oldIdIfNumeric = (existingRaw.isNotEmpty && !wasUuid && !wasMp)
            ? existingRaw
            : null;

        final vendaId = resolveFirestoreVendaDocId(venda);

        if (venda.idFirebase != vendaId) {
          logD('[MP-IDEMPOTENCIA] venda.key=${venda.key} idFirebase ${venda.idFirebase} → $vendaId');
          venda.idFirebase = vendaId;
          await venda.save();
        }

        final colRef = _db
            .collection('lojas')
            .doc(storeId)
            .collection(FSPaths.estoqueVendasCol);

        final remoteSnap = await colRef.doc(vendaId).get();
        if (remoteSnap.exists && isMpCanonicalVendaDocId(vendaId)) {
          logD(
            '[MP-IDEMPOTENCIA] doc já existe no Firestore ($vendaId); merge sem segundo UUID',
          );
        }

        // Remover doc antigo se migramos de ID numérico (evita duplicata no Firestore)
        if (oldIdIfNumeric != null && oldIdIfNumeric != vendaId) {
          try {
            await colRef.doc(oldIdIfNumeric).delete();
            logD('[SYNC-VENDAS] 🗑️ Doc antigo $oldIdIfNumeric removido (migrado para $vendaId)');
          } catch (_) {}
        }

        final vendaData = {
        'id': vendaId,
        'lojaId': storeId,
        'data': Timestamp.fromDate(venda.data),
        'total': venda.total,
        'desconto': venda.desconto,
        'descontoValor': venda.descontoValor,
        'formasPagamento': venda.formasPagamento,
        'frete': venda.frete,

        // Cliente
        'clienteNome': venda.clienteNome,
        'produtosDescricao': venda.produtosDescricao,
        'quantidade': venda.quantidade,
        'preco': venda.preco,
        'tamanho': venda.tamanho,
        'vendedor': venda.vendedor,
        'observacao': venda.observacao,

        // Pagamentos detalhados
        'pagamentoDinheiro': venda.pagamentoDinheiro,
        'pagamentoPix': venda.pagamentoPix,
        'pagamentoCartao': venda.pagamentoCartao,
        'taxas': venda.taxas,
        'custoProdutos': venda.custoProdutos,

        // Itens vendidos (estrutura completa para histórico; productId para fluxos ID-first)
        'itens': venda.itensOuVazio.map((item) => {
          'produtoNome': item.produtoNome,
          'quantidade': item.quantidade,
          'tamanho': item.tamanho,
          'cor': item.cor,
          'precoUnitario': item.precoUnitario,
          'precoTotal': item.precoUnitario * item.quantidade,
          if (item.productId != null && item.productId!.trim().isNotEmpty) 'productId': item.productId,
          if (item.variacaoExtraResumo.trim().isNotEmpty)
            'variacaoExtraResumo': item.variacaoExtraResumo.trim(),
          if (item.extraValor.trim().isNotEmpty) 'extraValor': item.extraValor.trim(),
          'custoUnitario': item.custoUnitario ?? 0.0,
          'origemCustoItem': item.origemCustoItem ?? VendaOrigemCusto.desconhecido,
        }).toList(),

        // Cliente estável (para consultas)
        'clienteId': venda.clienteId,

        if (venda.paymentId != null && venda.paymentId!.trim().isNotEmpty)
          'paymentId': venda.paymentId!.trim(),
        if (venda.orderId != null && venda.orderId!.trim().isNotEmpty)
          'orderId': venda.orderId!.trim(),
        if (venda.prePedidoId != null && venda.prePedidoId!.trim().isNotEmpty)
          'prePedidoId': venda.prePedidoId!.trim(),
        if (venda.pedidoId != null && venda.pedidoId!.trim().isNotEmpty)
          'pedidoId': venda.pedidoId!.trim(),
        if (venda.origemVenda != null && venda.origemVenda!.trim().isNotEmpty)
          'origemVenda': venda.origemVenda!.trim(),
        if (venda.origemCusto != null && venda.origemCusto!.trim().isNotEmpty)
          'origemCusto': venda.origemCusto!.trim(),
        if (venda.itensComboSelecaoJson != null &&
            venda.itensComboSelecaoJson!.trim().isNotEmpty)
          'itensComboSelecaoJson': venda.itensComboSelecaoJson!.trim(),
        if (venda.statusVenda != null && venda.statusVenda!.trim().isNotEmpty)
          'statusVenda': venda.statusVenda!.trim(),
        'cancelada': venda.cancelada,
        'estornada': venda.estornada,

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': 'concluida',
        };

        await colRef.doc(vendaId).set(vendaData, SetOptions(merge: true));

        logD('✅ [SYNC-VENDAS] Venda $vendaId sincronizada (lojaId=$storeId)');
        logD('[SYNC-VENDAS] 📤 OK → lojaId=$storeId | vendaId=$vendaId | cliente=${venda.clienteNome}');
        return true;
      } catch (e, st) {
        logE('❌ [VENDAS-SYNC] Tentativa $attempt/$maxAttempts falhou (vendaKey=${venda.key}, type=${e.runtimeType})', error: e, st: st);
        if (attempt < maxAttempts) {
          await Future<void>.delayed(baseDelay * attempt);
        } else {
          logE('❌ [VENDAS-SYNC] Erro final ao sincronizar venda (vendaKey=${venda.key}, type=${e.runtimeType})', error: e, st: st);
          // Enfileirar para retry só quando NÃO vem da própria fila (evita duplicação)
          if (enqueueOnFailure) {
            final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
            final key = venda.key;
            if (storeId != null && key != null) {
              logD('📋 [VENDAS-SYNC] Falhou; reenfileirado para retry (lojaId=$storeId, key=$key)');
              await SyncQueueService.enqueue(
                type: SyncOperationType.upsertVenda,
                lojaId: storeId,
                boxName: HiveBoxNames.vendas(storeId),
                entityKey: key as int,
              );
            } else {
              logE('❌ [VENDAS-SYNC] Falha ao enfileirar venda para retry (lojaId=$storeId, key=$key)');
            }
          } else {
            logD('📋 [VENDAS-SYNC] Falhou; não reenfileirado (já veio da fila, item permanece pendente)');
          }
          return false;
        }
      }
    }
    // Em teoria nunca chega aqui, mas manter por segurança.
    return false;
  }

  /// Sincroniza todas as vendas locais para o Firestore
  static Future<void> syncTodasVendas({required String boxName}) async {
    try {
      logD('🔄 [VENDAS-SYNC] Iniciando sync de todas as vendas...');

      final storeId = await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) {
        logE('❌ [VENDAS-SYNC] LojaId vazio em syncTodasVendas; abortando sync da box $boxName');
        return;
      }

      final box = await Hive.openBox<Venda>(boxName);
      int synced = 0;
      int errors = 0;

      for (int i = 0; i < box.length; i++) {
        final venda = box.getAt(i);
        if (venda != null) {
          try {
            final ok = await syncVenda(venda, lojaId: storeId);
            if (ok) {
              synced++;
            } else {
              errors++;
            }
          } catch (e, st) {
            errors++;
            logE('❌ [VENDAS-SYNC] Erro na venda (type=${e.runtimeType})', error: e, st: st);
          }
        }
      }

      logD('✅ [VENDAS-SYNC] Sync completo: $synced vendas sincronizadas, $errors erros');
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Sincroniza vendas do Firestore para o Hive (download)
  /// Útil para quando uma venda é feita em outro dispositivo/web
  /// ✅ Corrigido: usa orderBy('data') + paginação completa para não perder vendas
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<Venda> vendasBox,
  }) async {
    try {
      final localAntes = vendasBox.length;
      logD('🔄 [VENDAS-SYNC] Sincronizando vendas do Firestore → Hive...');
      logD('📥 [SYNC-DEBUG] syncFirestoreToHive INICIANDO → lojaId=$lojaId | vendasLocaisAntes=$localAntes');

      const batchSize = 200;
      int totalEncontradas = 0;
      int sincronizadas = 0;
      DocumentSnapshot? lastDoc;
      final firestoreVendaIds = <String>{};

      // ✅ Paginação: busca TODAS as vendas (não apenas 100)
      // ✅ orderBy('data') - campo sempre preenchido; createdAt pode faltar em migrações antigas
      while (true) {
        Query<Map<String, dynamic>> query = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueVendasCol)
            .orderBy('data', descending: true)
            .limit(batchSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snapshot = await query.get();
        totalEncontradas += snapshot.docs.length;

        if (snapshot.docs.isEmpty) break;

        for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final vendaId = doc.id;
          firestoreVendaIds.add(vendaId);

          final isUuid = vendaId.contains('-') && vendaId.length >= 36;
          final isMpDoc = isMpCanonicalVendaDocId(vendaId);
          if (isUuid || isMpDoc) {
            final existe = vendasBox.values.any((v) => v.idFirebase == vendaId);
            if (existe) {
              logD('[SYNC-VENDAS] ⏭️ venda $vendaId já no Hive (idFirebase), pulando');
              continue;
            }
          }
          if (localVendaJaExisteParaDocFirestore(vendasBox, data)) {
            logD(
              '[SYNC-VENDAS] ⏭️ duplicata MP (paymentId+pedido) remota=$vendaId — já existe local',
            );
            continue;
          }
          // Fallback legado: cliente + data (até segundo) + total
          final dataFirestore = (data['data'] as Timestamp?)?.toDate() ?? DateTime.now();
          final totalFirestore = (data['total'] as num?)?.toDouble() ?? 0.0;
          final clienteNome = (data['clienteNome'] ?? '').toString().trim();
          final existePorDados = vendasBox.values.any((v) {
            if (v.clienteNome.trim() != clienteNome) return false;
            if ((v.total - totalFirestore).abs() > 0.01) return false;
            final d = v.data;
            return d.year == dataFirestore.year && d.month == dataFirestore.month &&
                d.day == dataFirestore.day && d.hour == dataFirestore.hour &&
                d.minute == dataFirestore.minute && d.second == dataFirestore.second;
          });
          if (existePorDados) {
            logD('[SYNC-VENDAS] ⏭️ venda $vendaId já no Hive (cliente+data+total legado)');
            continue;
          }

          final venda = vendaFromFirestoreMap(data, vendaId, lojaId);

          // Salvar no Hive
          await vendasBox.add(venda);
          sincronizadas++;

          await linkMpImportedVendaToClienteFromPrePedidoIfNeeded(
            lojaId: lojaId,
            vendasBox: vendasBox,
            venda: venda,
            firestoreData: Map<String, dynamic>.from(data),
          );
          await reconcileMpVendaPagamentoFromPrePedidoIfNeeded(
            lojaId: lojaId,
            venda: venda,
            firestoreData: Map<String, dynamic>.from(data),
          );

          logD('✅ [VENDAS-SYNC] Venda $vendaId sincronizada do Firestore');
        } catch (e, st) {
          logE('❌ [VENDAS-SYNC] Erro ao sincronizar venda (type=${e.runtimeType})', error: e, st: st);
        }
        }

        if (snapshot.docs.length < batchSize) break;
        lastDoc = snapshot.docs.last;
      }

      // Remover locais que não existem mais no Firestore (excluídos em outro aparelho)
      final toRemove = <int>[];
      final vendasToRemove = <Venda>[];
      for (final k in vendasBox.keys) {
        final v = vendasBox.get(k);
        if (v != null && v.lojaId == lojaId && (v.idFirebase ?? '').isNotEmpty && !firestoreVendaIds.contains(v.idFirebase)) {
          toRemove.add(k as int);
          vendasToRemove.add(v);
        }
      }
      // Remover do histórico dos clientes antes de deletar
      try {
        final clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
        for (final v in vendasToRemove) {
          Cliente? c;
          for (final x in clientesBox.values) {
            if (x.lojaId == lojaId && x.nome == v.clienteNome) {
              c = x;
              break;
            }
          }
          if (c != null && c.historico != null) {
            c.historico!.removeWhere((h) => h.idFirebase == v.idFirebase);
            await c.save();
          }
        }
      } catch (_) {}
      for (final k in toRemove) {
        await vendasBox.delete(k);
        logD('🗑️ [VENDAS-SYNC] Venda local removida (excluída no Firestore): $k');
      }

      logD('📦 [VENDAS-SYNC] Total no Firestore: $totalEncontradas → $sincronizadas novas importadas, ${toRemove.length} removidas');
      logD('📥 [SYNC-DEBUG] syncFirestoreToHive FIM → lojaId=$lojaId | totalNoFirestore=$totalEncontradas | importadas=$sincronizadas | vendasLocaisAgora=${vendasBox.length}');
      return sincronizadas;
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Busca vendas do Firestore (útil para multi-dispositivo)
  static Stream<List<Map<String, dynamic>>> streamVendas({String? lojaId}) async* {
    final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
    if (storeId == null || storeId.isEmpty) {
      yield [];
      return;
    }

    yield* _db
        .collection('lojas')
        .doc(storeId)
        .collection(FSPaths.estoqueVendasCol)
        .orderBy('data', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Verifica se há vendas no Firestore que ainda não estão no dispositivo (para mostrar botão Importar).
  /// Retorna true quando a contagem no Firestore é maior que [localCount].
  static Future<bool> hasDataToImport({
    required String lojaId,
    required int localCount,
  }) async {
    try {
      final aggregate = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueVendasCol)
          .count();
      final snapshot = await aggregate.get();
      final remoteCount = snapshot.count ?? 0;
      final tem = remoteCount > localCount;
      logD('🔍 [SYNC-DEBUG] hasDataToImport → lojaId=$lojaId | local=$localCount | Firestore=$remoteCount | temParaImportar=$tem');
      return tem;
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Deleta uma venda do Firestore
  static Future<void> deleteVenda(String vendaId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueVendasCol)
          .doc(vendaId)
          .delete();

      logD('🗑️ [VENDAS-SYNC] Venda $vendaId deletada do Firestore');
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao deletar venda (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Estatísticas de vendas do Firestore
  static Future<Map<String, dynamic>> getEstatisticas({String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return {};

      final vendasSnap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueVendasCol)
          .get();

      double totalVendas = 0;
      int quantidadeVendas = 0;
      Map<String, double> vendasPorMes = {};

      for (final doc in vendasSnap.docs) {
        final data = doc.data();
        if (!incluirVendaFirestoreMap(data)) continue;
        quantidadeVendas++;
        final total = (data['total'] as num?)?.toDouble() ?? 0;
        totalVendas += total;

        // Agrupar por mês
        final timestamp = data['data'] as Timestamp?;
        if (timestamp != null) {
          final date = timestamp.toDate();
          final mesAno = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          vendasPorMes[mesAno] = (vendasPorMes[mesAno] ?? 0) + total;
        }
      }

      return {
        'totalVendas': totalVendas,
        'quantidadeVendas': quantidadeVendas,
        'ticketMedio': quantidadeVendas > 0 ? totalVendas / quantidadeVendas : 0,
        'vendasPorMes': vendasPorMes,
      };
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao buscar estatísticas (type=${e.runtimeType})', error: e, st: st);
      return {};
    }
  }

  static String _digitsOnly(String? s) =>
      RegExp(r'\d').allMatches(s ?? '').map((m) => m.group(0)!).join();

  static bool _isMpWebhookVenda(Map<String, dynamic> data, Venda v) {
    if (isMpCanonicalVendaDocId(v.idFirebase)) return true;
    final o =
        (v.origemVenda ?? data['origemVenda'] ?? '').toString().toLowerCase();
    return o == 'mp_webhook' || o.contains('mp_webhook');
  }

  /// Aplica forma de pagamento do pedido catálogo nos campos discriminados da [Venda].
  static void aplicarPagamentoCatalogoNaVenda({
    required Venda venda,
    required String pagamento,
    required double total,
  }) {
    final p = pagamento.trim();
    if (p.isEmpty || total <= 0) return;
    final upper = p.toUpperCase();
    venda.formasPagamento = p;
    venda.pagamentoPix = 0;
    venda.pagamentoCartao = 0;
    venda.pagamentoDinheiro = 0;
    if (upper == 'PIX' || (upper.contains('PIX') && !upper.contains('CART'))) {
      venda.pagamentoPix = total;
    } else if (upper.contains('CART') ||
        upper.contains('CARTÃO') ||
        upper == 'MERCADO PAGO' ||
        upper.contains('MERCADO PAGO')) {
      venda.pagamentoCartao = total;
    } else if (upper.contains('DINHEIRO')) {
      venda.pagamentoDinheiro = total;
    } else {
      venda.pagamentoPix = total;
    }
  }

  /// Corrige vendas MP espelhadas com `pagamentoCartao = total` indevido (legado webhook).
  static bool _vendaMpPrecisaReconciliarPagamento(Venda v) {
    if (v.total <= 0) return false;
    if (v.pagamentoPix > 0.01) return false;
    if (v.pagamentoCartao >= v.total * 0.99) {
      final fp = v.formasPagamento.toUpperCase();
      if (fp == 'MERCADO PAGO' || fp.isEmpty) return true;
    }
    return false;
  }

  /// Lê `pre_pedidos/{id}.pagamento` e alinha Hive após import/sync.
  static Future<void> reconcileMpVendaPagamentoFromPrePedidoIfNeeded({
    required String lojaId,
    required Venda venda,
    required Map<String, dynamic> firestoreData,
  }) async {
    if (!_isMpWebhookVenda(firestoreData, venda)) return;
    if (!_vendaMpPrecisaReconciliarPagamento(venda)) return;

    final prePedidoId = _resolvePrePedidoIdForMp(venda, firestoreData);
    if (prePedidoId == null || prePedidoId.isEmpty) return;

    try {
      final snap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('pre_pedidos')
          .doc(prePedidoId)
          .get();
      if (!snap.exists) return;
      final pedido = snap.data();
      if (pedido == null) return;
      final pagamento = (pedido['pagamento'] ?? '').toString().trim();
      if (pagamento.isEmpty) return;

      aplicarPagamentoCatalogoNaVenda(
        venda: venda,
        pagamento: pagamento,
        total: venda.total,
      );
      await venda.save();
      logD(
        '[MP-PAGAMENTO] Venda ${venda.idFirebase} reconciliada: $pagamento',
      );
    } catch (e) {
      logW(
        '[MP-PAGAMENTO] Falha ao reconciliar pagamento (type=${e.runtimeType}): $e',
      );
    }
  }

  static String? _resolvePrePedidoIdForMp(Venda v, Map<String, dynamic> data) {
    String? pick(String? a, String? b) {
      final x = (a ?? '').trim();
      if (x.isNotEmpty) return x;
      final y = (b ?? '').trim();
      return y.isNotEmpty ? y : null;
    }

    final fromVenda = pick(v.prePedidoId, v.orderId);
    if (fromVenda != null) return fromVenda;

    final d1 = data['prePedidoId']?.toString().trim();
    if (d1 != null && d1.isNotEmpty) return d1;
    final d2 = data['origemPrePedido']?.toString().trim();
    if (d2 != null && d2.isNotEmpty) return d2;
    final d3 = data['orderId']?.toString().trim();
    if (d3 != null && d3.isNotEmpty) return d3;
    return null;
  }

  static String _pickEnderecoCampo(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  static String _linhaEnderecoPreferFormatado(
    Map<String, dynamic> customer,
    Map<String, dynamic>? endMap,
  ) {
    final fmt = (customer['enderecoFormatado'] ?? '').toString().trim();
    if (fmt.isNotEmpty) return fmt;
    if (endMap == null || endMap.isEmpty) return '';
    final rua = _pickEnderecoCampo(endMap, ['rua', 'logradouro', 'street']);
    final numero = _pickEnderecoCampo(endMap, ['numero', 'número', 'number']);
    final bairro = _pickEnderecoCampo(endMap, ['bairro']);
    final cidade = _pickEnderecoCampo(endMap, ['cidade', 'localidade']);
    final uf = _pickEnderecoCampo(endMap, ['estado', 'uf']);
    final cep = _pickEnderecoCampo(endMap, ['cep', 'CEP']);
    final comp = _pickEnderecoCampo(endMap, ['complemento']);
    final parts = <String>[];
    if (rua.isNotEmpty) {
      parts.add(numero.isNotEmpty ? '$rua, nº $numero' : rua);
    } else if (numero.isNotEmpty) {
      parts.add('nº $numero');
    }
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty) parts.add(cidade);
    if (uf.isNotEmpty) parts.add(uf);
    if (cep.isNotEmpty) parts.add('CEP $cep');
    if (comp.isNotEmpty) parts.add(comp);
    return parts.join(' — ');
  }

  /// Após importar venda MP (`estoque_vendas` → Hive): lê `pre_pedidos`, cria/atualiza [Cliente] local e histórico.
  /// Idempotente; não altera estoque nem pagamento.
  static Future<void> linkMpImportedVendaToClienteFromPrePedidoIfNeeded({
    required String lojaId,
    required Box<Venda> vendasBox,
    required Venda venda,
    required Map<String, dynamic> firestoreData,
  }) async {
    try {
      if (!_isMpWebhookVenda(firestoreData, venda)) return;

      final prePedidoId = _resolvePrePedidoIdForMp(venda, firestoreData);
      if (prePedidoId == null || prePedidoId.isEmpty) return;

      final snap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('pre_pedidos')
          .doc(prePedidoId)
          .get();

      if (!snap.exists) return;
      final pedido = snap.data();
      if (pedido == null) return;

      final rawCliente = pedido['cliente'];
      if (rawCliente is! Map) return;
      final customer = Map<String, dynamic>.from(rawCliente);

      final telDigits = _digitsOnly(customer['telefone']?.toString());
      final emailNorm =
          (customer['email'] ?? '').toString().trim().toLowerCase();

      if (telDigits.isEmpty && emailNorm.isEmpty) return;

      Map<String, dynamic>? endMap;
      final endRaw = customer['endereco'];
      if (endRaw is Map) {
        endMap = Map<String, dynamic>.from(endRaw);
      }

      final cep = _pickEnderecoCampo(endMap, ['cep', 'CEP']);
      final cidade =
          _pickEnderecoCampo(endMap, ['cidade', 'localidade', 'city']);
      final linhaEnd =
          _linhaEnderecoPreferFormatado(customer, endMap).trim();

      final clientesBox =
          await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));

      Cliente? found;
      for (final c in clientesBox.values) {
        if (c.lojaId.isNotEmpty && c.lojaId != lojaId) continue;
        if (telDigits.isNotEmpty && _digitsOnly(c.telefone) == telDigits) {
          found = c;
          break;
        }
        final ce = (c.email ?? '').trim().toLowerCase();
        if (emailNorm.isNotEmpty && ce == emailNorm) {
          found = c;
          break;
        }
      }

      final nomeIn = (customer['nome'] ?? '').toString().trim();
      final nomeFinal = nomeIn.isNotEmpty
          ? nomeIn
          : (venda.clienteNome.trim().isNotEmpty ? venda.clienteNome : 'Cliente');

      if (found == null) {
        final telDisplay = (customer['telefone'] ?? '').toString();
        found = Cliente(
          nome: nomeFinal,
          telefone: telDisplay,
          instagram: '',
          cep: cep,
          cidade: cidade.isNotEmpty ? cidade : '',
          email: emailNorm.isEmpty
              ? null
              : customer['email']?.toString().trim(),
          endereco: linhaEnd.isNotEmpty ? linhaEnd : null,
          lojaId: lojaId,
        );
        await clientesBox.add(found);
      } else {
        if (nomeFinal.isNotEmpty) found.nome = nomeFinal;
        final tel = (customer['telefone'] ?? '').toString();
        if (tel.isNotEmpty) found.telefone = tel;
        final em = (customer['email'] ?? '').toString().trim();
        if (em.isNotEmpty) found.email = em;
        if (cep.isNotEmpty) found.cep = cep;
        if (cidade.isNotEmpty) found.cidade = cidade;
        if (linhaEnd.isNotEmpty) found.endereco = linhaEnd;
        await found.save();
      }

      final pay = (venda.paymentId ?? '').trim();
      final ordKey =
          (venda.prePedidoId ?? venda.orderId ?? prePedidoId).trim();

      // ignore: experimental_member_use
      found.historico ??= HiveList(vendasBox);

      final jaTem = found.historico!.any((h) {
        if (identical(h, venda)) return true;
        if (h.key != null &&
            venda.key != null &&
            h.key == venda.key) {
          return true;
        }
        final hid = (h.idFirebase ?? '').trim();
        final vid = (venda.idFirebase ?? '').trim();
        if (hid.isNotEmpty && vid.isNotEmpty && hid == vid) return true;
        final hp = (h.paymentId ?? '').trim();
        if (pay.isNotEmpty && hp == pay) {
          final ho = (h.prePedidoId ?? h.orderId ?? '').trim();
          if (ho.isNotEmpty &&
              ordKey.isNotEmpty &&
              ho == ordKey) {
            return true;
          }
        }
        return false;
      });

      if (!jaTem) {
        found.historico!.add(venda);
        await found.save();
      }

      if ((venda.clienteId ?? '').trim().isEmpty && found.key != null) {
        venda.clienteId = found.key.toString();
        await venda.save();
      }
    } catch (e, st) {
      logE(
        '⚠️ [MP-CLIENTE-HIVE] Vincular cliente pós-import (não crítico)',
        error: e,
        st: st,
      );
    }
  }
}
