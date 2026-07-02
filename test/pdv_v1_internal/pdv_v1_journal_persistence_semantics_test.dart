import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';

const _boxName = 'pdv_v1_journal_test_box';

PdvV1PreparedSnapshot _prep({
  Map<String, dynamic> snapshot = const {'k': 1},
  String snapshotHash = 'snap-sem-1',
  String txHash = 'tx-sem-1',
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-sem-1',
    saleId: 'sale-sem-1',
    lojaId: 'loja-sem-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: snapshot,
    snapshotHash: snapshotHash,
    txItemsHash: txHash,
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _record(
  PdvV1JournalState state, {
  int revision = 0,
  int updatedAt = 1,
}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: updatedAt,
    journalRevision: revision,
  );
}

class _SemanticsHarness {
  late Directory tempDir;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_semantics_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(_boxName);
    return PdvV1HiveJournalRepository(box: box);
  }

  Future<void> tearDown() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(_boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<PdvV1JournalPersistCasOutcome> _persist(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord stored,
  PdvV1JournalRecord candidate,
) {
  return repo.persistIfRevisionMatches(
    operationId: stored.operationId,
    expectedJournalRevision: stored.journalRevision,
    candidateJournalRecord: candidate,
  );
}

void main() {
  final harness = _SemanticsHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('Semântica de persistIfRevisionMatches', () {
    test('1 remoteStockPending → remoteStockApplied permitido', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final candidate = stored.copyWith(
        state: PdvV1JournalState.remoteStockApplied,
        journalRevision: 1,
        updatedAtEpochMs: 2,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.accepted, isTrue);
      expect(outcome.recordPersisted, isTrue);
      expect(outcome.storedRevisionAfter, 1);
    });

    test('2 salto para operationCompleted rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final candidate = stored.copyWith(
        state: PdvV1JournalState.operationCompleted,
        journalRevision: 1,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'invalid_state_transition');
    });

    test('3 salto para hiveSaleCompleted rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final candidate = stored.copyWith(
        state: PdvV1JournalState.hiveSaleCompleted,
        journalRevision: 1,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'invalid_state_transition');
    });

    test('4 state change com revision igual rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final candidate = stored.copyWith(
        state: PdvV1JournalState.remoteStockApplied,
        journalRevision: 0,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'revision_increment_required');
    });

    test('5 state change com revision +2 rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final candidate = stored.copyWith(
        state: PdvV1JournalState.remoteStockApplied,
        journalRevision: 2,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'revision_mismatch');
    });

    test('6 state change com revision menor rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockApplied, revision: 1);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(
        state: PdvV1JournalState.hiveSalePending,
        journalRevision: 0,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'revision_regress_denied');
    });

    test('7 same-state idêntico é no-op sem Box.put', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await repo.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: stored,
      );
      final writesBefore = harness.box.length;
      final outcome = await _persist(repo, stored, stored);
      expect(outcome.accepted, isTrue);
      expect(outcome.recordPersisted, isFalse);
      expect(outcome.rejectionReasonCode, 'no_semantic_change');
      expect(harness.box.length, writesBefore);
    });

    test('8 same-state attempts alterado rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(attempts: 1);
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
    });

    test('9 same-state subestados alterados rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(subestados: const {'x': 1});
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
    });

    test('10 same-state ultimoErro alterado rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(ultimoErroSanitizado: 'erro');
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
    });

    test('11 same-state vendaHiveKey alterada rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(vendaHiveKey: 99);
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
    });

    test('12 same-state updatedAtEpochMs alterado rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(updatedAtEpochMs: 99);
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
    });

    test('13 preparedSnapshot alterado rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = PdvV1JournalRecord(
        prepared: _prep(snapshot: const {'k': 2}),
        state: stored.state,
        createdAtEpochMs: stored.createdAtEpochMs,
        updatedAtEpochMs: stored.updatedAtEpochMs,
        journalRevision: stored.journalRevision,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'prepared_snapshot_mismatch');
    });

    test('14 snapshotHash alterado rejeitado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = PdvV1JournalRecord(
        prepared: _prep(snapshotHash: 'outro-hash'),
        state: stored.state,
        createdAtEpochMs: stored.createdAtEpochMs,
        updatedAtEpochMs: stored.updatedAtEpochMs,
        journalRevision: stored.journalRevision,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'identity_mismatch');
    });

    test('15 operationCompleted terminal rejeita novo estado', () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.operationCompleted, revision: 8);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(
        state: PdvV1JournalState.effectsCompleted,
        journalRevision: 9,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'terminal_state_persist_denied');
    });

    test('16 manualInterventionRequired terminal rejeita novo estado',
        () async {
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored =
          _record(PdvV1JournalState.manualInterventionRequired, revision: 3);
      await harness.box.put(stored.operationId, stored.toJson());
      final candidate = stored.copyWith(
        state: PdvV1JournalState.prepared,
        journalRevision: 4,
      );
      final outcome = await _persist(repo, stored, candidate);
      expect(outcome.rejectionReasonCode, 'terminal_state_persist_denied');
    });

    test('17 journal malformado sem journalRevision preserva payload',
        () async {
      final raw = {
        'state': 'remoteStockPending',
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': _prep().toJson(),
      };
      await harness.box.put('op-sem-1', raw);
      final repo = PdvV1HiveJournalRepository(box: harness.box);
      final candidate =
          _record(PdvV1JournalState.remoteStockApplied, revision: 1);
      final outcome = await repo.persistIfRevisionMatches(
        operationId: 'op-sem-1',
        expectedJournalRevision: 0,
        candidateJournalRecord: candidate,
      );
      expect(outcome.rejectionReasonCode, 'journal_malformed_persist_denied');
      expect(harness.box.get('op-sem-1'), raw);
    });

    test('18 após restart salto inválido não altera Box', () async {
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final repo2 = await harness.reopenRepo();
      final before = await repo2.readByOperationId(stored.operationId);
      final candidate = stored.copyWith(
        state: PdvV1JournalState.operationCompleted,
        journalRevision: 1,
      );
      final outcome = await repo2.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: candidate,
      );
      expect(outcome.rejectionReasonCode, 'invalid_state_transition');
      final after = await repo2.readByOperationId(stored.operationId);
      expect(after!.record.toJson(), before!.record.toJson());
    });

    test('19 após restart mutação same-state não altera Box', () async {
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await harness.box.put(stored.operationId, stored.toJson());
      final repo2 = await harness.reopenRepo();
      final candidate = stored.copyWith(attempts: 5);
      final outcome = await repo2.persistIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        candidateJournalRecord: candidate,
      );
      expect(outcome.rejectionReasonCode,
          'same_state_semantic_mutation_not_supported');
      final after = await repo2.readByOperationId(stored.operationId);
      expect(after!.record.attempts, 0);
    });

    test('20 três execuções iguais retornam JSON idêntico', () async {
      final runs = <String>[];
      for (var i = 0; i < 3; i++) {
        await harness.tearDown();
        await harness.setUp();
        final repo = PdvV1HiveJournalRepository(box: harness.box);
        final stored = _record(PdvV1JournalState.remoteStockPending);
        await harness.box.put(stored.operationId, stored.toJson());
        final candidate = stored.copyWith(
          state: PdvV1JournalState.operationCompleted,
          journalRevision: 1,
        );
        final outcome = await repo.persistIfRevisionMatches(
          operationId: stored.operationId,
          expectedJournalRevision: 0,
          candidateJournalRecord: candidate,
        );
        runs.add(jsonEncode(outcome.toJson()));
      }
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });
  });
}
