// List / pull convergence: when remote estoque_produtos is authoritative,
// a stale or partial Hive grade must not remain sticky on the product list.
//
// Stock authority remains nested `variacoes` cells. `estoquePorTamanho` is
// projection only and must never resurrect qty absent from remote variacoes.

import '../models/produto.dart';
import 'hive_box_names.dart';
import 'produto_estoque_grade_snapshot.dart';
import 'produto_stock_revision.dart';

export 'produto_estoque_grade_snapshot.dart' show PullStockMergeDecision;

/// List / cloud pull: accept authoritative remote grade unless local revision
/// is strictly newer or a pending stock conflict blocks merge.
bool shouldAcceptRemoteGradeOnAuthoritativeListPull({
  required Produto local,
  required Map<String, dynamic> remoteData,
}) {
  final remoteRev = parseStockRevisionFromRemote(remoteData);
  final localRev = local.stockRevision;

  if (hasPendingStockMutation(local) &&
      shouldMarkStockConflictOnPull(local: local, remoteData: remoteData)) {
    return false;
  }
  if (remoteRev < localRev) {
    return false;
  }
  return true;
}

/// Whether syncFirestoreToHive (list path) should preserve local stock grade.
bool shouldPreserveLocalGradeOnListPull({
  required Produto local,
  required Map<String, dynamic> remoteData,
  required bool preferRemoteQuantity,
}) {
  if (preferRemoteQuantity) {
    return !shouldAcceptRemoteGradeOnAuthoritativeListPull(
      local: local,
      remoteData: remoteData,
    );
  }
  return evaluatePullStockMergeByRevision(
        local: local,
        remoteData: remoteData,
      ) ==
      PullStockMergeDecision.preserveLocalGrade;
}

/// Guard: abort applying a pull batch if the Hive box was closed or swapped.
bool listPullTargetStillValid({
  required bool produtosBoxIsOpen,
  required String produtosBoxName,
  required String boxNameAtSyncStart,
}) {
  if (!produtosBoxIsOpen) return false;
  if (boxNameAtSyncStart.isEmpty) return false;
  return produtosBoxName == boxNameAtSyncStart;
}

/// Store-scoped box naming helper for callers / tests.
bool listPullBoxMatchesStoreConvention({
  required String lojaId,
  required String produtosBoxName,
}) {
  if (lojaId.trim().isEmpty) return false;
  return produtosBoxName == HiveBoxNames.produtos(lojaId);
}

/// Convenience for tests / diagnostics.
bool remoteGradeIsStrictlyMoreCompleteThan({
  required ProdutoEstoqueGradeSnapshot local,
  required ProdutoEstoqueGradeSnapshot remote,
}) =>
    remote.isStrictlyMoreCompleteThan(local);
