// lib/services/produto_exclusao_remota_service.dart
// Camada única para remoção remota na exclusão de produto (catálogo canônico + estoque + imagens).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import '../models/produto.dart';
import 'catalog_cache_service.dart';
import 'catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import 'firestore_paths.dart';
import 'produto_imagens_storage_cleanup.dart';
import 'produtos_firestore_service.dart';

enum ProdutoExclusaoRemotaStatus {
  confirmada,
  pendente,
}

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

  /// Marca o doc em `estoque_produtos` como soft delete pendente (não apaga o doc — permite desfazer).
  /// [syncFirestoreToHive] ignora docs assim para não recriar o item no Hive durante a janela de undo.
  static Future<void> marcarEstoqueProdutoPendenteSoftDelete({
    required Produto produto,
    required String lojaId,
  }) async {
    final id = produto.idFirebase.trim();
    if (lojaId.isEmpty || id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set(
            {
              ProdutosFirestoreService.fieldEstoquePendingSoftDelete: true,
              ProdutosFirestoreService.fieldEstoquePendingSoftDeleteAt:
                  FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (e, st) {
      logE(
        '[EXCLUSAO_REMOTA] Falha ao marcar pendingSoftDelete em estoque_produtos',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
  }

  /// Remove o tombstone de soft delete após desfazer a exclusão.
  static Future<void> limparEstoquePendenteSoftDelete({
    required String lojaId,
    required String produtoIdFirebase,
  }) async {
    final id = produtoIdFirebase.trim();
    if (lojaId.isEmpty || id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .update({
            ProdutosFirestoreService.fieldEstoquePendingSoftDelete:
                FieldValue.delete(),
            ProdutosFirestoreService.fieldEstoquePendingSoftDeleteAt:
                FieldValue.delete(),
          });
    } catch (e, st) {
      logW(
        '[EXCLUSAO_REMOTA] limpar pendingSoftDelete (doc pode não existir): '
        'type=${e.runtimeType} $st',
        tag: 'EXCLUSAO',
      );
    }
  }

  /// Exclusão permanente (após janela de undo) ou fluxo sem soft delete: imagens + `estoque_produtos`.
  /// Catálogo já deve ter sido removido na fase imediata do soft delete; chamadas repetidas são idempotentes.
  static Future<ProdutoExclusaoRemotaStatus> apagarImagensEEstoqueRemotoComStatus({
    required Produto produto,
    required String lojaId,
  }) async {
    if (lojaId.isEmpty) return ProdutoExclusaoRemotaStatus.pendente;
    var ok = true;
    try {
      await ProdutoImagensStorageCleanup.apagarTodasImagensGerenciadasDoProduto(
        produto,
        lojaId,
      );
    } catch (e, st) {
      ok = false;
      logE(
        '[EXCLUSAO_REMOTA] Falha ao apagar imagens gerenciadas',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
    try {
      await ProdutosFirestoreService.deleteProdutoRobusto(
        produto: produto,
        lojaId: lojaId,
      );
    } catch (e, st) {
      ok = false;
      logE(
        '[EXCLUSAO_REMOTA] Falha deleteProdutoRobusto',
        tag: 'EXCLUSAO',
        error: e,
        st: st,
      );
    }
    return ok
        ? ProdutoExclusaoRemotaStatus.confirmada
        : ProdutoExclusaoRemotaStatus.pendente;
  }

  static Future<void> apagarImagensEEstoqueRemoto({
    required Produto produto,
    required String lojaId,
  }) async {
    await apagarImagensEEstoqueRemotoComStatus(
      produto: produto,
      lojaId: lojaId,
    );
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
