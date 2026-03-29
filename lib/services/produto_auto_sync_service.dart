// lib/services/produto_auto_sync_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../models/produto.dart';
import 'catalogo_sync_service.dart';
import 'catalog_cache_service.dart';
import 'produto_remote_sync_guard.dart';
import 'produtos_firestore_service.dart';
import 'store_resolver_facade.dart';

/// Serviço que monitora mudanças no box de produtos e sincroniza automaticamente
/// com o catálogo no Firestore
class ProdutoAutoSyncService {
  static final ProdutoAutoSyncService _instance = ProdutoAutoSyncService._internal();
  factory ProdutoAutoSyncService() => _instance;
  ProdutoAutoSyncService._internal();

  StreamSubscription<BoxEvent>? _subscription;
  Timer? _debounceTimer;
  final Set<String> _pendingProductKeys = {};
  bool _isRunning = false;
  /// Usa [ProdutoRemoteSyncGuard] (evita loop: sync Firestore→Hive dispara AUTO-SYNC).

  /// Inicia o monitoramento automático de mudanças no box de produtos
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('⚠️ [AUTO-SYNC] Já está rodando');
      return;
    }

    try {
      // Resolve a loja atual (vazio é esperado na tela de login — não logar como erro)
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        return; // esperado na tela de login — sem log para não poluir console
      }

      final boxName = HiveBoxNames.produtos(lojaId);
      final box = await Hive.openBox<Produto>(boxName);

      debugPrint('✅ [AUTO-SYNC] Iniciando monitoramento no box: $boxName');

      // Monitora eventos do box (put, delete)
      _subscription = box.watch().listen(_handleBoxEvent);
      _isRunning = true;

      debugPrint('🟢 [AUTO-SYNC] Serviço iniciado com sucesso');
    } catch (e) {
      debugPrint('❌ [AUTO-SYNC] Erro ao iniciar (type=${e.runtimeType})');
    }
  }

  /// Para o monitoramento
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingProductKeys.clear();
    _isRunning = false;
    debugPrint('🔴 [AUTO-SYNC] Serviço parado');
  }

  /// Chamar antes/depois de syncFirestoreToHive para evitar loop ( Firestore→Hive dispara box.watch).
  @Deprecated('Use ProdutoRemoteSyncGuard.applyingRemoteToHive')
  static void setApplyingRemoteSync(bool value) {
    ProdutoRemoteSyncGuard.applyingRemoteToHive = value;
  }

  /// Trata eventos do Hive box
  void _handleBoxEvent(BoxEvent event) {
    if (ProdutoRemoteSyncGuard.applyingRemoteToHive) {
      return;
    }

    final key = event.key.toString();

    if (event.deleted) {
      debugPrint('🗑️ [AUTO-SYNC] Produto deletado: $key');
      _scheduleSyncDeletion(key);
    } else {
      final produto = event.value as Produto?;
      if (produto != null) {
        final isNew = !_pendingProductKeys.contains(key);
        if (isNew) debugPrint('📝 [AUTO-SYNC] Produto modificado: ${produto.nome} (key: $key)');
        _scheduleSync(key, produto);
      }
    }
  }

  /// Agenda sincronização com debounce (evita sync excessivo)
  void _scheduleSync(String key, Produto produto) {
    _pendingProductKeys.add(key);

    // Cancela timer anterior
    _debounceTimer?.cancel();

    // Agenda novo sync após 1 segundo de inatividade (era 2s)
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _executePendingSyncs();
    });
  }

  /// Agenda deleção com debounce
  void _scheduleSyncDeletion(String key) {
    _pendingProductKeys.add('DELETE:$key');

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _executePendingSyncs();
    });
  }

  /// Executa todas as sincronizações pendentes
  Future<void> _executePendingSyncs() async {
    if (_pendingProductKeys.isEmpty) return;

    final keys = List<String>.from(_pendingProductKeys);
    _pendingProductKeys.clear();

    debugPrint('🔄 [AUTO-SYNC] Executando sync de ${keys.length} produto(s)...');

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) return;

      final boxName = HiveBoxNames.produtos(lojaId);
      final box = await Hive.openBox<Produto>(boxName);

      for (final key in keys) {
        // Se é uma deleção
        if (key.startsWith('DELETE:')) {
          final originalKey = key.replaceFirst('DELETE:', '');
          await _syncDeletion(originalKey, lojaId);
          continue;
        }

        // Sincronização normal
        final produto = box.get(key);
        if (produto != null) {
          await _syncProduto(produto, lojaId);
        }
      }

      debugPrint('✅ [AUTO-SYNC] Sync concluído');
    } catch (e) {
      debugPrint('❌ [AUTO-SYNC] Erro ao executar sync (type=${e.runtimeType})');
    }
  }

  /// Sincroniza um produto individual
  Future<void> _syncProduto(Produto produto, String lojaId) async {
    try {
      debugPrint('📤 [AUTO-SYNC] Sincronizando: ${produto.nome}');

      // Sempre refletir Hive em estoque_produtos (peso, custo, etc.). Antes só o catálogo era atualizado.
      try {
        await ProdutosFirestoreService.syncProduto(
          produto,
          lojaId: lojaId,
          bumpHiveTimestamp: false,
        );
      } catch (e) {
        debugPrint(
          '❌ [AUTO-SYNC] Falha em estoque_produtos (type=${e.runtimeType})',
        );
      }

      // Determina o target baseado no estado do produto
      final target = produto.ativoNoRascunho ? SyncTarget.draft : SyncTarget.live;

      // ✅ VERIFICAR SE DEVE EXISTIR NO CATÁLOGO
      final deveExistir = produto.quantidade > 0 &&
                          produto.publicadoNoCatalogo;

      debugPrint('📊 [AUTO-SYNC] Target: $target');
      debugPrint('📊 [AUTO-SYNC] Publicado: ${produto.publicadoNoCatalogo}');
      debugPrint('📊 [AUTO-SYNC] Quantidade: ${produto.quantidade}');
      debugPrint('📊 [AUTO-SYNC] DeveExistir: $deveExistir');

      if (!deveExistir) {
        // ❌ REMOVER DO CATÁLOGO SE NÃO DEVE EXISTIR
        debugPrint('🗑️ [AUTO-SYNC] Produto não deve existir no catálogo, removendo...');

        // Remove de draft e live
        await CatalogoSyncService.removeProdutoFromFirestore(
          produto,
          target: SyncTarget.draft,
          lojaIdOverride: lojaId,
        );
        await CatalogoSyncService.removeProdutoFromFirestore(
          produto,
          target: SyncTarget.live,
          lojaIdOverride: lojaId,
        );

        CatalogCacheService.invalidate(lojaId, preview: false);
        CatalogCacheService.invalidate(lojaId, preview: true);

        debugPrint('✅ [AUTO-SYNC] Produto removido do catálogo');
        return;
      }

      // ✅ Adicionar/atualizar normalmente
      await CatalogoSyncService.syncProduto(
        produto,
        target: target,
        lojaIdOverride: lojaId,
      );

      debugPrint('✅ [AUTO-SYNC] ${produto.nome} sincronizado');
    } catch (e) {
      debugPrint('❌ [AUTO-SYNC] Erro ao sync produto (type=${e.runtimeType})');
    }
  }

  /// Remove produto deletado do Firestore
  Future<void> _syncDeletion(String productKey, String lojaId) async {
    try {
      debugPrint('🗑️ [AUTO-SYNC] Removendo do Firestore: $productKey');

      // Remove de draft e live
      await CatalogoSyncService.removeProdutoByKey(
        productKey,
        lojaId: lojaId,
      );

      debugPrint('✅ [AUTO-SYNC] Produto removido do Firestore');
    } catch (e) {
      debugPrint('❌ [AUTO-SYNC] Erro ao remover (type=${e.runtimeType})');
    }
  }

  /// Força sincronização imediata de um produto específico
  Future<void> syncNow(Produto produto) async {
    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) return;

      await _syncProduto(produto, lojaId);
    } catch (e) {
      debugPrint('❌ [AUTO-SYNC] Erro ao sync imediato (type=${e.runtimeType})');
    }
  }

  /// Força sincronização de todos os produtos pendentes
  Future<void> syncPendingNow() async {
    _debounceTimer?.cancel();
    await _executePendingSyncs();
  }
}
