// Retentativa de sync de produto após processar a fila Hive (cadastro / edição).

import 'package:flutter/foundation.dart';

import 'produtos_firestore_service.dart';
import 'sync_queue_service.dart';
import '../models/produto.dart';

/// Garante que itens enfileirados por falha transitória sejam processados antes de desistir.
class ProdutoSyncFilaRetryService {
  ProdutoSyncFilaRetryService._();

  @visibleForTesting
  static int debugProcessPendingChamadas = 0;

  /// Sincroniza com Firestore; se cair na fila ou falhar sem ACK, esvazia a fila e tenta de novo.
  static Future<ProdutoSyncRemotoStatus> syncComRetentativaFila(
    Produto produto, {
    required String lojaId,
    bool bumpHiveTimestamp = true,
    bool forcePushFromCadastro = false,
    bool enqueueOnFailure = true,
  }) async {
    var status = await ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      bumpHiveTimestamp: bumpHiveTimestamp,
      forcePushFromCadastro: forcePushFromCadastro,
      writeOrigin: forcePushFromCadastro
          ? 'produto_form.save'
          : 'produto_sync_fila_retry.primeira',
      enqueueOnFailure: enqueueOnFailure,
    );

    if (!_precisaRetentativaFila(status)) {
      return status;
    }

    debugProcessPendingChamadas++;
    await SyncQueueService.processPending();

    return ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      bumpHiveTimestamp: false,
      forcePushFromCadastro: forcePushFromCadastro,
      writeOrigin: forcePushFromCadastro
          ? 'produto_form.save_retry'
          : 'produto_sync_fila_retry.segunda',
      enqueueOnFailure: enqueueOnFailure,
    );
  }

  static bool _precisaRetentativaFila(ProdutoSyncRemotoStatus status) =>
      status == ProdutoSyncRemotoStatus.pendenteFila ||
      status == ProdutoSyncRemotoStatus.falhaRemota;

  /// Erro sanitizado da fila ou do último sync, para mensagem no cadastro.
  static Future<String?> detalheErroAposRetentativa({
    required String lojaId,
    required Produto produto,
  }) async {
    final key = produto.key;
    if (key is int) {
      final daFila = await SyncQueueService.lastProdutoSyncErrorForEntity(
        lojaId: lojaId,
        entityKey: key,
      );
      if (daFila != null && daFila.trim().isNotEmpty) return daFila.trim();
    }
    return ProdutosFirestoreService.ultimoErroSyncSanitizado?.trim();
  }
}
