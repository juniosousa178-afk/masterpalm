import 'pdv_v1_remote_stock_marker_models.dart';

/// Operações transacionais injetáveis para marker + estoque simples (R2-A).
abstract class PdvV1RemoteStockMarkerTransactionPort {
  Future<PdvV1RemoteStockMarkerApplyOutcome> runAtomicApply({
    required PdvV1RemoteStockMarkerPlan plan,
    required Future<PdvV1RemoteStockMarkerApplyOutcome> Function(
      PdvV1RemoteStockMarkerTransactionReadWrite txn,
    ) body,
  });
}

/// Leituras e escritas disponíveis dentro de uma transação atômica.
abstract class PdvV1RemoteStockMarkerTransactionReadWrite {
  Future<Map<String, dynamic>?> readMarker({
    required String lojaId,
    required String operationId,
  });

  Future<Map<String, dynamic>?> readStock({
    required String lojaId,
    required String stockDocumentId,
  });

  void writeStockQuantity({
    required String lojaId,
    required String stockDocumentId,
    required String quantityField,
    required int newQuantity,
  });

  void writeMarker({
    required String lojaId,
    required String operationId,
    required Map<String, dynamic> markerData,
  });
}
