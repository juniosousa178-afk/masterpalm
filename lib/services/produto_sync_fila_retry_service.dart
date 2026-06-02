// Retentativa de sync de produto após processar a fila Hive (cadastro / edição).

import 'produtos_firestore_service.dart';
import 'sync_queue_service.dart';
import '../models/produto.dart';

/// Garante que itens enfileirados por falha transitória sejam processados antes de desistir.
class ProdutoSyncFilaRetryService {
  ProdutoSyncFilaRetryService._();

  /// Sincroniza com Firestore; se cair na fila ou falhar sem ACK, esvazia a fila e tenta de novo.
  static Future<ProdutoSyncRemotoStatus> syncComRetentativaFila(
    Produto produto, {
    required String lojaId,
    bool bumpHiveTimestamp = true,
    bool enqueueOnFailure = true,
  }) async {
    var status = await ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      bumpHiveTimestamp: bumpHiveTimestamp,
      enqueueOnFailure: enqueueOnFailure,
    );

    if (!_precisaRetentativaFila(status)) {
      return status;
    }

    await SyncQueueService.processPending();

    return ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      bumpHiveTimestamp: false,
      enqueueOnFailure: enqueueOnFailure,
    );
  }

  static bool _precisaRetentativaFila(ProdutoSyncRemotoStatus status) =>
      status == ProdutoSyncRemotoStatus.pendenteFila ||
      status == ProdutoSyncRemotoStatus.falhaRemota;
}
