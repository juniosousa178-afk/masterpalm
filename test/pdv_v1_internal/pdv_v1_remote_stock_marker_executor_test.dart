import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_transaction_port.dart';

PdvV1RemoteStockMarkerPlan _plan({
  String operationId = 'op-ex-r2a-1',
  String saleId = 'sale-ex-r2a-1',
  String lojaId = 'loja-ex-r2a-1',
  String snapshotHash = 'snap-ex-r2a-1',
  String txItemsHash = 'tx-ex-r2a-1',
  String stockDocumentId = 'prod-ex-r2a-1',
  int quantityToDebit = 2,
}) {
  return PdvV1RemoteStockMarkerPlan(
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: snapshotHash,
    txItemsHash: txItemsHash,
    stockDocumentId: stockDocumentId,
    quantityToDebit: quantityToDebit,
  );
}

Map<String, dynamic> _v1MarkerFromPlan(PdvV1RemoteStockMarkerPlan plan) {
  return plan.toRemoteMarkerMap();
}

class _RecordingFakePort implements PdvV1RemoteStockMarkerTransactionPort {
  Map<String, dynamic>? marker;
  Map<String, dynamic>? stock;
  bool throwUnavailable = false;
  final reads = <String>[];
  final writes = <String>[];
  int stockQuantityAfterApply = -1;

  @override
  Future<PdvV1RemoteStockMarkerApplyOutcome> runAtomicApply({
    required PdvV1RemoteStockMarkerPlan plan,
    required Future<PdvV1RemoteStockMarkerApplyOutcome> Function(
      PdvV1RemoteStockMarkerTransactionReadWrite txn,
    ) body,
  }) async {
    if (throwUnavailable) {
      throw Exception('transaction unavailable');
    }
    return body(_FakeTxn(this));
  }
}

class _FakeTxn implements PdvV1RemoteStockMarkerTransactionReadWrite {
  _FakeTxn(this._port);

  final _RecordingFakePort _port;

  @override
  Future<Map<String, dynamic>?> readMarker({
    required String lojaId,
    required String operationId,
  }) async {
    _port.reads.add('marker:$lojaId:$operationId');
    return _port.marker == null
        ? null
        : Map<String, dynamic>.from(_port.marker!);
  }

  @override
  Future<Map<String, dynamic>?> readStock({
    required String lojaId,
    required String stockDocumentId,
  }) async {
    _port.reads.add('stock:$lojaId:$stockDocumentId');
    return _port.stock == null ? null : Map<String, dynamic>.from(_port.stock!);
  }

  @override
  void writeStockQuantity({
    required String lojaId,
    required String stockDocumentId,
    required String quantityField,
    required int newQuantity,
  }) {
    _port.writes.add('stock:$lojaId:$stockDocumentId:$newQuantity');
    _port.stock ??= {'lojaId': lojaId};
    _port.stock![quantityField] = newQuantity;
    _port.stockQuantityAfterApply = newQuantity;
  }

  @override
  void writeMarker({
    required String lojaId,
    required String operationId,
    required Map<String, dynamic> markerData,
  }) {
    _port.writes.add('marker:$lojaId:$operationId');
    _port.marker = Map<String, dynamic>.from(markerData);
  }
}

void main() {
  group('PdvV1RemoteStockMarkerExecutor R2-A', () {
    test('1. marker ausente + saldo suficiente → applied', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);
      final plan = _plan(quantityToDebit: 2);

      final result = await executor.applyOnce(plan);

      expect(result.outcome, PdvV1RemoteStockMarkerApplyOutcome.applied);
      expect(port.stockQuantityAfterApply, 3);
      expect(port.marker, _v1MarkerFromPlan(plan));
      expect(port.writes.length, 2);
    });

    test('2. marker V1 compatível → alreadyApplied, zero escrita', () async {
      final plan = _plan();
      final port = _RecordingFakePort()
        ..marker = _v1MarkerFromPlan(plan)
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(plan);

      expect(result.outcome, PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied);
      expect(port.writes, isEmpty);
      expect(
        port.reads.where((r) => r.startsWith('stock:')),
        isEmpty,
      );
    });

    test('3. marker legado existente → conflito, zero escrita', () async {
      final port = _RecordingFakePort()
        ..marker = {
          'lojaId': 'loja-ex-r2a-1',
          'baixaAplicada': false,
          'origem': 'catalogo',
        }
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict,
      );
      expect(port.writes, isEmpty);
    });

    test('4. marker V1 saleId divergente → conflito', () async {
      final plan = _plan();
      final port = _RecordingFakePort()
        ..marker = {
          ..._v1MarkerFromPlan(plan),
          'saleId': 'sale-DIVERGENTE',
        }
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(plan);

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict,
      );
      expect(port.writes, isEmpty);
    });

    test('5. marker V1 hash divergente → conflito', () async {
      final plan = _plan();
      final port = _RecordingFakePort()
        ..marker = {
          ..._v1MarkerFromPlan(plan),
          'snapshotHash': 'snap-DIVERGENTE',
        }
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(plan);

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict,
      );
      expect(port.writes, isEmpty);
    });

    test('6. marker V1 com campo extra → conflito', () async {
      final plan = _plan();
      final port = _RecordingFakePort()
        ..marker = {
          ..._v1MarkerFromPlan(plan),
          'nota': 'extra',
        }
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(plan);

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict,
      );
      expect(port.writes, isEmpty);
    });

    test('7. estoque ausente → stock_document_invalid', () async {
      final port = _RecordingFakePort();
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid,
      );
      expect(port.writes, isEmpty);
    });

    test('8. campo de estoque ausente → stock_document_invalid', () async {
      final port = _RecordingFakePort()..stock = {'nome': 'SKU'};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid,
      );
      expect(port.writes, isEmpty);
    });

    test('9. estoque decimal → stock_document_invalid', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 2.5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid,
      );
      expect(port.writes, isEmpty);
    });

    test('10. estoque negativo → stock_document_invalid', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: -1};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid,
      );
      expect(port.writes, isEmpty);
    });

    test('11. estoque insuficiente → insufficient_stock', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 1};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan(quantityToDebit: 2));

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.insufficientStock,
      );
      expect(port.writes, isEmpty);
    });

    test('12. saldo exato → zero permitido, marker criado', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 2};
      final executor = PdvV1RemoteStockMarkerExecutor(port);
      final plan = _plan(quantityToDebit: 2);

      final result = await executor.applyOnce(plan);

      expect(result.outcome, PdvV1RemoteStockMarkerApplyOutcome.applied);
      expect(port.stockQuantityAfterApply, 0);
      expect(port.marker, isNotNull);
    });

    test('13. porta indisponível → remote_transaction_unavailable', () async {
      final port = _RecordingFakePort()..throwUnavailable = true;
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      final result = await executor.applyOnce(_plan());

      expect(
        result.outcome,
        PdvV1RemoteStockMarkerApplyOutcome.remoteTransactionUnavailable,
      );
    });

    test('14. ordem: marker lido antes de estoque; reads antes de writes',
        () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);

      await executor.applyOnce(_plan());

      expect(port.reads.first.startsWith('marker:'), isTrue);
      expect(port.reads[1].startsWith('stock:'), isTrue);
      expect(port.reads.length, 2);
      expect(port.writes.length, 2);
    });

    test('15. nenhuma saída altera journal/Hive/attempts/state', () async {
      final port = _RecordingFakePort()
        ..stock = {pdvV1RemoteStockQuantityField: 5};
      final executor = PdvV1RemoteStockMarkerExecutor(port);
      final result = await executor.applyOnce(_plan());

      expect(result, isA<PdvV1RemoteStockMarkerApplyResult>());
      expect(result.toString(), isNot(contains('journal')));
      expect(result.toString(), isNot(contains('Hive')));
    });
  });
}
