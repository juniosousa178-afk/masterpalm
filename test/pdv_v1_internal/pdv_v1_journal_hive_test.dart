import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';

PdvV1PreparedSnapshot _snap() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-journal-1',
    saleId: 'sale-journal-1',
    lojaId: 'loja-journal-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: {'k': 'v'},
    snapshotHash: 'snap-h',
    txItemsHash: 'tx-h',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late String boxName;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_journal_test_');
    Hive.init(tempDir.path);
    boxName = 'pdv_v1_journal_box_test';
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

  group('PdvV1HiveJournalRepository', () {
    test('serializa e reabre record válido', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      final record = PdvV1JournalRecord.createInitial(
        prepared: _snap(),
        createdAtEpochMs: 1700000000001,
      );
      await repo.put(record);
      final outcome = await repo.readByOperationId('op-journal-1');
      expect(outcome, isNotNull);
      expect(outcome!.isMalformedReadOnly, isFalse);
      expect(outcome.record.state, PdvV1JournalState.prepared);
      expect(outcome.record.prepared.saleId, 'sale-journal-1');
    });

    test('journal com estado inválido retorna manual com evidência', () async {
      final raw = {'state': 'invalid', 'prepared': 1};
      await box.put('bad-op', raw);
      final repo = PdvV1HiveJournalRepository(box: box);
      final outcome = await repo.readByOperationId('bad-op');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(
          outcome.record.state, PdvV1JournalState.manualInterventionRequired);
      expect(outcome.malformedEvidence!.operationIdCandidate, 'bad-op');
      expect(outcome.malformedEvidence!.rawPayloadSanitized, isA<Map>());
      expect(
        Map<String, dynamic>.from(
          outcome.malformedEvidence!.rawPayloadSanitized as Map,
        )['state'],
        'invalid',
      );
      expect(box.get('bad-op'), raw);
    });

    test('record sem operationId recupera candidate da chave', () async {
      final raw = {
        'state': 'prepared',
        'prepared': {'saleId': 's1', 'lojaId': 'l1'},
      };
      await box.put('key-op', raw);
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: raw,
        storageKey: 'key-op',
      );
      expect(outcome.malformedEvidence!.operationIdCandidate, 'key-op');
      expect(outcome.malformedEvidence!.saleIdCandidate, 's1');
    });

    test('record com preparedSnapshot inválido preserva payload bruto',
        () async {
      final raw = {
        'state': 'prepared',
        'prepared': {'preparedSnapshot': 'x'},
      };
      await box.put('bad-snap', raw);
      final repo = PdvV1HiveJournalRepository(box: box);
      final before = box.get('bad-snap');
      final outcome = await repo.readByOperationId('bad-snap');
      expect(outcome!.isMalformedReadOnly, isTrue);
      expect(box.get('bad-snap'), before);
      expect(outcome.malformedEvidence!.rawPayloadType, 'Map');
    });

    test('tipo inválido no box preserva evidência', () async {
      await box.put('bad-type', 'string-payload');
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: box.get('bad-type'),
        storageKey: 'bad-type',
      );
      expect(outcome.isMalformedReadOnly, isTrue);
      expect(outcome.malformedEvidence!.rawPayloadType, 'String');
      expect(box.get('bad-type'), 'string-payload');
    });

    test('leitura duas vezes gera decisão equivalente', () async {
      await box.put('dup', {'state': 'x'});
      final repo = PdvV1HiveJournalRepository(box: box);
      final a = await repo.readByOperationId('dup');
      final b = await repo.readByOperationId('dup');
      expect(a!.malformedEvidence!.toJson(), b!.malformedEvidence!.toJson());
      expect(a.record.state, b.record.state);
    });

    test('leitura malformada não grava no box', () async {
      final raw = {'state': 'invalid'};
      await box.put('no-write', raw);
      final writesBefore = box.length;
      final repo = PdvV1HiveJournalRepository(box: box);
      await repo.readByOperationId('no-write');
      expect(box.length, writesBefore);
      expect(box.get('no-write'), raw);
    });

    test('não permite transição em journal malformado', () async {
      await box.put('mal', {'state': 'invalid'});
      final repo = PdvV1HiveJournalRepository(box: box);
      expect(
        () => repo.transition(
          operationId: 'mal',
          to: PdvV1JournalState.prepared,
          updatedAtEpochMs: 2,
        ),
        throwsA(isA<PdvV1MalformedJournalError>()),
      );
    });

    test('não permite put de record malformado read-only', () async {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {'state': 'invalid'},
        storageKey: 'x',
      );
      final repo = PdvV1HiveJournalRepository(box: box);
      expect(
        () => repo.put(outcome.record),
        throwsA(isA<PdvV1MalformedJournalError>()),
      );
    });

    test('não permite transição inválida em record válido', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      final record = PdvV1JournalRecord.createInitial(
        prepared: _snap(),
        createdAtEpochMs: 1,
      );
      await repo.put(record);
      expect(
        () => repo.transition(
          operationId: 'op-journal-1',
          to: PdvV1JournalState.operationCompleted,
          updatedAtEpochMs: 2,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
    });

    test('operationCompleted é terminal', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      await repo.put(
        PdvV1JournalRecord.createInitial(
            prepared: _snap(), createdAtEpochMs: 1),
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.remoteStockPending,
        updatedAtEpochMs: 2,
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.remoteStockApplied,
        updatedAtEpochMs: 3,
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.hiveSalePending,
        updatedAtEpochMs: 4,
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.hiveSaleCompleted,
        updatedAtEpochMs: 5,
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.effectsPending,
        updatedAtEpochMs: 6,
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.effectsCompleted,
        updatedAtEpochMs: 7,
      );
      final done = await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.operationCompleted,
        updatedAtEpochMs: 8,
      );
      expect(done.state, PdvV1JournalState.operationCompleted);
      expect(done.journalRevision, 7);
      expect(
        () => repo.transition(
          operationId: 'op-journal-1',
          to: PdvV1JournalState.prepared,
          updatedAtEpochMs: 9,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
    });

    test('journal novo inicia em revision 0', () async {
      final record = PdvV1JournalRecord.createInitial(
        prepared: _snap(),
        createdAtEpochMs: 1,
      );
      expect(record.journalRevision, 0);
    });

    test('transição válida incrementa revision exatamente uma vez', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      await repo.put(
        PdvV1JournalRecord.createInitial(
            prepared: _snap(), createdAtEpochMs: 1),
      );
      final next = await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.remoteStockPending,
        updatedAtEpochMs: 2,
      );
      expect(next.journalRevision, 1);
    });

    test('transição inválida não incrementa revision', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      await repo.put(
        PdvV1JournalRecord.createInitial(
            prepared: _snap(), createdAtEpochMs: 1),
      );
      expect(
        () => repo.transition(
          operationId: 'op-journal-1',
          to: PdvV1JournalState.operationCompleted,
          updatedAtEpochMs: 2,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
      final outcome = await repo.readByOperationId('op-journal-1');
      expect(outcome!.record.journalRevision, 0);
    });

    test('manualInterventionRequired é terminal', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      await repo.put(
        PdvV1JournalRecord.createInitial(
            prepared: _snap(), createdAtEpochMs: 1),
      );
      await repo.transition(
        operationId: 'op-journal-1',
        to: PdvV1JournalState.manualInterventionRequired,
        updatedAtEpochMs: 2,
        ultimoErroSanitizado: 'teste',
      );
      expect(
        () => repo.transition(
          operationId: 'op-journal-1',
          to: PdvV1JournalState.prepared,
          updatedAtEpochMs: 3,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
    });
  });
}
