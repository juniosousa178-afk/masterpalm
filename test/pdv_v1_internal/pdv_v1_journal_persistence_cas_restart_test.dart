import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

PdvV1PreparedSnapshot _prep({String op = 'op-cas-1'}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: op,
    saleId: 'sale-cas-1',
    lojaId: 'loja-cas-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-cas-1',
    txItemsHash: 'tx-cas-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _record(
  PdvV1JournalState state, {
  int revision = 0,
  String op = 'op-cas-1',
}) {
  return PdvV1JournalRecord(
    prepared: _prep(op: op),
    state: state,
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
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_cas_restart_');
    Hive.init(tempDir.path);
    boxName = 'pdv_v1_journal_test_box';
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

Future<PdvV1JournalPersistCasOutcome> _persist(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord candidate, {
  required int expectedRevision,
}) {
  return repo.persistIfRevisionMatches(
    operationId: candidate.operationId,
    expectedJournalRevision: expectedRevision,
    candidateJournalRecord: candidate,
  );
}

void main() {
  final harness = _HiveRestartHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('persistIfRevisionMatches CAS local', () {
    test('journal criado com revision 0', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final initial = _record(PdvV1JournalState.remoteStockPending);
      final outcome = await _persist(repo, initial, expectedRevision: 0);
      expect(outcome.accepted, isTrue);
      expect(outcome.storedRevisionAfter, 0);
      final read = await repo.readByOperationId('op-cas-1');
      expect(read!.record.journalRevision, 0);
    });

    test('transição exige revision atual e incrementa +1', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final initial = _record(PdvV1JournalState.remoteStockPending);
      await _persist(repo, initial, expectedRevision: 0);
      final next = initial.copyWith(
        state: PdvV1JournalState.remoteStockApplied,
        journalRevision: 1,
        updatedAtEpochMs: 2,
      );
      final outcome = await _persist(repo, next, expectedRevision: 0);
      expect(outcome.accepted, isTrue);
      expect(outcome.storedRevisionBefore, 0);
      expect(outcome.storedRevisionAfter, 1);
    });

    test('persistência sem mudança estrutural é no-op sem Box.put', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final initial = _record(PdvV1JournalState.remoteStockPending);
      await _persist(repo, initial, expectedRevision: 0);
      final writesBefore = harness.box.length;
      final outcome = await _persist(repo, initial, expectedRevision: 0);
      expect(outcome.accepted, isTrue);
      expect(outcome.recordPersisted, isFalse);
      expect(outcome.rejectionReasonCode, 'no_semantic_change');
      expect(outcome.storedRevisionAfter, 0);
      expect(harness.box.length, writesBefore);
    });

    test('candidate com revision +2 é rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persist(
        repo,
        _record(PdvV1JournalState.remoteStockPending),
        expectedRevision: 0,
      );
      final jump = _record(PdvV1JournalState.remoteStockApplied, revision: 2);
      final outcome = await _persist(repo, jump, expectedRevision: 0);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'revision_mismatch');
      final read = await repo.readByOperationId('op-cas-1');
      expect(read!.record.journalRevision, 0);
    });

    test('candidate com revision igual em mudança de estado é rejeitado',
        () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persist(
        repo,
        _record(PdvV1JournalState.remoteStockPending),
        expectedRevision: 0,
      );
      final stale = _record(PdvV1JournalState.remoteStockApplied, revision: 0);
      final outcome = await _persist(repo, stale, expectedRevision: 0);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'revision_increment_required');
    });

    test('candidate com identity divergente é rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      await _persist(
        repo,
        _record(PdvV1JournalState.remoteStockPending),
        expectedRevision: 0,
      );
      final divergent = PdvV1JournalRecord(
        prepared: PdvV1PreparedSnapshot(
          protocolVersion: pdvV1ProtocolVersion,
          operationId: 'op-cas-1',
          saleId: 'sale-cas-1',
          lojaId: 'loja-cas-1',
          origem: PdvV1InternalOrigin.novaVendaPdvFuture,
          preparedAtEpochMs: 1700000000000,
          preparedSnapshot: const {'k': 1},
          snapshotHash: 'snap-divergent',
          txItemsHash: 'tx-cas-1',
          isFiado: false,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false,
        ),
        state: PdvV1JournalState.remoteStockApplied,
        createdAtEpochMs: 1,
        updatedAtEpochMs: 2,
        journalRevision: 1,
      );
      final outcome = await _persist(repo, divergent, expectedRevision: 0);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'identity_mismatch');
    });

    test('registro sem journalRevision é malformado na leitura', () async {
      final raw = {
        'state': 'remoteStockPending',
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': _prep().toJson(),
      };
      await harness.box.put('op-cas-1', raw);
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final outcome = await repo.readByOperationId('op-cas-1');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(outcome.malformedEvidence!.reasonCode, 'journal_revision_ausente');
    });

    test('journal terminal não aceita novo estado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final terminal =
          _record(PdvV1JournalState.operationCompleted, revision: 8);
      await harness.box.put('op-cas-1', terminal.toJson());
      final candidate = terminal.copyWith(
        state: PdvV1JournalState.effectsCompleted,
        journalRevision: 9,
      );
      final outcome = await _persist(repo, candidate, expectedRevision: 8);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'terminal_state_persist_denied');
    });

    test('teardown remove Box e diretório temporário', () async {
      final dirPath = harness.tempDir.path;
      final name = harness.boxName;
      expect(await harness.tempDir.exists(), isTrue);
      expect(Hive.isBoxOpen(name), isTrue);
      await harness.tearDown();
      expect(await Directory(dirPath).exists(), isFalse);
      expect(Hive.isBoxOpen(name), isFalse);
      await harness.setUp();
    });
  });

  group('stale após restart', () {
    final coordinator = PdvV1RecoverySimulationCoordinator();
    final orchestrator = PdvV1RecoveryOrchestrator();

    PdvV1RemoteVerificationEvidence syntheticEvidence() {
      return PdvV1RemoteVerificationEvidence(
        requestedOperationId: 'op-cas-1',
        requestedSaleId: 'sale-cas-1',
        requestedLojaId: 'loja-cas-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-cas-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        optionalMarker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-cas-1',
          operationId: 'op-cas-1',
          saleId: 'sale-cas-1',
          baixaAplicada: true,
          txItemsHash: 'tx-cas-1',
        ),
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
    }

    test('plano stale após restart não altera Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final initial = _record(PdvV1JournalState.remoteStockPending);
      await _persist(repo, initial, expectedRevision: 0);

      final storeA = PdvV1RecoverySimulatedCasStore(initial);
      final runA = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: storeA,
          journalOutcome: PdvV1JournalReadOutcome(record: initial),
          evidence: syntheticEvidence(),
        ),
      );
      expect(runA.casApplyOutcome!.accepted, isTrue);
      await _persist(repo, storeA.snapshot, expectedRevision: 0);

      repo = await harness.reopenRepo();
      final afterA = await repo.readByOperationId('op-cas-1');
      expect(afterA!.record.journalRevision, 1);
      expect(afterA.record.state, PdvV1JournalState.remoteStockApplied);

      final staleCandidate = initial.copyWith(
        state: PdvV1JournalState.remoteStockPending,
        journalRevision: 0,
      );
      final stale = await _persist(repo, staleCandidate, expectedRevision: 0);
      expect(stale.accepted, isFalse);
      expect(stale.rejectionReasonCode, 'stale_journal_revision');

      final afterStale = await repo.readByOperationId('op-cas-1');
      expect(afterStale!.record.journalRevision, 1);
      expect(afterStale.record.state, PdvV1JournalState.remoteStockApplied);
      expect(
          orchestrator
              .plan(
                PdvV1RecoveryOrchestratorInput(journalOutcome: afterStale),
              )
              .currentState,
          PdvV1JournalState.remoteStockApplied);
    });

    test('confirmação stale após restart não altera Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final pending = _record(PdvV1JournalState.hiveSalePending, revision: 2);
      await harness.box.put('op-cas-1', pending.toJson());

      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: pending),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: pending.prepared);

      final storeA = PdvV1RecoverySimulatedCasStore(pending);
      final confA = PdvV1SimulatedStageConfirmation(
        planFingerprint: fp,
        expectedJournalRevision: 2,
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        lojaId: 'loja-cas-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-cas-1',
        txItemsHash: 'tx-cas-1',
        expectedStateBefore: PdvV1JournalState.hiveSalePending,
        expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
      );
      final runA = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: storeA,
          journalOutcome: PdvV1JournalReadOutcome(record: pending),
          confirmation: confA,
        ),
      );
      expect(runA.casApplyOutcome!.accepted, isTrue);
      await _persist(repo, storeA.snapshot, expectedRevision: 2);

      repo = await harness.reopenRepo();
      final afterA = await repo.readByOperationId('op-cas-1');
      expect(afterA!.record.state, PdvV1JournalState.hiveSaleCompleted);
      expect(afterA.record.journalRevision, 3);

      final confB = PdvV1SimulatedStageConfirmation(
        planFingerprint: fp,
        expectedJournalRevision: 2,
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        lojaId: 'loja-cas-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-cas-1',
        txItemsHash: 'tx-cas-1',
        expectedStateBefore: PdvV1JournalState.hiveSalePending,
        expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
      );
      final storeB = PdvV1RecoverySimulatedCasStore(afterA.record);
      final runB = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: storeB,
          journalOutcome: PdvV1JournalReadOutcome(record: afterA.record),
          confirmation: confB,
        ),
      );
      expect(
          runB.casApplyOutcome == null ||
              runB.casApplyOutcome!.accepted == false,
          isTrue);

      final staleCandidate = pending.copyWith(
        state: PdvV1JournalState.hiveSaleCompleted,
        journalRevision: 3,
        updatedAtEpochMs: 3,
      );
      final stalePersist =
          await _persist(repo, staleCandidate, expectedRevision: 2);
      expect(stalePersist.accepted, isFalse);
      expect(
        stalePersist.rejectionReasonCode,
        anyOf('stale_journal_revision', 'revision_mismatch'),
      );

      final afterStale = await repo.readByOperationId('op-cas-1');
      expect(afterStale!.record.journalRevision, 3);
      expect(afterStale.record.state, PdvV1JournalState.hiveSaleCompleted);
    });

    test('stage request stale após restart não altera Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final completed =
          _record(PdvV1JournalState.hiveSaleCompleted, revision: 3);
      await harness.box.put('op-cas-1', completed.toJson());

      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: completed),
        ),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
          plan: plan, prep: completed.prepared);

      final storeA = PdvV1RecoverySimulatedCasStore(completed);
      final stageA = PdvV1SimulatedStageStartRequest(
        planFingerprint: fp,
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        lojaId: 'loja-cas-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-cas-1',
        txItemsHash: 'tx-cas-1',
        expectedJournalRevision: 3,
        expectedStateBefore: PdvV1JournalState.hiveSaleCompleted,
        expectedTargetState: PdvV1JournalState.saleSyncPending,
        stageToStart: PdvV1SimulatedConfirmationStage.saleSync,
        requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
        semanticPlanValidated: true,
        identityValidated: true,
      );
      final runA = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: storeA,
          journalOutcome: PdvV1JournalReadOutcome(record: completed),
          stageStartRequest: stageA,
        ),
      );
      expect(runA.casApplyOutcome!.accepted, isTrue);
      await _persist(repo, storeA.snapshot, expectedRevision: 3);

      repo = await harness.reopenRepo();
      final afterA = await repo.readByOperationId('op-cas-1');
      expect(afterA!.record.state, PdvV1JournalState.saleSyncPending);
      expect(afterA.record.journalRevision, 4);

      final stageB = PdvV1SimulatedStageStartRequest(
        planFingerprint: fp,
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        lojaId: 'loja-cas-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-cas-1',
        txItemsHash: 'tx-cas-1',
        expectedJournalRevision: 3,
        expectedStateBefore: PdvV1JournalState.hiveSaleCompleted,
        expectedTargetState: PdvV1JournalState.saleSyncPending,
        stageToStart: PdvV1SimulatedConfirmationStage.saleSync,
        requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
        semanticPlanValidated: true,
        identityValidated: true,
      );
      final storeB = PdvV1RecoverySimulatedCasStore(afterA.record);
      final runB = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: storeB,
          journalOutcome: PdvV1JournalReadOutcome(record: afterA.record),
          stageStartRequest: stageB,
        ),
      );
      expect(
          runB.casApplyOutcome == null ||
              runB.casApplyOutcome!.accepted == false,
          isTrue);

      final staleCandidate = completed.copyWith(
        state: PdvV1JournalState.saleSyncPending,
        journalRevision: 4,
        updatedAtEpochMs: 4,
      );
      final stalePersist =
          await _persist(repo, staleCandidate, expectedRevision: 3);
      expect(stalePersist.accepted, isFalse);
      expect(stalePersist.rejectionReasonCode, 'stale_journal_revision');

      final afterStale = await repo.readByOperationId('op-cas-1');
      expect(afterStale!.record.journalRevision, 4);
      expect(afterStale.record.state, PdvV1JournalState.saleSyncPending);
    });
  });
}
