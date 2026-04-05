// lib/services/produto_exclusao_remota_service.dart
// Camada única para remoção remota na exclusão de produto (catálogo canônico + estoque + imagens).

import '../core/logger.dart';
import '../models/produto.dart';
import 'catalog_cache_service.dart';
import 'catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import 'produto_imagens_storage_cleanup.dart';
import 'produtos_firestore_service.dart';

/// Exclusão remota coerente entre fluxos de estoque (soft delete e v2).
class ProdutoExclusaoRemotaService {
  ProdutoExclusaoRemotaService._();

  static void _invalidarCacheCatalogo(String lojaId) {
    try {
      CatalogCacheService.invalidate(lojaId, preview: true);
      CatalogCacheService.invalidate(lojaId, preview: false);
    } catch (_) {}
  }

  /// Fase imediata do **soft delete**: remove `draft_produtos` e `produtos` pelo doc canônico.
  /// Não apaga `estoque_produtos` nem imagens (permite desfazer).
  static Future<void> removerCatalogoParaProdutoRemovidoDoHive({
    required Produto produto,
    required String lojaId,
  }) async {
    if (lojaId.isEmpty) return;
    try {
      await CatalogoSyncService.removeProdutoFromFirestore(
        produto,
        target: SyncTarget.draft,
        lojaIdOverride: lojaId,
      );
    } catch (e, st) {
      logE(
        '[EXCLUSAO_REMOTA] Falha ao remover draft_produtos',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
    try {
      await CatalogoSyncService.removeProdutoFromFirestore(
        produto,
        target: SyncTarget.live,
        lojaIdOverride: lojaId,
      );
    } catch (e, st) {
      logE(
        '[EXCLUSAO_REMOTA] Falha ao remover produtos (live)',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
    _invalidarCacheCatalogo(lojaId);
  }

  /// Exclusão permanente (após janela de undo) ou fluxo sem soft delete: imagens + `estoque_produtos`.
  /// Catálogo já deve ter sido removido na fase imediata do soft delete; chamadas repetidas são idempotentes.
  static Future<void> apagarImagensEEstoqueRemoto({
    required Produto produto,
    required String lojaId,
  }) async {
    if (lojaId.isEmpty) return;
    await ProdutoImagensStorageCleanup.apagarTodasImagensGerenciadasDoProduto(
      produto,
      lojaId,
    );
    try {
      await ProdutosFirestoreService.deleteProdutoRobusto(
        produto: produto,
        lojaId: lojaId,
      );
    } catch (e, st) {
      logE(
        '[EXCLUSAO_REMOTA] Falha deleteProdutoRobusto',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
  }

  /// Fluxo **imediato** (ex.: estoque v2): catálogo canônico + imagens + estoque, sem alterar Hive.
  static Future<void> exclusaoRemotaCompletaImediata({
    required Produto produto,
    required String lojaId,
  }) async {
    await removerCatalogoParaProdutoRemovidoDoHive(
      produto: produto,
      lojaId: lojaId,
    );
    await apagarImagensEEstoqueRemoto(produto: produto, lojaId: lojaId);
  }
}
