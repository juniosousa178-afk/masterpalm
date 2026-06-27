// Pós-save do cadastro: sync draft/live com registro de falha + reidratação Hive.

import '../core/produto_form_grade_hydration.dart';
import '../models/produto.dart';
import 'catalogo_sync_attempt_context.dart';
import 'catalog_publish_service.dart';
import 'catalogo_sync_service.dart';
import 'produto_catalogo_upsert_falha.dart';
import 'produtos_firestore_service.dart';

/// Fluxo compartilhado após estoque remoto OK (botão Salvar / persistir).
class ProdutoCadastroPosSaveService {
  ProdutoCadastroPosSaveService._();

  /// Sincroniza draft/live (sem propagar exceção), marca catálogo e reidrata Hive.
  static Future<ProdutoRehydratePosSaveResult?> executarAposEstoqueRemotoOk({
    required Produto produto,
    required String lojaId,
    required ProdutoSyncRemotoStatus remoteStatus,
    ProdutoFormGradeBaseline? gradeBaseline,
    CatalogoSyncAttemptContext? catalogoDiagContext,
  }) async {
    if (remoteStatus != ProdutoSyncRemotoStatus.confirmado &&
        remoteStatus != ProdutoSyncRemotoStatus.semMudancas) {
      return null;
    }

    await CatalogoSyncService.upsertFromProdutoRegistrandoFalha(
      produto,
      target: SyncTarget.draft,
      lojaIdOverride: lojaId,
      catalogoDiagContext: catalogoDiagContext,
    );
    await CatalogoSyncService.upsertFromProdutoRegistrandoFalha(
      produto,
      target: SyncTarget.live,
      lojaIdOverride: lojaId,
      catalogoDiagContext: catalogoDiagContext,
    );
    await CatalogPublishService.marcarCatalogoPrecisaAtualizar();

    if (remoteStatus != ProdutoSyncRemotoStatus.confirmado) {
      return null;
    }

    return ProdutosFirestoreService.rehydrateProdutoConfirmadoFromEstoqueRemoto(
      produto,
      lojaId: lojaId,
      gradeBaseline: gradeBaseline,
    );
  }

  static bool estoqueSalvoComSucesso(ProdutoSyncRemotoStatus status) =>
      status == ProdutoSyncRemotoStatus.confirmado ||
      status == ProdutoSyncRemotoStatus.semMudancas;
}
