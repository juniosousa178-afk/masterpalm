import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_canonical_json.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_prepared_journal_writer.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _preparedAtEpochMs = 1700000000000;
const _boxName = 'pdv_v1_prepared_journal_writer_roundtrip_box';

PdvV1SimpleSalePreparationResult _canonicalPreparation() {
  return pdvV1PrepareSimpleSale(
    PdvV1SimpleSalePreparationInput(
      operationId: 'op-roundtrip-001',
      saleId: 'op-roundtrip-001',
      lojaId: 'loja-roundtrip-a',
      preparedAtEpochMs: _preparedAtEpochMs,
      stockDocumentId: 'prod-roundtrip-001',
      quantidade: 2,
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
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'pdv_v1_prepared_journal_writer_roundtrip_',
    );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(_boxName)) {
      await Hive.box<dynamic>(_boxName).close();
      await Hive.deleteBoxFromDisk(_boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PdvV1PreparedJournalWriter Hive roundtrip', () {
    test('1. preparador → writer → Hive → reopen preserva prepared', () async {
      final box = await Hive.openBox<dynamic>(_boxName);
      final repo = PdvV1HiveJournalRepository(box: box);
      final writer = PdvV1PreparedJournalWriter(
        initialPreparedJournalCreateRepository: repo,
      );
      final preparation = _canonicalPreparation();

      final written = await writer.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(written.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWritten);
      await box.close();

      final reopenedBox = await Hive.openBox<dynamic>(_boxName);
      final reopenedRepo = PdvV1HiveJournalRepository(box: reopenedBox);
      final outcome = await reopenedRepo.readByOperationId('op-roundtrip-001');

      expect(outcome, isNotNull);
      expect(outcome!.isMalformedReadOnly, isFalse);
      expect(outcome.record.state, PdvV1JournalState.prepared);
      expect(outcome.record.journalRevision, 0);
      expect(outcome.record.operationId, outcome.record.saleId);
      expect(outcome.record.prepared.operationId, 'op-roundtrip-001');
      expect(outcome.record.prepared.origemProtocol, 'pdv');
      expect(outcome.record.prepared.isFiado, isFalse);
      expect(outcome.record.prepared.hasCombo, isFalse);
      expect(outcome.record.prepared.isEdicao, isFalse);
      expect(outcome.record.prepared.isCancelamento, isFalse);
      expect(outcome.record.prepared.preparedAtEpochMs, _preparedAtEpochMs);

      final inner = outcome.record.prepared.preparedSnapshot;
      expect(inner.keys.toSet(), {
        'protocolVersion',
        'operationId',
        'saleId',
        'lojaId',
        'origem',
        'snapshotHash',
        'txItemsHash',
        'txItems',
      });
      expect((inner['txItems'] as List).length, 1);

      final expectedInnerJson = pdvV1CanonicalJsonEncode(
        preparation.prepared!.preparedSnapshot,
      );
      final reopenedInnerJson = pdvV1CanonicalJsonEncode(inner);
      expect(reopenedInnerJson, expectedInnerJson);

      expect(
        outcome.record.state,
        isNot(PdvV1JournalState.remoteStockPending),
      );
    });

    test('2. reexecução após reopen retorna alreadyExists sem alteração',
        () async {
      final box = await Hive.openBox<dynamic>(_boxName);
      final repo = PdvV1HiveJournalRepository(box: box);
      final writer = PdvV1PreparedJournalWriter(
        initialPreparedJournalCreateRepository: repo,
      );
      final preparation = _canonicalPreparation();

      await writer.writeInitialPreparedJournal(preparation: preparation);
      await box.close();

      final reopenedBox = await Hive.openBox<dynamic>(_boxName);
      final reopenedRepo = PdvV1HiveJournalRepository(box: reopenedBox);
      final reopenedWriter = PdvV1PreparedJournalWriter(
        initialPreparedJournalCreateRepository: reopenedRepo,
      );

      final before = await reopenedRepo.readByOperationId('op-roundtrip-001');
      final again = await reopenedWriter.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(
        again.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalAlreadyExists,
      );
      final after = await reopenedRepo.readByOperationId('op-roundtrip-001');
      expect(
        pdvV1CanonicalJsonEncode(after!.record.toJson()),
        pdvV1CanonicalJsonEncode(before!.record.toJson()),
      );
      expect(after.record.state, PdvV1JournalState.prepared);
      expect(after.record.journalRevision, 0);
    });

    test('3. journal divergente após reopen retorna conflict sem overwrite',
        () async {
      final box = await Hive.openBox<dynamic>(_boxName);
      final repo = PdvV1HiveJournalRepository(box: box);
      final writer = PdvV1PreparedJournalWriter(
        initialPreparedJournalCreateRepository: repo,
      );
      final preparation = _canonicalPreparation();

      await writer.writeInitialPreparedJournal(preparation: preparation);
      await box.close();

      final reopenedBox = await Hive.openBox<dynamic>(_boxName);
      final reopenedRepo = PdvV1HiveJournalRepository(box: reopenedBox);

      final divergentPrep = pdvV1PrepareSimpleSale(
        PdvV1SimpleSalePreparationInput(
          operationId: 'op-roundtrip-001',
          saleId: 'op-roundtrip-001',
          lojaId: 'loja-roundtrip-a',
          preparedAtEpochMs: _preparedAtEpochMs,
          stockDocumentId: 'prod-roundtrip-001',
          quantidade: 5,
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
      );

      final reopenedWriter = PdvV1PreparedJournalWriter(
        initialPreparedJournalCreateRepository: reopenedRepo,
      );
      final conflict = await reopenedWriter.writeInitialPreparedJournal(
        preparation: divergentPrep,
      );

      expect(conflict.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalConflict);

      final stored = await reopenedRepo.readByOperationId('op-roundtrip-001');
      expect(stored!.record.prepared.txItemsHash,
          preparation.prepared!.txItemsHash);
      expect(stored.record.journalRevision, 0);
      expect(stored.record.state, PdvV1JournalState.prepared);
    });
  });
}
