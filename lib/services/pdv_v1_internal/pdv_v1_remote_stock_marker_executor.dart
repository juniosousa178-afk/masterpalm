import 'pdv_v1_remote_stock_marker_models.dart';
import 'pdv_v1_remote_stock_marker_transaction_port.dart';

/// Executor atômico R2-A — sem Firebase, Hive, journal ou retry próprio.
class PdvV1RemoteStockMarkerExecutor {
  PdvV1RemoteStockMarkerExecutor(this._port);

  final PdvV1RemoteStockMarkerTransactionPort _port;

  Future<PdvV1RemoteStockMarkerApplyResult> applyOnce(
    PdvV1RemoteStockMarkerPlan plan,
  ) async {
    try {
      final outcome = await _port.runAtomicApply(
        plan: plan,
        body: (txn) => _applyWithinTransaction(plan, txn),
      );
      return PdvV1RemoteStockMarkerApplyResult(outcome: outcome);
    } catch (_) {
      return const PdvV1RemoteStockMarkerApplyResult(
        outcome:
            PdvV1RemoteStockMarkerApplyOutcome.remoteTransactionUnavailable,
      );
    }
  }

  Future<PdvV1RemoteStockMarkerApplyOutcome> _applyWithinTransaction(
    PdvV1RemoteStockMarkerPlan plan,
    PdvV1RemoteStockMarkerTransactionReadWrite txn,
  ) async {
    final markerRaw = await txn.readMarker(
      lojaId: plan.lojaId,
      operationId: plan.operationId,
    );

    final markerCompat = plan.evaluateExistingMarker(markerRaw);
    if (markerCompat == PdvV1RemoteMarkerCompatibility.compatible) {
      return PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied;
    }
    if (markerCompat == PdvV1RemoteMarkerCompatibility.incompatible) {
      return PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict;
    }

    final stockRaw = await txn.readStock(
      lojaId: plan.lojaId,
      stockDocumentId: plan.stockDocumentId,
    );

    final stockValidation = validateStockQuantityField(
      stockDocument: stockRaw,
      quantityField: plan.stockQuantityField,
      quantityToDebit: plan.quantityToDebit,
    );

    switch (stockValidation) {
      case PdvV1RemoteStockQuantityValidation.valid:
        break;
      case PdvV1RemoteStockQuantityValidation.insufficient:
        return PdvV1RemoteStockMarkerApplyOutcome.insufficientStock;
      case PdvV1RemoteStockQuantityValidation.documentAbsent:
      case PdvV1RemoteStockQuantityValidation.fieldAbsent:
      case PdvV1RemoteStockQuantityValidation.fieldNotInt:
      case PdvV1RemoteStockQuantityValidation.fieldNegative:
        return PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid;
    }

    final currentQty = stockRaw![plan.stockQuantityField]! as int;
    final newQty = currentQty - plan.quantityToDebit;

    txn.writeStockQuantity(
      lojaId: plan.lojaId,
      stockDocumentId: plan.stockDocumentId,
      quantityField: plan.stockQuantityField,
      newQuantity: newQty,
    );

    txn.writeMarker(
      lojaId: plan.lojaId,
      operationId: plan.operationId,
      markerData: plan.toRemoteMarkerMap(),
    );

    return PdvV1RemoteStockMarkerApplyOutcome.applied;
  }
}
