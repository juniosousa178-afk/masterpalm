// lib/services/sync_firestore_script.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/categoria.dart';
import '../models/fornecedor.dart';
import 'firestore_paths.dart';
import 'store_resolver_facade.dart';
import 'sync_queue_service.dart';
import 'vendas_firestore_service.dart';

/// Script completo para sincronizar TODAS as coleções do Hive → Firestore
/// Garante que o banco de dados do Firestore está 100% atualizado com o app local
class SyncFirestoreScript {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// SCRIPT PRINCIPAL - Executa tudo
  static Future<Map<String, dynamic>> syncTudo() async {
    debugPrint('🚀 [SYNC-SCRIPT] Iniciando sincronização completa...');

    final results = <String, dynamic>{
      'success': true,
      'lojaId': '',
      'produtos': {'synced': 0, 'errors': 0},
      'clientes': {'synced': 0, 'errors': 0},
      'vendas': {'synced': 0, 'errors': 0},
      'categorias': {'synced': 0, 'errors': 0},
      'fornecedores': {'synced': 0, 'errors': 0},
      'config': {'synced': 0, 'errors': 0},
      'errors': <String>[],
    };

    try {
      // 1. Resolver lojaId
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        results['success'] = false;
        (results['errors'] as List<String>).add('LojaId não resolvido');
        debugPrint('❌ [SYNC-SCRIPT] LojaId vazio, abortando');
        return results;
      }

      results['lojaId'] = lojaId;
      debugPrint('✅ [SYNC-SCRIPT] LojaId: $lojaId');

      // 1.5 Processar fila pendente (vendas/clientes etc.) antes de sincronizar a box local
      final queueResult = await SyncQueueService.processPending();
      if (queueResult.processed > 0 || queueResult.failed > 0) {
        debugPrint('📋 [SYNC-SCRIPT] Fila: processados=${queueResult.processed} falhas=${queueResult.failed} ignorados=${queueResult.skipped}');
      }
      final pendentesApos = await SyncQueueService.pendingCount();
      if (pendentesApos > 0) {
        debugPrint('⚠️ [SYNC-SCRIPT] Fila ainda tem $pendentesApos itens pendentes');
      }

      // 2. Sincronizar Produtos
      debugPrint('📦 [SYNC-SCRIPT] Sincronizando produtos...');
      final produtosResult = await _syncProdutos(lojaId);
      results['produtos'] = produtosResult;

      // 3. Sincronizar Clientes
      debugPrint('👥 [SYNC-SCRIPT] Sincronizando clientes...');
      final clientesResult = await _syncClientes(lojaId);
      results['clientes'] = clientesResult;

      // 4. Sincronizar Vendas
      debugPrint('💰 [SYNC-SCRIPT] Sincronizando vendas...');
      final vendasResult = await _syncVendas(lojaId);
      results['vendas'] = vendasResult;

      // 5. Sincronizar Categorias
      debugPrint('🏷️ [SYNC-SCRIPT] Sincronizando categorias...');
      final categoriasResult = await _syncCategorias(lojaId);
      results['categorias'] = categoriasResult;

      // 6. Sincronizar Fornecedores
      debugPrint('🏭 [SYNC-SCRIPT] Sincronizando fornecedores...');
      final fornecedoresResult = await _syncFornecedores(lojaId);
      results['fornecedores'] = fornecedoresResult;

      // 7. Verificar Config (não sobrescrever se já existir)
      debugPrint('⚙️ [SYNC-SCRIPT] Verificando config...');
      final configResult = await _verificarConfig(lojaId);
      results['config'] = configResult;

      debugPrint('✅ [SYNC-SCRIPT] Sincronização completa!');
      debugPrint('📊 [SYNC-SCRIPT] Produtos: ${produtosResult['synced']} | Clientes: ${clientesResult['synced']} | Vendas: ${vendasResult['synced']}');

    } catch (e) {
      debugPrint('❌ [SYNC-SCRIPT] Erro geral (type=${e.runtimeType})');
      results['success'] = false;
      (results['errors'] as List<String>).add('Erro geral: $e');
    }

    return results;
  }

  /// Sincroniza todos os produtos do Hive → Firestore
  static Future<Map<String, int>> _syncProdutos(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final boxName = HiveBoxNames.produtos(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Produto>(boxName);
      }

      final box = Hive.box<Produto>(boxName);
      debugPrint('📦 [PRODUTOS] Total no Hive: ${box.length}');

      final batch = _db.batch();
      final produtosRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos');

      for (int i = 0; i < box.length; i++) {
        final produto = box.getAt(i);
        if (produto == null) continue;

        try {
          final produtoId = produto.key?.toString() ??
              produto.slug.replaceAll(' ', '_').toLowerCase();

          final data = {
            'id': produtoId,
            'lojaId': lojaId,
            'nome': produto.nome,
            'slug': produto.slug,
            'descricao': produto.descricao,
            'custoReal': produto.custoReal,
            'frete': produto.frete,
            'gastosFixos': produto.gastosFixos,
            'gastosVariaveis': produto.gastosVariaveis,
            'precoSugerido': produto.precoSugerido,
            'precoFinal': produto.precoFinal,
            'precoUnitario': produto.precoUnitario,
            'quantidade': produto.quantidade,
            'estoquePorTamanho': produto.estoquePorTamanho,
            'categoria': produto.categoria,
            'subcategoria': produto.subcategoria,
            'imagens': produto.imagens,
            'tamanhos': produto.tamanhos,
            'publicadoNoCatalogo': produto.publicadoNoCatalogo,
            'ativoNoRascunho': produto.ativoNoRascunho,
            'emPromocao': produto.emPromocao,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          batch.set(
            produtosRef.doc(produtoId),
            data,
            SetOptions(merge: true),
          );

          synced++;

          // Commit a cada 500 (limite do Firestore é 500)
          if (synced % 450 == 0) {
            await batch.commit();
            debugPrint('✅ [PRODUTOS] Batch committed: $synced produtos');
          }

        } catch (e) {
          debugPrint('❌ [PRODUTOS] Erro no produto (type=${e.runtimeType})');
          errors++;
        }
      }

      // Commit final
      await batch.commit();
      debugPrint('✅ [PRODUTOS] Sincronizados: $synced | Erros: $errors');

    } catch (e) {
      debugPrint('❌ [PRODUTOS] Erro geral (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Sincroniza todos os clientes do Hive → Firestore
  static Future<Map<String, int>> _syncClientes(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final boxName = HiveBoxNames.clientes(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Cliente>(boxName);
      }

      final box = Hive.box<Cliente>(boxName);
      debugPrint('👥 [CLIENTES] Total no Hive: ${box.length}');

      final batch = _db.batch();
      final clientesRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('clientes');

      for (int i = 0; i < box.length; i++) {
        final cliente = box.getAt(i);
        if (cliente == null) continue;

        try {
          final clienteId = cliente.key?.toString() ??
              '${cliente.nome.replaceAll(' ', '_').toLowerCase()}_$i';

          final data = {
            'id': clienteId,
            'lojaId': lojaId,
            'nome': cliente.nome,
            'telefone': cliente.telefone,
            'instagram': cliente.instagram,
            'cep': cliente.cep,
            'cidade': cliente.cidade,
            'totalCompras': cliente.historico?.length ?• 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          batch.set(
            clientesRef.doc(clienteId),
            data,
            SetOptions(merge: true),
          );

          synced++;

          if (synced % 450 == 0) {
            await batch.commit();
            debugPrint('✅ [CLIENTES] Batch committed: $synced clientes');
          }

        } catch (e) {
          debugPrint('❌ [CLIENTES] Erro no cliente (type=${e.runtimeType})');
          errors++;
        }
      }

      await batch.commit();
      debugPrint('✅ [CLIENTES] Sincronizados: $synced | Erros: $errors');

    } catch (e) {
      debugPrint('❌ [CLIENTES] Erro geral (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Sincroniza todas as vendas do Hive → Firestore
  static Future<Map<String, int>> _syncVendas(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final boxName = HiveBoxNames.vendas(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Venda>(boxName);
      }

      final box = Hive.box<Venda>(boxName);
      debugPrint('💰 [VENDAS] Total no Hive: ${box.length}');

      // Usa o serviço existente
      for (int i = 0; i < box.length; i++) {
        final venda = box.getAt(i);
        if (venda == null) continue;

        try {
          final ok = await VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
          if (ok) {
            synced++;
          } else {
            errors++;
          }

          if (synced % 50 == 0) {
            debugPrint('✅ [VENDAS] Progresso: $synced vendas');
          }

        } catch (e) {
          debugPrint('❌ [VENDAS] Erro na venda (type=${e.runtimeType})');
          errors++;
        }
      }

      debugPrint('✅ [VENDAS] Sincronizadas: $synced | Erros: $errors');

    } catch (e) {
      debugPrint('❌ [VENDAS] Erro geral (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Sincroniza todas as categorias do Hive → Firestore
  static Future<Map<String, int>> _syncCategorias(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final boxName = HiveBoxNames.categorias(lojaId);
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Categoria>(boxName);
      }

      final box = Hive.box<Categoria>(boxName);
      debugPrint('🏷️ [CATEGORIAS] Total no Hive: ${box.length}');

      final batch = _db.batch();
      final categoriasRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('categorias');

      for (int i = 0; i < box.length; i++) {
        final categoria = box.getAt(i);
        if (categoria == null) continue;

        try {
          final categoriaId = categoria.nome.replaceAll(' ', '_').toLowerCase();

          final data = {
            'id': categoriaId,
            'lojaId': lojaId,
            'nome': categoria.nome,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          batch.set(
            categoriasRef.doc(categoriaId),
            data,
            SetOptions(merge: true),
          );

          synced++;

        } catch (e) {
          debugPrint('❌ [CATEGORIAS] Erro na categoria (type=${e.runtimeType})');
          errors++;
        }
      }

      await batch.commit();
      debugPrint('✅ [CATEGORIAS] Sincronizadas: $synced | Erros: $errors');

    } catch (e) {
      debugPrint('❌ [CATEGORIAS] Erro geral (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Sincroniza todos os fornecedores do Hive → Firestore
  static Future<Map<String, int>> _syncFornecedores(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final boxName = HiveBoxNames.fornecedores(lojaId);
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Fornecedor>(boxName);
      }

      final box = Hive.box<Fornecedor>(boxName);
      debugPrint('🏭 [FORNECEDORES] Total no Hive: ${box.length}');

      final batch = _db.batch();
      final fornecedoresRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('fornecedores');

      for (int i = 0; i < box.length; i++) {
        final fornecedor = box.getAt(i);
        if (fornecedor == null) continue;

        try {
          final fornecedorId = fornecedor.nome.replaceAll(' ', '_').toLowerCase();

          final data = {
            'id': fornecedorId,
            'lojaId': lojaId,
            'nome': fornecedor.nome,
            'telefone': fornecedor.telefone,
            'email': fornecedor.email,
            'instagram': fornecedor.instagram,
            'whatsapp': fornecedor.whatsapp,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          batch.set(
            fornecedoresRef.doc(fornecedorId),
            data,
            SetOptions(merge: true),
          );

          synced++;

        } catch (e) {
          debugPrint('❌ [FORNECEDORES] Erro no fornecedor (type=${e.runtimeType})');
          errors++;
        }
      }

      await batch.commit();
      debugPrint('✅ [FORNECEDORES] Sincronizados: $synced | Erros: $errors');

    } catch (e) {
      debugPrint('❌ [FORNECEDORES] Erro geral (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Verifica se config existe, não sobrescreve se já houver
  static Future<Map<String, int>> _verificarConfig(String lojaId) async {
    int synced = 0;
    int errors = 0;

    try {
      final configDoc = await _db
          .collection('lojas')
          .doc(lojaId)
          .get();

      if (!configDoc.exists) {
        // Cria config básico se não existir
        await _db.collection('lojas').doc(lojaId).set({
          'lojaId': lojaId,
          'nome': 'Minha Loja',
          'ativa': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        synced++;
        debugPrint('✅ [CONFIG] Config básico criado');
      } else {
        debugPrint('ℹ️ [CONFIG] Config já existe, não sobrescrito');
      }

    } catch (e) {
      debugPrint('❌ [CONFIG] Erro (type=${e.runtimeType})');
      errors++;
    }

    return {'synced': synced, 'errors': errors};
  }

  /// Limpa dados de TESTE do Firestore (usar com cuidado!)
  static Future<void> limparDadosTeste(String lojaId) async {
    debugPrint('⚠️ [SYNC-SCRIPT] LIMPANDO DADOS DE TESTE...');

    try {
      final collections = ['produtos', 'clientes', 'vendas', 'categorias', 'fornecedores'];

      for (final collectionName in collections) {
        final snapshot = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(collectionName)
            .get();

        debugPrint('🗑️ [LIMPAR] $collectionName: ${snapshot.docs.length} docs');

        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      debugPrint('✅ [LIMPAR] Dados de teste removidos');

    } catch (e) {
      debugPrint('❌ [LIMPAR] Erro (type=${e.runtimeType})');
    }
  }

  /// Sincroniza APENAS produtos (útil para atualizações rápidas)
  static Future<void> syncApenasProdutos() async {
    debugPrint('📦 [SYNC-QUICK] Sincronizando apenas produtos...');

    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      debugPrint('❌ [SYNC-QUICK] LojaId vazio');
      return;
    }

    await _syncProdutos(lojaId);
  }

  /// Sincroniza APENAS vendas (útil para relatórios)
  static Future<void> syncApenasVendas() async {
    debugPrint('💰 [SYNC-QUICK] Sincronizando apenas vendas...');

    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      debugPrint('❌ [SYNC-QUICK] LojaId vazio');
      return;
    }

    await _syncVendas(lojaId);
  }

  /// Retorna estatísticas da sincronização
  static Future<Map<String, dynamic>> getEstatisticas(String lojaId) async {
    final stats = <String, dynamic>{};

    try {
      // Produtos
      final produtosSnap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .get();
      stats['produtos'] = produtosSnap.docs.length;

      // Clientes
      final clientesSnap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('clientes')
          .get();
      stats['clientes'] = clientesSnap.docs.length;

      // Vendas (path correto: estoque_vendas)
      final vendasSnap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueVendasCol)
          .get();
      stats['vendas'] = vendasSnap.docs.length;

      // Categorias
      final categoriasSnap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('categorias')
          .get();
      stats['categorias'] = categoriasSnap.docs.length;

      debugPrint('📊 [STATS] Firestore - Produtos: ${stats['produtos']}, Clientes: ${stats['clientes']}, Vendas: ${stats['vendas']}');

    } catch (e) {
      debugPrint('❌ [STATS] Erro (type=${e.runtimeType})');
    }

    return stats;
  }
}
