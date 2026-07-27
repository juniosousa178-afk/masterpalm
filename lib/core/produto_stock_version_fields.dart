// Campos de versionamento de estoque em `estoque_produtos` (Firestore) e Hive.

/// Timestamp de servidor da última mutação de **estoque** (não nome/preço).
const String kProdutoStockUpdatedAtField = 'stockUpdatedAt';

/// Âncora Hive da última versão de estoque **confirmada pelo servidor** (pull/push).
/// Espelho diagnóstico — **não** usado para ordenar merge (R8.3 usa `stockRevision`).
const int kProdutoStockUpdatedAtServerHiveField = 49;

/// @deprecated R8.3 — não usar para ordenação. Mantido só para leitura legada.
DateTime? localStockVersionForServerCompare({
  DateTime? stockUpdatedAtServer,
  DateTime? stockUpdatedAt,
}) {
  return stockUpdatedAtServer ?? stockUpdatedAt;
}

/// @deprecated R8.3 — pendência é [hasPendingStockMutation] em `produto_stock_revision.dart`.
bool hasPendingLocalStockMutation({
  DateTime? stockUpdatedAt,
  DateTime? stockUpdatedAtServer,
  String? pendingStockOperationId,
}) {
  if (pendingStockOperationId != null &&
      pendingStockOperationId.trim().isNotEmpty) {
    return true;
  }
  return false;
}
