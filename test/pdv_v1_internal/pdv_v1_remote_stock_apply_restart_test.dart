import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_apply_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_apply_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_transaction_port.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_state_machine.dart';

const _opId = 'op-r2b-rst-1';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: _opId,
    saleId: 'sale-r2b-rst-1',
    lojaId: 'loja-r2b-rst-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: {
      pdvV1PreparedSnapshotIdentityOperationIdKey: _opId,
      pdvV1PreparedSnapshotIdentitySaleIdKey: 'sale-r2b-rst-1',
      pdvV1PreparedSnapshotIdentityLojaIdKey: 'loja-r2b-rst-1',
      pdvV1PreparedSnapshotIdentityOrigemKey: pdvV1OrigemProtocolValue,
      pdvV1PreparedSnapshotIdentityProtocolVersionKey: pdvV1ProtocolVersion,
      pdvV1PreparedSnapshotIdentitySnapshotHashKey: 'snap-rst-1',
      pdvV1PreparedSnapshotIdentityTxItemsHashKey: 'tx-rst-1',
      pdvV1PreparedSnapshotTxItemsKey: [
        {
          pdvV1PreparedSnapshotSimpleItemProductIdKey: 'prod-rst-1',
          pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 2,
        },
      ],
    },
    snapshotHash: 'snap-rst-1',
    txItemsHash: 'tx-rst-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _pending({int revision = 0}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: PdvV1JournalState.remoteStockPending,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
  );
}

class _HiveRestartHarness {
  late Directory tempDir;
  late String boxName;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_r2b_restart_');
    Hive.init(tempDir.path);
    boxName = 'pdv_v1_r2b_journal_box';
    box = await Hive.openBox<dynamic>(boxName);
  }

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(boxName);
    return PdvV1HiveJournalRepository(box: box);
  }

  Future<void> tearDown() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _RestartPort implements PdvV1RemoteStockMarkerTransactionPort {
  _RestartPort({this.mode = _RestartPortMode.applied});

  _RestartPortMode mode;
  int applyCalls = 0;

  @override
  Future<PdvV1RemoteStockMarkerApplyOutcome> runAtomicApply({
    required PdvV1RemoteStockMarkerPlan plan,
    required Future<PdvV1RemoteStockMarkerApplyOutcome> Function(
      PdvV1RemoteStockMarkerTransactionReadWrite txn,
    ) body,
  }) async {
    applyCalls++;
    if (mode == _RestartPortMode.unavailable) {
      throw Exception('unavailable');
    }
    if (mode == _RestartPortMode.alreadyApplied) {
      return PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied;
    }
    return body(_RestartTxn());
  }
}

enum _RestartPortMode { applied, alreadyApplied, unavailable }

class _RestartTxn implements PdvV1RemoteStockMarkerTransactionReadWrite {
  @override
  Future<Map<String, dynamic>?> readMarker({
    required String lojaId,
    required String operationId,
  }) async =>
      null;

  @override
  Future<Map<String, dynamic>?> readStock({
    required String lojaId,
    required String stockDocumentId,
  }) async =>
      {pdvV1RemoteStockQuantityField: 10};

  @override
  void writeStockQuantity({
    required String lojaId,
    required String stockDocumentId,
    required String quantityField,
    required int newQuantity,
  }) {}

  @override
  void writeMarker({
    required String lojaId,
    required String operationId,
    required Map<String, dynamic> markerData,
  }) {}
}

Future<void> _persistInitial(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord record,
) async {
  final outcome = await repo.persistIfRevisionMatches(
    operationId: record.operationId,
    expectedJournalRevision: 0,
    candidateJournalRecord: record,
  );
  expect(outcome.accepted, isTrue);
}

void main() {
  final harness = _HiveRestartHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('PdvV1RemoteStockApply restart R2-B', () {
    test('1–5. applied persiste remoteStockApplied após restart Hive',
        () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persistInitial(repo, _pending());

      await harness.box.close();
      repo = await harness.reopenRepo();

      final port = _RestartPort();
      final orch = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: repo,
        executor: PdvV1RemoteStockMarkerExecutor(port),
      );

      final result = await orch.applyPendingRemoteStock(
        operationId: _opId,
        expectedJournalRevision: 0,
      );
      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalAdvanced);

      await harness.box.close();
      repo = await harness.reopenRepo();
      final read = await repo.readByOperationId(_opId);
      final record = read!.record;

      expect(record.state, PdvV1JournalState.remoteStockApplied);
      expect(record.journalRevision, 1);
      expect(record.prepared.snapshotHash, 'snap-rst-1');
      expect(record.prepared.txItemsHash, 'tx-rst-1');
      expect(record.prepared.operationId, _opId);
    });

    test('6–8. CAS rejeitado depois alreadyApplied avança sem novo débito',
        () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persistInitial(repo, _pending());

      final rejectRepo = PdvV1HiveJournalRepository(box: harness.box);
      final rejectPort = _RestartPort();
      final rejectOrch = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: _CasRejectOnceRepo(rejectRepo),
        executor: PdvV1RemoteStockMarkerExecutor(rejectPort),
      );

      final rejectResult = await rejectOrch.applyPendingRemoteStock(
        operationId: _opId,
        expectedJournalRevision: 0,
      );
      expect(
        rejectResult.kind,
        PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalNotAdvanced,
      );
      expect(rejectPort.applyCalls, 1);

      await harness.box.close();
      repo = await harness.reopenRepo();

      final port = _RestartPort(mode: _RestartPortMode.alreadyApplied);
      final orch = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: repo,
        executor: PdvV1RemoteStockMarkerExecutor(port),
      );

      final result = await orch.applyPendingRemoteStock(
        operationId: _opId,
        expectedJournalRevision: 0,
      );
      expect(
        result.kind,
        PdvV1RemoteStockApplyOutcomeKind.remoteAlreadyAppliedJournalAdvanced,
      );
      expect(port.applyCalls, 1);

      final read = await repo.readByOperationId(_opId);
      expect(read!.record.state, PdvV1JournalState.remoteStockApplied);
      expect(read.record.journalRevision, 1);
    });

    test('9. remoteTransactionUnavailable após restart mantém pending',
        () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persistInitial(repo, _pending());

      await harness.box.close();
      repo = await harness.reopenRepo();

      final port = _RestartPort(mode: _RestartPortMode.unavailable);
      final orch = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: repo,
        executor: PdvV1RemoteStockMarkerExecutor(port),
      );

      final result = await orch.applyPendingRemoteStock(
        operationId: _opId,
        expectedJournalRevision: 0,
      );
      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.remotePendingNoMutation);

      final read = await repo.readByOperationId(_opId);
      expect(read!.record.state, PdvV1JournalState.remoteStockPending);
      expect(read.record.journalRevision, 0);
    });

    test('10. restart com saleId divergente no inner preserva journal',
        () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final divergentInner =
          Map<String, dynamic>.from(_prep().preparedSnapshot);
      divergentInner[pdvV1PreparedSnapshotIdentitySaleIdKey] = 'sale-DIVERGENT';
      final divergentPrep = PdvV1PreparedSnapshot(
        protocolVersion: _prep().protocolVersion,
        operationId: _prep().operationId,
        saleId: _prep().saleId,
        lojaId: _prep().lojaId,
        origem: _prep().origem,
        preparedAtEpochMs: _prep().preparedAtEpochMs,
        preparedSnapshot: divergentInner,
        snapshotHash: _prep().snapshotHash,
        txItemsHash: _prep().txItemsHash,
        isFiado: _prep().isFiado,
        hasCombo: _prep().hasCombo,
        isEdicao: _prep().isEdicao,
        isCancelamento: _prep().isCancelamento,
      );
      final initial = _pending().copyWith(prepared: divergentPrep);
      await _persistInitial(repo, initial);

      await harness.box.close();
      repo = await harness.reopenRepo();

      final port = _RestartPort();
      final orch = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: repo,
        executor: PdvV1RemoteStockMarkerExecutor(port),
      );

      final result = await orch.applyPendingRemoteStock(
        operationId: _opId,
        expectedJournalRevision: 0,
      );
      expect(
        result.kind,
        PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible,
      );
      expect(port.applyCalls, 0);

      final read = await repo.readByOperationId(_opId);
      final record = read!.record;
      expect(record.state, PdvV1JournalState.remoteStockPending);
      expect(record.journalRevision, 0);
      expect(record.prepared.saleId, 'sale-r2b-rst-1');
      expect(record.prepared.snapshotHash, 'snap-rst-1');
      expect(record.prepared.txItemsHash, 'tx-rst-1');
      expect(
        record
            .prepared.preparedSnapshot[pdvV1PreparedSnapshotIdentitySaleIdKey],
        'sale-DIVERGENT',
      );
    });
  });
}

/// Decorator que rejeita a primeira persistência CAS e delega depois.
class _CasRejectOnceRepo implements PdvV1JournalRepository {
  _CasRejectOnceRepo(this._inner);

  final PdvV1HiveJournalRepository _inner;
  bool _rejected = false;

  @override
  Future<PdvV1JournalReadOutcome?> readByOperationId(String operationId) =>
      _inner.readByOperationId(operationId);

  @override
  Future<PdvV1JournalPersistCasOutcome> persistIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalRecord candidateJournalRecord,
  }) async {
    if (!_rejected) {
      _rejected = true;
      return PdvV1JournalPersistCasOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: expectedJournalRevision,
        storedRevisionAfter: expectedJournalRevision,
        rejectionReasonCode: 'revision_mismatch',
        operationId: operationId,
        stateBefore: candidateJournalRecord.state,
        stateAfter: candidateJournalRecord.state,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
      );
    }
    return _inner.persistIfRevisionMatches(
      operationId: operationId,
      expectedJournalRevision: expectedJournalRevision,
      candidateJournalRecord: candidateJournalRecord,
    );
  }

  @override
  Future<void> put(PdvV1JournalRecord record) => _inner.put(record);

  @override
  Future<PdvV1JournalRecord> transition({
    required String operationId,
    required PdvV1JournalState to,
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  }) =>
      _inner.transition(
        operationId: operationId,
        to: to,
        updatedAtEpochMs: updatedAtEpochMs,
        ultimoErroSanitizado: ultimoErroSanitizado,
        vendaHiveKey: vendaHiveKey,
      );

  @override
  Future<PdvV1JournalRecord> reconcileRemoteStockPending({
    required String operationId,
    required PdvV1RemoteStockResolution resolution,
    required int updatedAtEpochMs,
  }) =>
      _inner.reconcileRemoteStockPending(
        operationId: operationId,
        resolution: resolution,
        updatedAtEpochMs: updatedAtEpochMs,
      );

  @override
  Future<PdvV1JournalSameStatePatchPersistOutcome>
      persistAuthorizedSameStatePatchIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalSameStatePatch patch,
    required PdvV1JournalSameStatePatchAuthorization authorization,
  }) =>
          _inner.persistAuthorizedSameStatePatchIfRevisionMatches(
            operationId: operationId,
            expectedJournalRevision: expectedJournalRevision,
            patch: patch,
            authorization: authorization,
          );
}
