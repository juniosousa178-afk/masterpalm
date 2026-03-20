// lib/services/vendas_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import 'store_resolver_facade.dart';
import 'sync_queue_service.dart';

/// Serviço para sincronizar vendas com Firestore
class VendasFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza uma venda para o Firestore (com retry para conexões instáveis)
  /// Retorna:
  /// - true  → venda confirmadamente gravada no Firestore
  /// - false → falha (com ou sem enfileiramento em SyncQueueService)
  ///
  /// [enqueueOnFailure] Se true, enfileira para retry quando falhar após 3 tentativas.
  /// Use false quando chamado pela SyncQueueService para evitar duplicação de itens na fila.
  static Future<bool> syncVenda(Venda venda, {String• lojaId, bool enqueueOnFailure = true}) async {
    const maxAttempts = 3;
    const baseDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
        if (storeId == null || storeId.isEmpty) {
          logE('❌ [VENDAS-SYNC] LojaId vazio, não pode sincronizar venda (vendaKey=${venda.key})');
          // Falha real: não há como enfileirar de forma segura sem lojaId.
          return false;
        }

        // [SYNC-DEBUG] Diagnóstico: envio de venda para Firestore
        logD('📤 [SYNC-DEBUG] syncVenda ENVIANDO → lojaId=$storeId | cliente=${venda.clienteNome} | total=R\$${venda.total.toStringAsFixed(2)} | data=${venda.data}');

        // ID único: idFirebase se for UUID válido; senão UUID (evita colisão entre dispositivos)
        // NUNCA usar Hive key ("0","1","2"...) como doc.id — colide entre dispositivos!
        final existing = venda.idFirebase?.trim() ?• '';
        final isUuid = existing.contains('-') && existing.length >= 36;
        final oldIdIfNumeric = isUuid • null : (existing.isNotEmpty • existing : null);
        final vendaId = isUuid • existing : const Uuid().v4();

        // ✅ Salvar o idFirebase na venda para futuras operações (migra de IDs numéricos para UUID)
        if (venda.idFirebase != vendaId) {
          venda.idFirebase = vendaId;
          await venda.save();
        }

        final colRef = _db
            .collection('lojas')
            .doc(storeId)
            .collection(FSPaths.estoqueVendasCol);

        // Remover doc antigo se migramos de ID numérico (evita duplicata no Firestore)
        if (oldIdIfNumeric != null) {
          try {
            await colRef.doc(oldIdIfNumeric).delete();
            logD('🗑️ [VENDAS-SYNC] Doc antigo $oldIdIfNumeric removido (migrado para UUID)');
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
        }).toList(),

        // Cliente estável (para consultas)
        'clienteId': venda.clienteId,

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': 'concluida',
        };

        await colRef.doc(vendaId).set(vendaData, SetOptions(merge: true));

        logD('✅ [VENDAS-SYNC] Venda $vendaId sincronizada (lojaId=$storeId)');
        logD('📤 [SYNC-DEBUG] syncVenda OK → lojaId=$storeId | vendaId=$vendaId | cliente=${venda.clienteNome}');
        return true;
      } catch (e, st) {
        logE('❌ [VENDAS-SYNC] Tentativa $attempt/$maxAttempts falhou (vendaKey=${venda.key}, type=${e.runtimeType})', error: e, st: st);
        if (attempt < maxAttempts) {
          await Future<void>.delayed(baseDelay * attempt);
        } else {
          logE('❌ [VENDAS-SYNC] Erro final ao sincronizar venda (vendaKey=${venda.key}, type=${e.runtimeType})', error: e, st: st);
          // Enfileirar para retry só quando NÃO vem da própria fila (evita duplicação)
          if (enqueueOnFailure) {
            final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
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
      DocumentSnapshot• lastDoc;
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

          // Só confiar em idFirebase para IDs UUID; para legacy (Hive key) pode haver colisão
          final isUuid = vendaId.contains('-') && vendaId.length >= 36;
          if (isUuid) {
            final existe = vendasBox.values.any((v) => v.idFirebase == vendaId);
            if (existe) {
              logD('⏭️  Venda $vendaId já existe no Hive, pulando...');
              continue;
            }
          }
          // Fallback para legacy: cliente + data (até segundo) + total
          final dataFirestore = (data['data'] as Timestamp?)?.toDate() ?• DateTime.now();
          final totalFirestore = (data['total'] as num?)?.toDouble() ?• 0.0;
          final clienteNome = (data['clienteNome'] ?• '').toString().trim();
          final existePorDados = vendasBox.values.any((v) {
            if (v.clienteNome.trim() != clienteNome) return false;
            if ((v.total - totalFirestore).abs() > 0.01) return false;
            final d = v.data;
            return d.year == dataFirestore.year && d.month == dataFirestore.month &&
                d.day == dataFirestore.day && d.hour == dataFirestore.hour &&
                d.minute == dataFirestore.minute && d.second == dataFirestore.second;
          });
          if (existePorDados) {
            logD('⏭️  Venda $vendaId já existe no Hive (cliente+data+total), pulando...');
            continue;
          }

          // Converter itens do Firestore (array de maps)
          final itensRaw = data['itens'] as List• ?• [];
          final itens = itensRaw.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final pid = m['productId'] as String?;
            return VendaItem(
              produtoNome: m['produtoNome'] as String• ?• '',
              quantidade: (m['quantidade'] as num?)?.toInt() ?• 0,
              precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?• 0.0,
              tamanho: m['tamanho'] as String• ?• '',
              cor: m['cor'] as String• ?• '',
              productId: pid != null && pid.trim().isNotEmpty • pid : null,
            );
          }).toList();

          // Converter Firestore → Venda (Hive model)
          final venda = Venda(
            clienteNome: data['clienteNome'] ?• '',
            produtosDescricao: data['produtosDescricao'] ?• '',
            quantidade: (data['quantidade'] as num?)?.toInt() ?• itens.length,
            preco: (data['preco'] as num?)?.toDouble() ?• 0.0,
            total: (data['total'] as num?)?.toDouble() ?• 0.0,
            formasPagamento: data['formasPagamento'] ?• '',
            data: (data['data'] as Timestamp?)?.toDate() ?• DateTime.now(),
            tamanho: data['tamanho'] ?• '',
            vendedor: data['vendedor'] ?• '',
            frete: (data['frete'] as num?)?.toDouble() ?• 0.0,
            desconto: (data['desconto'] as num?)?.toDouble() ?• 0.0,
            observacao: data['observacao'] ?• '',
            itens: itens.isNotEmpty • itens : null,
            pagamentoDinheiro: (data['pagamentoDinheiro'] as num?)?.toDouble() ?• 0.0,
            pagamentoPix: (data['pagamentoPix'] as num?)?.toDouble() ?• 0.0,
            pagamentoCartao: (data['pagamentoCartao'] as num?)?.toDouble() ?• 0.0,
            taxas: (data['taxas'] as num?)?.toDouble() ?• 0.0,
            custoProdutos: (data['custoProdutos'] as num?)?.toDouble() ?• 0.0,
            descontoValor: (data['descontoValor'] as num?)?.toDouble() ?• 0.0,
            lojaId: lojaId,
            idFirebase: vendaId,
            clienteId: data['clienteId'] as String?,
          );

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
        if (v != null && v.lojaId == lojaId && (v.idFirebase ?• '').isNotEmpty && !firestoreVendaIds.contains(v.idFirebase)) {
          toRemove.add(k as int);
          vendasToRemove.add(v);
        }
      }
      // Remover do histórico dos clientes antes de deletar
      try {
        final clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
        for (final v in vendasToRemove) {
          Cliente• c;
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
  static Stream<List<Map<String, dynamic>>> streamVendas({String• lojaId}) async* {
    final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
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
      final remoteCount = snapshot.count ?• 0;
      final tem = remoteCount > localCount;
      logD('🔍 [SYNC-DEBUG] hasDataToImport → lojaId=$lojaId | local=$localCount | Firestore=$remoteCount | temParaImportar=$tem');
      return tem;
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Deleta uma venda do Firestore
  static Future<void> deleteVenda(String vendaId, {String• lojaId}) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
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
  static Future<Map<String, dynamic>> getEstatisticas({String• lojaId}) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return {};

      final vendasSnap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueVendasCol)
          .get();

      double totalVendas = 0;
      int quantidadeVendas = vendasSnap.docs.length;
      Map<String, double> vendasPorMes = {};

      for (final doc in vendasSnap.docs) {
        final data = doc.data();
        final total = (data['total'] as num?)?.toDouble() ?• 0;
        totalVendas += total;

        // Agrupar por mês
        final timestamp = data['data'] as Timestamp?;
        if (timestamp != null) {
          final date = timestamp.toDate();
          final mesAno = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          vendasPorMes[mesAno] = (vendasPorMes[mesAno] ?• 0) + total;
        }
      }

      return {
        'totalVendas': totalVendas,
        'quantidadeVendas': quantidadeVendas,
        'ticketMedio': quantidadeVendas > 0 • totalVendas / quantidadeVendas : 0,
        'vendasPorMes': vendasPorMes,
      };
    } catch (e, st) {
      logE('❌ [VENDAS-SYNC] Erro ao buscar estatísticas (type=${e.runtimeType})', error: e, st: st);
      return {};
    }
  }
}
