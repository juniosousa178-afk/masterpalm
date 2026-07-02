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

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-mal-restart-1',
    saleId: 'sale-mal-1',
    lojaId: 'loja-mal-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-mal-1',
    txItemsHash: 'tx-mal-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

void main() {
  late Directory tempDir;
  late String boxName;
  late Box<dynamic> box;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('pdv_v1_malformed_restart_');
    Hive.init(tempDir.path);
    boxName = 'pdv_v1_journal_test_box';
    box = await Hive.openBox<dynamic>(boxName);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(boxName);
    return PdvV1HiveJournalRepository(box: box);
  }

  group('Journal malformado após restart', () {
    test('payload sem journalRevision permanece bruto e terminal', () async {
      final raw = {
        'state': 'remoteStockPending',
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': _prep().toJson(),
      };
      await box.put('op-mal-restart-1', raw);

      await box.close();
      var repo = await reopenRepo();
      var outcome = await repo.readByOperationId('op-mal-restart-1');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(
          outcome.record.state, PdvV1JournalState.manualInterventionRequired);
      expect(outcome.malformedEvidence!.reasonCode, 'journal_revision_ausente');
      expect(box.get('op-mal-restart-1'), raw);

      repo = await reopenRepo();
      final outcome2 = await repo.readByOperationId('op-mal-restart-1');
      expect(outcome2!.malformedEvidence!.toJson(),
          outcome.malformedEvidence!.toJson());
      expect(box.get('op-mal-restart-1'), raw);
    });

    test('estado inválido preserva payload e rejeita persist CAS', () async {
      final raw = {
        'state': 'invalid_state',
        'prepared': _prep().toJson(),
        'journalRevision': 0
      };
      await box.put('op-mal-restart-1', raw);
      await box.close();

      var repo = await reopenRepo();
      final outcome = await repo.readByOperationId('op-mal-restart-1');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(box.get('op-mal-restart-1'), raw);

      final candidate = PdvV1JournalRecord(
        prepared: _prep(),
        state: PdvV1JournalState.remoteStockPending,
        createdAtEpochMs: 1,
        updatedAtEpochMs: 2,
        journalRevision: 0,
      );
      final persist = await repo.persistIfRevisionMatches(
        operationId: 'op-mal-restart-1',
        expectedJournalRevision: 0,
        candidateJournalRecord: candidate,
      );
      expect(persist.accepted, isFalse);
      expect(persist.rejectionReasonCode, 'journal_malformed_persist_denied');
      expect(box.get('op-mal-restart-1'), raw);
    });

    test('preparedSnapshot inválido não cruza para plano ou coordinator',
        () async {
      final raw = {
        'state': 'prepared',
        'journalRevision': 0,
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': {'preparedSnapshot': 'not-a-map'},
      };
      await box.put('op-mal-restart-1', raw);
      await box.close();

      final repo = await reopenRepo();
      final outcome = await repo.readByOperationId('op-mal-restart-1');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(box.get('op-mal-restart-1'), raw);

      final orchestrator = PdvV1RecoveryOrchestrator();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      expect(plan.isManualIntervention, isTrue);

      final store = PdvV1RecoverySimulatedCasStore(outcome.record);
      final before = store.snapshot.toJson();
      final coordinator = PdvV1RecoverySimulationCoordinator();
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: outcome,
        ),
      );
      expect(run.manualInterventionRequired, isTrue);
      expect(run.executionOutcome, isNull);
      expect(run.casApplyOutcome, isNull);
      expect(store.snapshot.toJson(), before);
      expect(box.get('op-mal-restart-1'), raw);
    });

    test('nenhuma escrita automática após leitura malformada', () async {
      final raw = {'state': 'x', 'journalRevision': 0};
      await box.put('op-mal-restart-1', raw);
      final writesBefore = box.length;

      await box.close();
      final repo = await reopenRepo();
      await repo.readByOperationId('op-mal-restart-1');
      await repo.readByOperationId('op-mal-restart-1');

      expect(box.length, writesBefore);
      expect(box.get('op-mal-restart-1'), raw);
    });
  });
}
