// lib/services/full_sync_service.dart
// ✅ Serviço de sincronização completa para garantir dados consistentes entre celulares

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import 'firestore_paths.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import 'produto_auto_sync_service.dart';
import 'importar_vendas_firestore_service.dart';
import 'store_resolver_facade.dart';

class FullSyncService {
  FullSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ✅ Executa sincronização COMPLETA ao fazer login
  /// Deve ser chamado após login bem-sucedido
  static Future<SyncResult> syncInicialCompleto() async {
    final result = SyncResult();

    try {
      logD('═══════════════════════════════════════════════════════════');
      logD('🔄 [FULL-SYNC] INICIANDO SINCRONIZAÇÃO COMPLETA');
      logD('═══════════════════════════════════════════════════════════');

      // 1. Resolver loja do usuário
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        result.erro = 'Nenhuma loja encontrada para este usuário';
        logD('❌ [FULL-SYNC] Erro: ${result.erro}');
        return result;
      }

      logD('🎯 [FULL-SYNC] Loja ok');

      // 2. Limpar cache local antigo (se existir de outra conta)
      await _limparCacheAntigo(lojaId);

      // 3. Sincronizar produtos do Firestore para Hive
      result.produtosSincronizados = await _syncProdutos(lojaId);

      // 4. Sincronizar clientes
      result.clientesSincronizados = await _syncClientes(lojaId);

      // 5. Sincronizar vendas (Firestore → Hive)
      result.vendasSincronizadas = await _syncVendas(lojaId);

      result.sucesso = true;
      logD('═══════════════════════════════════════════════════════════');
      logD('✅ [FULL-SYNC] SINCRONIZAÇÃO COMPLETA FINALIZADA');
      logD('   Produtos: ${result.produtosSincronizados}');
      logD('   Clientes: ${result.clientesSincronizados}');
      logD('   Vendas: ${result.vendasSincronizadas}');
      logD('═══════════════════════════════════════════════════════════');

    } catch (e, st) {
      result.erro = e.toString();
      logE('❌ [FULL-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    }

    return result;
  }

  /// Limpa cache local que pode ser de outra conta
  static Future<void> _limparCacheAntigo(String lojaIdAtual) async {
    try {
      logD('🗑️ [FULL-SYNC] Verificando cache local...');

      // Verificar se o cache é da loja correta
      final sessaoBox = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      final cachedLojaId = sessaoBox.get('last_synced_loja_id');

      if (cachedLojaId != null && cachedLojaId != lojaIdAtual) {
        logW('⚠️ [FULL-SYNC] Cache de loja diferente detectado');
        logD('🗑️ [FULL-SYNC] Limpando boxes antigas...');

        // Limpar conteúdo das boxes antigas (evita HiveError ao fechar box ainda referenciada)
        final boxesToClear = [HiveBoxNames.produtos(cachedLojaId), HiveBoxNames.clientes(cachedLojaId)];
        for (final boxName in boxesToClear) {
          try {
            if (Hive.isBoxOpen(boxName)) {
              final box = Hive.box(boxName);
              await box.clear();
              logD('🧹 [SYNC] Box limpa ao trocar de loja (box=$boxName, lojaAntiga=$cachedLojaId, lojaAtual=$lojaIdAtual)');
            }
          } catch (e) {
            logD('⚠️ [SYNC] Erro ao limpar box ao trocar de loja (box=$boxName, type=${e.runtimeType}) – ignorando.');
          }
        }
      }

      // Atualizar loja atual no cache
      await sessaoBox.put('last_synced_loja_id', lojaIdAtual);
      await sessaoBox.put('last_sync_timestamp', DateTime.now().toIso8601String());

      logD('✅ [FULL-SYNC] Cache verificado');
    } catch (e) {
      logW('⚠️ [FULL-SYNC] Erro ao limpar cache (type=${e.runtimeType})');
    }
  }

  /// Sincroniza TODOS os produtos do Firestore para o Hive (com paginação)
  static Future<int> _syncProdutos(String lojaId) async {
    ProdutoAutoSyncService.setApplyingRemoteSync(true);
    try {
      logD('📦 [FULL-SYNC] Sincronizando produtos...');

      final boxName = HiveBoxNames.produtos(lojaId);
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Produto>(boxName);
      }
      final box = Hive.box<Produto>(boxName);

      // Buscar TODOS os produtos do Firestore (paginado)
      int totalSincronizados = 0;
      const int pageSize = 500;
      DocumentSnapshot? lastDoc;
      bool hasMore = true;

      while (hasMore) {
        Query query = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .orderBy('nome')
            .limit(pageSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snapshot = await query.get();

        if (snapshot.docs.isEmpty) {
          hasMore = false;
          continue;
        }

        for (final doc in snapshot.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final produto = _produtoFromFirestore(data, doc.id);

            // Verificar se já existe pelo idFirebase ou slug (whereType evita crash por typeId inválido)
            final candidatos = box.values.whereType<Produto>().where(
                (p) => p.idFirebase == doc.id || p.slug == produto.slug);
            final existente = candidatos.isEmpty ? null : candidatos.first;

            if (existente != null) {
              // Atualizar existente
              existente
                ..nome = produto.nome
                ..descricao = produto.descricao
                ..precoFinal = produto.precoFinal
                ..quantidade = produto.quantidade
                ..categoria = produto.categoria
                ..subcategoria = produto.subcategoria
                ..imagens = produto.imagens
                ..tamanhos = produto.tamanhos
                ..estoquePorTamanho = produto.estoquePorTamanho
                ..cores = produto.cores
                ..variacoes = produto.variacoes
                ..publicadoNoCatalogo = produto.publicadoNoCatalogo
                ..idFirebase = doc.id;
              await existente.save();
            } else {
              // Adicionar novo
              produto.idFirebase = doc.id;
              await box.add(produto);
            }

            totalSincronizados++;
          } catch (e) {
            logW('⚠️ [FULL-SYNC] Erro ao processar produto (type=${e.runtimeType})');
          }
        }

        lastDoc = snapshot.docs.last;
        hasMore = snapshot.docs.length == pageSize;

        logD('📦 [FULL-SYNC] Lote processado: ${snapshot.docs.length} produtos');
      }

      logD('✅ [FULL-SYNC] Produtos sincronizados: $totalSincronizados');
      return totalSincronizados;

    } catch (e, st) {
      logE('❌ [FULL-SYNC] Erro ao sincronizar produtos (type=${e.runtimeType})', error: e, st: st);
      return 0;
    } finally {
      ProdutoAutoSyncService.setApplyingRemoteSync(false);
    }
  }

  /// Sincroniza TODOS os clientes do Firestore para o Hive
  static Future<int> _syncClientes(String lojaId) async {
    try {
      logD('👥 [FULL-SYNC] Sincronizando clientes...');

      final boxName = HiveBoxNames.clientes(lojaId);
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Cliente>(boxName);
      }
      final box = Hive.box<Cliente>(boxName);

      // Buscar todos os clientes
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueClientesCol)
          .get();

      int totalSincronizados = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final cliente = Cliente(
            nome: data['nome']?.toString() ?? '',
            telefone: data['telefone']?.toString() ?? '',
            instagram: data['instagram']?.toString() ?? '',
            cep: data['cep']?.toString() ?? '',
            cidade: data['cidade']?.toString() ?? '',
            email: data['email']?.toString(),
            endereco: data['endereco']?.toString(),
            lojaId: lojaId,
          );

          // Verificar duplicidade (whereType evita crash por typeId inválido)
          final candidatos = box.values.whereType<Cliente>().where((c) =>
              c.telefone == cliente.telefone || c.email == cliente.email);
          final existente = candidatos.isEmpty ? null : candidatos.first;

          if (existente == null && cliente.nome.isNotEmpty) {
            await box.add(cliente);
            totalSincronizados++;
          }
        } catch (e) {
          logW('⚠️ [FULL-SYNC] Erro ao processar cliente (type=${e.runtimeType})');
        }
      }

      logD('✅ [FULL-SYNC] Clientes sincronizados: $totalSincronizados');
      return totalSincronizados;

    } catch (e, st) {
      logE('❌ [FULL-SYNC] Erro ao sincronizar clientes (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Sincroniza vendas do Firestore para o Hive (login em novo dispositivo)
  static Future<int> _syncVendas(String lojaId) async {
    try {
      logD('💰 [FULL-SYNC] Sincronizando vendas...');

      final boxName = HiveBoxNames.vendas(lojaId);
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Venda>(boxName);
      }
      final box = Hive.box<Venda>(boxName);

      final resultado = await ImportarVendasFirestoreService.importar(
        lojaId: lojaId,
        vendasBox: box,
      );

      logD('✅ [FULL-SYNC] Vendas: ${resultado.importadas} importadas (${resultado.jaExistentes} já existiam)');
      return resultado.importadas;
    } catch (e, st) {
      logE('❌ [FULL-SYNC] Erro ao sincronizar vendas (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Converte documento Firestore para Produto
  static Produto _produtoFromFirestore(Map<String, dynamic> data, String docId) {
    final preco = (data['precoFinal'] as num?)?.toDouble() ??
                  (data['preco'] as num?)?.toDouble() ?? 0.0;
    return Produto(
      nome: data['nome']?.toString() ?? '',
      descricao: data['descricao']?.toString() ?? '',
      custoReal: (data['custoReal'] as num?)?.toDouble() ?? 0.0,
      frete: (data['frete'] as num?)?.toDouble() ?? 0.0,
      gastosFixos: (data['gastosFixos'] as num?)?.toDouble() ?? 0.0,
      gastosVariaveis: (data['gastosVariaveis'] as num?)?.toDouble() ?? 0.0,
      precoSugerido: (data['precoSugerido'] as num?)?.toDouble() ?? preco,
      precoFinal: preco,
      precoUnitario: (data['precoUnitario'] as num?)?.toDouble() ?? preco,
      quantidade: (data['quantidade'] as num?)?.toInt() ??
                  (data['estoque'] as num?)?.toInt() ?? 0,
      categoria: data['categoria']?.toString() ?? '',
      subcategoria: data['subcategoria']?.toString() ?? '',
      imagens: _parseListString(data['imagens']),
      tamanhos: _parseListString(data['tamanhos']),
      estoquePorTamanho: _parseMapStringInt(data['estoquePorTamanho']),
      cores: _parseListString(data['cores']),
      variacoes: _parseMapDynamic(data['variacoes']),
      publicadoNoCatalogo: data['publicadoNoCatalogo'] == true ||
                           data['publicar'] == true,
      divideSemJuros: data['divideSemJuros'] == true,
      maxParcelasSemJuros: (data['maxParcelasSemJuros'] is num)
          ? (data['maxParcelasSemJuros'] as num).toInt()
          : 12,
      percentualDescontoPix: (data['percentualDescontoPix'] is num)
          ? (data['percentualDescontoPix'] as num).toDouble()
          : 0.0,
      slug: data['slug']?.toString() ?? docId,
      lojaId: data['lojaId']?.toString() ?? '',
      idFirebase: docId,
      dataEntrada: DateTime.now(),
    );
  }

  static List<String> _parseListString(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static Map<String, int> _parseMapStringInt(dynamic value) {
    if (value == null) return {};
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
    }
    return {};
  }

  static Map<String, dynamic>? _parseMapDynamic(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }
}

/// Resultado da sincronização
class SyncResult {
  bool sucesso = false;
  String? erro;
  int produtosSincronizados = 0;
  int clientesSincronizados = 0;
  int vendasSincronizadas = 0;

  @override
  String toString() {
    if (sucesso) {
      return 'Sincronização OK: $produtosSincronizados produtos, $clientesSincronizados clientes, $vendasSincronizadas vendas';
    }
    return 'Erro: $erro';
  }
}
