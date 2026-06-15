// lib/services/vendas_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/conta_receber_venda_vinculo.dart';
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

  /// Atualiza pagamentos/total da venda local quando o remoto mudou (ex.: fiado misto).
  static Future<bool> mesclarPagamentosRemotoNaVendaHive({
    required Venda local,
    required Map<String, dynamic> data,
    required String lojaId,
  }) async {
    var changed = false;
    void setDouble(void Function(double) set, double value) {
      if (value.isNaN) return;
      set(value);
      changed = true;
    }

    final din = (data['pagamentoDinheiro'] as num?)?.toDouble();
    final pix = (data['pagamentoPix'] as num?)?.toDouble();
    final cart = (data['pagamentoCartao'] as num?)?.toDouble();
    final total = (data['total'] as num?)?.toDouble();
    final formas = (data['formasPagamento'] ?? '').toString();

    if (din != null && (local.pagamentoDinheiro - din).abs() > 0.009) {
      setDouble((v) => local.pagamentoDinheiro = v, din);
    }
    if (pix != null && (local.pagamentoPix - pix).abs() > 0.009) {
      setDouble((v) => local.pagamentoPix = v, pix);
    }
    if (cart != null && (local.pagamentoCartao - cart).abs() > 0.009) {
      setDouble((v) => local.pagamentoCartao = v, cart);
    }
    if (total != null && (local.total - total).abs() > 0.009) {
      setDouble((v) => local.total = v, total);
    }
    if (formas.trim().isNotEmpty && local.formasPagamento.trim() != formas.trim()) {
      local.formasPagamento = formas;
      changed = true;
    }
    if (local.lojaId == null || local.lojaId!.trim().isEmpty) {
      local.lojaId = lojaId;
      changed = true;
    }
    if (changed) {
      try {
        await local.save();
      } catch (_) {}
    }
    return changed;
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

        // Fiado / saldo a receber (backfill cross-device)
        ...() {
          final saldoFiado = valorAReceberDaVenda(venda);
          if (saldoFiado <= 0.01) return <String, dynamic>{};
          final meta =
              parseFiadoMetadataFromFormasPagamento(venda.formasPagamento);
          final extra = <String, dynamic>{'saldoFiado': saldoFiado};
          if (meta.quantidadeParcelas > 1) {
            extra['quantidadeParcelasFiado'] = meta.quantidadeParcelas;
            extra['intervaloParcelasDias'] = meta.intervaloDias;
          }
          if (meta.dataVencimento != null) {
            extra['dataVencimentoFiado'] =
                Timestamp.fromDate(meta.dataVencimento!);
          }
          return extra;
        }(),

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
            final existente = vendasBox.values.cast<Venda?>().firstWhere(
                  (v) => v!.idFirebase == vendaId,
                  orElse: () => null,
                );
            if (existente != null) {
              await mesclarPagamentosRemotoNaVendaHive(
                local: existente,
                data: data,
                lojaId: lojaId,
              );
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
}
