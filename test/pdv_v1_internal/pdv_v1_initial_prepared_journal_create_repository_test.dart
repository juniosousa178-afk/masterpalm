import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_initial_prepared_journal_create_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _preparedAtEpochMs = 1700000000000;
const _boxName = 'pdv_v1_initial_create_repo_test_box';

PdvV1PreparedSnapshot _prepared({
  String operationId = 'op-create-001',
  String lojaId = 'loja-create-a',
  String stockDocumentId = 'prod-create-001',
  int quantidade = 2,
  int preparedAtEpochMs = _preparedAtEpochMs,
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
}) {
  return pdvV1PrepareSimpleSale(
    PdvV1SimpleSalePreparationInput(
      operationId: operationId,
      saleId: operationId,
      lojaId: lojaId,
      preparedAtEpochMs: preparedAtEpochMs,
      stockDocumentId: stockDocumentId,
      quantidade: quantidade,
      saleLineCount: 1,
      stockLineCount: 1,
      isNewPdvSale: true,
      hasCombo: hasCombo,
      isFiado: isFiado,
      isEdicao: isEdicao,
      isCancelamento: isCancelamento,
      hasVariationSelection: false,
      productHasVariationDefinition: false,
      stockShapeIsKnownSimpleDirect: true,
    ),
  ).prepared!;
}

PdvV1JournalRecord _validInitial({
  String operationId = 'op-create-001',
  int preparedAtEpochMs = _preparedAtEpochMs,
}) {
  return PdvV1JournalRecord.createInitial(
    prepared: _prepared(
      operationId: operationId,
      preparedAtEpochMs: preparedAtEpochMs,
    ),
    createdAtEpochMs: preparedAtEpochMs,
  );
}

PdvV1HiveJournalRepository _createRepo(Box<dynamic> box) {
  return PdvV1HiveJournalRepository(box: box);
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'pdv_v1_initial_create_repo_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(_boxName);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(_boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('createInitialPreparedIfAbsent', () {
    test('1. journal ausente retorna created com prepared rev0', () async {
      final repo = _createRepo(box);
      final expected = _validInitial();

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: expected,
      );

      expect(outcome.kind, PdvV1JournalInitialCreateOutcomeKind.created);
      expect(outcome.record, isNotNull);
      expect(outcome.record!.state, PdvV1JournalState.prepared);
      expect(outcome.record!.journalRevision, 0);
      expect(outcome.operationId, 'op-create-001');
      expect(box.containsKey('op-create-001'), isTrue);
    });

    test('2. repetição retorna alreadyExistsIdentical sem nova escrita',
        () async {
      final repo = _createRepo(box);
      final expected = _validInitial();
      await repo.createInitialPreparedIfAbsent(expectedInitial: expected);
      final rawAfterFirst = box.get('op-create-001');

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: expected,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical,
      );
      expect(outcome.record, isNotNull);
      expect(box.get('op-create-001'), rawAfterFirst);
    });

    test('3. mesmo operationId expected divergente retorna conflict', () async {
      final repo = _createRepo(box);
      final first = _validInitial();
      await repo.createInitialPreparedIfAbsent(expectedInitial: first);

      final divergentPrepared = PdvV1PreparedSnapshot(
        protocolVersion: first.prepared.protocolVersion,
        operationId: first.prepared.operationId,
        saleId: first.prepared.saleId,
        lojaId: first.prepared.lojaId,
        origem: first.prepared.origem,
        preparedAtEpochMs: first.prepared.preparedAtEpochMs,
        preparedSnapshot: first.prepared.preparedSnapshot,
        snapshotHash:
            '0000000000000000000000000000000000000000000000000000000000000001',
        txItemsHash: first.prepared.txItemsHash,
        isFiado: false,
        hasCombo: false,
        isEdicao: false,
        isCancelamento: false,
      );
      final divergent = PdvV1JournalRecord.createInitial(
        prepared: divergentPrepared,
        createdAtEpochMs: first.createdAtEpochMs,
      );

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: divergent,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
      );
      expect(
        (box.get('op-create-001') as Map)['prepared']['snapshotHash'],
        first.prepared.snapshotHash,
      );
    });

    test('4. existente remoteStockPending retorna conflict', () async {
      final repo = _createRepo(box);
      final initial = _validInitial();
      await repo.createInitialPreparedIfAbsent(expectedInitial: initial);
      final advanced = initial.copyWith(
        state: PdvV1JournalState.remoteStockPending,
        journalRevision: 1,
      );
      await box.put('op-create-001', advanced.toJson());

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: initial,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
      );
      expect(
        (await repo.readByOperationId('op-create-001'))!.record.state,
        PdvV1JournalState.remoteStockPending,
      );
    });

    test('5. existente malformado retorna existingMalformed', () async {
      final repo = _createRepo(box);
      await box.put('op-create-001', {'state': 'invalid_only'});

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: _validInitial(),
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.existingMalformed,
      );
      expect(box.get('op-create-001'), {'state': 'invalid_only'});
    });

    test('6. operationId/saleId divergentes retorna invalidExpectedInitial',
        () async {
      final repo = _createRepo(box);
      final prepared = _prepared(operationId: 'op-create-001');
      final bad = PdvV1JournalRecord.createInitial(
        prepared: PdvV1PreparedSnapshot(
          protocolVersion: prepared.protocolVersion,
          operationId: 'op-create-001',
          saleId: 'op-create-alt',
          lojaId: prepared.lojaId,
          origem: prepared.origem,
          preparedAtEpochMs: prepared.preparedAtEpochMs,
          preparedSnapshot: prepared.preparedSnapshot,
          snapshotHash: prepared.snapshotHash,
          txItemsHash: prepared.txItemsHash,
          isFiado: false,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false,
        ),
        createdAtEpochMs: prepared.preparedAtEpochMs,
      );

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: bad,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
      );
      expect(box.isEmpty, isTrue);
    });

    test('7. state diferente de prepared retorna invalidExpectedInitial',
        () async {
      final repo = _createRepo(box);
      final expected = _validInitial().copyWith(
        state: PdvV1JournalState.remoteStockPending,
      );

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: expected,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
      );
      expect(box.isEmpty, isTrue);
    });

    test('8. revision diferente de zero retorna invalidExpectedInitial',
        () async {
      final repo = _createRepo(box);
      final expected = _validInitial().copyWith(journalRevision: 1);

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: expected,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
      );
      expect(box.isEmpty, isTrue);
    });

    test('9. flags inelegíveis retornam invalidExpectedInitial', () async {
      final repo = _createRepo(box);
      final base = _validInitial();
      final prep = base.prepared;
      for (final flags in [
        (
          isFiado: true,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false
        ),
        (
          isFiado: false,
          hasCombo: true,
          isEdicao: false,
          isCancelamento: false
        ),
        (
          isFiado: false,
          hasCombo: false,
          isEdicao: true,
          isCancelamento: false
        ),
        (
          isFiado: false,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: true
        ),
      ]) {
        final expected = base.copyWith(
          prepared: PdvV1PreparedSnapshot(
            protocolVersion: prep.protocolVersion,
            operationId: prep.operationId,
            saleId: prep.saleId,
            lojaId: prep.lojaId,
            origem: prep.origem,
            preparedAtEpochMs: prep.preparedAtEpochMs,
            preparedSnapshot: prep.preparedSnapshot,
            snapshotHash: prep.snapshotHash,
            txItemsHash: prep.txItemsHash,
            isFiado: flags.isFiado,
            hasCombo: flags.hasCombo,
            isEdicao: flags.isEdicao,
            isCancelamento: flags.isCancelamento,
          ),
        );
        final outcome = await repo.createInitialPreparedIfAbsent(
          expectedInitial: expected,
        );
        expect(
          outcome.kind,
          PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        );
      }
      expect(box.isEmpty, isTrue);
    });

    test('10. malformedEvidence presente retorna invalidExpectedInitial',
        () async {
      final repo = _createRepo(box);
      final expected = _validInitial().copyWith(
        malformedEvidence: const PdvV1MalformedJournalEvidence(
          reasonCode: 'test',
          rawPayloadType: 'Map',
          rawPayloadSanitized: {'x': 1},
        ),
      );

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: expected,
      );

      expect(
        outcome.kind,
        PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
      );
      expect(box.isEmpty, isTrue);
    });

    test('11. diferenças semânticas isoladas retornam conflict', () async {
      final repo = _createRepo(box);
      final base = _validInitial(operationId: 'op-sem-eq-001');
      await repo.createInitialPreparedIfAbsent(expectedInitial: base);

      Future<void> expectConflict(PdvV1JournalRecord divergent) async {
        final outcome = await repo.createInitialPreparedIfAbsent(
          expectedInitial: divergent,
        );
        expect(
          outcome.kind,
          PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
        );
      }

      final prep = base.prepared;
      await expectConflict(
        base.copyWith(
          prepared: PdvV1PreparedSnapshot(
            protocolVersion: prep.protocolVersion,
            operationId: prep.operationId,
            saleId: prep.saleId,
            lojaId: prep.lojaId,
            origem: prep.origem,
            preparedAtEpochMs: prep.preparedAtEpochMs + 1,
            preparedSnapshot: prep.preparedSnapshot,
            snapshotHash: prep.snapshotHash,
            txItemsHash: prep.txItemsHash,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
      );

      await expectConflict(
        base.copyWith(
          prepared: PdvV1PreparedSnapshot(
            protocolVersion: prep.protocolVersion,
            operationId: prep.operationId,
            saleId: prep.saleId,
            lojaId: prep.lojaId,
            origem: prep.origem,
            preparedAtEpochMs: prep.preparedAtEpochMs,
            preparedSnapshot: prep.preparedSnapshot,
            snapshotHash: 'a' * 64,
            txItemsHash: prep.txItemsHash,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
      );

      await expectConflict(
        base.copyWith(
          prepared: PdvV1PreparedSnapshot(
            protocolVersion: prep.protocolVersion,
            operationId: prep.operationId,
            saleId: prep.saleId,
            lojaId: prep.lojaId,
            origem: prep.origem,
            preparedAtEpochMs: prep.preparedAtEpochMs,
            preparedSnapshot: prep.preparedSnapshot,
            snapshotHash: prep.snapshotHash,
            txItemsHash: 'b' * 64,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
      );

      final inner = Map<String, dynamic>.from(prep.preparedSnapshot);
      final txItems = List<Map<String, dynamic>>.from(
        inner['txItems'] as List,
      );
      txItems[0] = Map<String, dynamic>.from(txItems[0])..['quantidade'] = 9;
      inner['txItems'] = txItems;
      await expectConflict(
        base.copyWith(
          prepared: PdvV1PreparedSnapshot(
            protocolVersion: prep.protocolVersion,
            operationId: prep.operationId,
            saleId: prep.saleId,
            lojaId: prep.lojaId,
            origem: prep.origem,
            preparedAtEpochMs: prep.preparedAtEpochMs,
            preparedSnapshot: inner,
            snapshotHash: prep.snapshotHash,
            txItemsHash: prep.txItemsHash,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
      );

      await expectConflict(base.copyWith(attempts: 1));
      await expectConflict(base.copyWith(subestados: {'k': 1}));
      await expectConflict(base.copyWith(vendaHiveKey: 42));
      await expectConflict(
        base.copyWith(ultimoErroSanitizado: 'erro-teste'),
      );
    });

    test('12. pdvV1InitialPreparedRecordSemanticallyIdentical cobre flags', () {
      final a = _validInitial();
      final b = _validInitial();
      expect(pdvV1InitialPreparedRecordSemanticallyIdentical(a, b), isTrue);

      final prep = a.prepared;
      final fiadoRecord = a.copyWith(
        prepared: PdvV1PreparedSnapshot(
          protocolVersion: prep.protocolVersion,
          operationId: prep.operationId,
          saleId: prep.saleId,
          lojaId: prep.lojaId,
          origem: prep.origem,
          preparedAtEpochMs: prep.preparedAtEpochMs,
          preparedSnapshot: prep.preparedSnapshot,
          snapshotHash: prep.snapshotHash,
          txItemsHash: prep.txItemsHash,
          isFiado: true,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false,
        ),
      );
      expect(
        pdvV1InitialPreparedRecordSemanticallyIdentical(a, fiadoRecord),
        isFalse,
      );
    });
  });
}
