import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_initial_prepared_journal_create_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _preparedAtEpochMs = 1700000000000;
const _boxName = 'pdv_v1_initial_create_concurrency_box';

PdvV1JournalRecord _validInitial({
  String operationId = 'op-conc-001',
  int preparedAtEpochMs = _preparedAtEpochMs,
}) {
  final prepared = pdvV1PrepareSimpleSale(
    PdvV1SimpleSalePreparationInput(
      operationId: operationId,
      saleId: operationId,
      lojaId: 'loja-conc-a',
      preparedAtEpochMs: preparedAtEpochMs,
      stockDocumentId: 'prod-conc-001',
      quantidade: 1,
      saleLineCount: 1,
      stockLineCount: 1,
      isNewPdvSale: true,
      hasCombo: false,
      isFiado: false,
      isEdicao: false,
      isCancelamento: false,
      hasVariationSelection: false,
      productHasVariationDefinition: false,
      stockShapeIsKnownSimpleDirect: true,
    ),
  ).prepared!;
  return PdvV1JournalRecord.createInitial(
    prepared: prepared,
    createdAtEpochMs: preparedAtEpochMs,
  );
}

PdvV1JournalRecord _divergentInitial(String operationId) {
  final base = _validInitial(operationId: operationId);
  final prep = base.prepared;
  return PdvV1JournalRecord.createInitial(
    prepared: PdvV1PreparedSnapshot(
      protocolVersion: prep.protocolVersion,
      operationId: prep.operationId,
      saleId: prep.saleId,
      lojaId: prep.lojaId,
      origem: prep.origem,
      preparedAtEpochMs: prep.preparedAtEpochMs,
      preparedSnapshot: prep.preparedSnapshot,
      snapshotHash: 'f' * 64,
      txItemsHash: prep.txItemsHash,
      isFiado: false,
      hasCombo: false,
      isEdicao: false,
      isCancelamento: false,
    ),
    createdAtEpochMs: base.createdAtEpochMs,
  );
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'pdv_v1_initial_create_conc_',
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

  group('createInitialPreparedIfAbsent concurrency', () {
    test(
        '1. duas criações concorrentes mesmo expected: 1 created + 1 identical',
        () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      final expected = _validInitial(operationId: 'op-conc-same');

      final f1 = repo.createInitialPreparedIfAbsent(expectedInitial: expected);
      final f2 = repo.createInitialPreparedIfAbsent(expectedInitial: expected);
      final outcomes = await Future.wait([f1, f2]);

      final kinds = outcomes.map((o) => o.kind).toSet();
      expect(kinds, {
        PdvV1JournalInitialCreateOutcomeKind.created,
        PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical,
      });
      expect(
        pdvV1InitialPreparedRecordSemanticallyIdentical(
          (await repo.readByOperationId('op-conc-same'))!.record,
          expected,
        ),
        isTrue,
      );
    });

    test(
        '2. duas criações concorrentes expected divergente: 1 created + 1 conflict',
        () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      const opId = 'op-conc-diff';
      final first = _validInitial(operationId: opId);
      final second = _divergentInitial(opId);

      final f1 = repo.createInitialPreparedIfAbsent(expectedInitial: first);
      final f2 = repo.createInitialPreparedIfAbsent(expectedInitial: second);
      final outcomes = await Future.wait([f1, f2]);

      final kinds = outcomes.map((o) => o.kind).toSet();
      expect(kinds, {
        PdvV1JournalInitialCreateOutcomeKind.created,
        PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
      });

      final stored = (await repo.readByOperationId(opId))!.record;
      final createdOutcome = outcomes.firstWhere(
        (o) => o.kind == PdvV1JournalInitialCreateOutcomeKind.created,
      );
      expect(
        pdvV1InitialPreparedRecordSemanticallyIdentical(
          stored,
          createdOutcome.record!,
        ),
        isTrue,
      );
    });

    test('3. operationIds diferentes: ambas created sem cruzamento', () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      final a = _validInitial(operationId: 'op-conc-a');
      final b = _validInitial(operationId: 'op-conc-b');

      final outcomes = await Future.wait([
        repo.createInitialPreparedIfAbsent(expectedInitial: a),
        repo.createInitialPreparedIfAbsent(expectedInitial: b),
      ]);

      expect(
        outcomes.every(
          (o) => o.kind == PdvV1JournalInitialCreateOutcomeKind.created,
        ),
        isTrue,
      );
      expect(await repo.readByOperationId('op-conc-a'), isNotNull);
      expect(await repo.readByOperationId('op-conc-b'), isNotNull);
    });

    test('4. fila recupera após falha de transition e create prossegue',
        () async {
      final repo = PdvV1HiveJournalRepository(box: box);
      const opId = 'op-conc-recover';

      await expectLater(
        repo.transition(
          operationId: opId,
          to: PdvV1JournalState.remoteStockPending,
          updatedAtEpochMs: _preparedAtEpochMs,
        ),
        throwsA(isA<PdvV1ValidationError>()),
      );

      final outcome = await repo.createInitialPreparedIfAbsent(
        expectedInitial: _validInitial(operationId: opId),
      );

      expect(outcome.kind, PdvV1JournalInitialCreateOutcomeKind.created);
      expect(await repo.readByOperationId(opId), isNotNull);
    });

    test('5. mutadores públicos entram no mesmo gate por operationId', () {
      final source = File(
        'lib/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart',
      ).readAsStringSync();

      expect(source, contains('_runSerializedMutation'));
      expect(source, contains('_mutationTailsByOperationId'));

      for (final method in [
        'Future<void> put(',
        'Future<PdvV1JournalRecord> transition(',
        'Future<PdvV1JournalRecord> reconcileRemoteStockPending(',
        'Future<PdvV1JournalInitialCreateOutcome> createInitialPreparedIfAbsent(',
        'Future<PdvV1JournalPersistCasOutcome> persistIfRevisionMatches(',
        'persistAuthorizedSameStatePatchIfRevisionMatches(',
      ]) {
        expect(source, contains(method), reason: method);
      }

      final putBody =
          source.split('Future<void> put(')[1].split('@override')[0];
      expect(putBody, contains('_runSerializedMutation'));

      expect(source, isNot(contains('Future.delayed')));
      expect(source, isNot(contains('Timer')));
    });
  });
}
