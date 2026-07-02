import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_transaction_port.dart';

/// Implementação Cloud Firestore da porta transacional R2-A.
class PdvV1CloudFirestoreRemoteStockMarkerPort
    implements PdvV1RemoteStockMarkerTransactionPort {
  PdvV1CloudFirestoreRemoteStockMarkerPort(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<PdvV1RemoteStockMarkerApplyOutcome> runAtomicApply({
    required PdvV1RemoteStockMarkerPlan plan,
    required Future<PdvV1RemoteStockMarkerApplyOutcome> Function(
      PdvV1RemoteStockMarkerTransactionReadWrite txn,
    ) body,
  }) {
    return _firestore.runTransaction((transaction) async {
      final txn = _CloudFirestoreTxn(_firestore, transaction);
      return body(txn);
    });
  }
}

class _CloudFirestoreTxn implements PdvV1RemoteStockMarkerTransactionReadWrite {
  _CloudFirestoreTxn(this._firestore, this._transaction);

  final FirebaseFirestore _firestore;
  final Transaction _transaction;

  DocumentReference<Map<String, dynamic>> _markerRef(
    String lojaId,
    String operationId,
  ) {
    return _firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(pdvV1RemoteMarkerCollectionSegment)
        .doc(operationId);
  }

  DocumentReference<Map<String, dynamic>> _stockRef(
    String lojaId,
    String stockDocumentId,
  ) {
    return _firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(pdvV1RemoteStockCollectionSegment)
        .doc(stockDocumentId);
  }

  @override
  Future<Map<String, dynamic>?> readMarker({
    required String lojaId,
    required String operationId,
  }) async {
    final snap = await _transaction.get(_markerRef(lojaId, operationId));
    if (!snap.exists) return null;
    return snap.data();
  }

  @override
  Future<Map<String, dynamic>?> readStock({
    required String lojaId,
    required String stockDocumentId,
  }) async {
    final snap = await _transaction.get(_stockRef(lojaId, stockDocumentId));
    if (!snap.exists) return null;
    return snap.data();
  }

  @override
  void writeStockQuantity({
    required String lojaId,
    required String stockDocumentId,
    required String quantityField,
    required int newQuantity,
  }) {
    _transaction.update(_stockRef(lojaId, stockDocumentId), {
      quantityField: newQuantity,
    });
  }

  @override
  void writeMarker({
    required String lojaId,
    required String operationId,
    required Map<String, dynamic> markerData,
  }) {
    _transaction.set(_markerRef(lojaId, operationId), markerData);
  }
}
