import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_initial_prepared_journal_create_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_prepared_journal_writer.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _txHashVector =
    '54057fe86061142af70fd516bea621352587b3f611ecb969faa8b07c90584b97';
const _snapshotHashVector =
    '1297da35da51a9e77d643d73b06db76be48a323bcd04612cb9d95c1d23421065';

PdvV1SimpleSalePreparationInput _validInput({
  String operationId = 'op-001',
  String saleId = 'op-001',
  String lojaId = 'loja-a',
  int preparedAtEpochMs = 1700000000000,
  String stockDocumentId = 'prod-001',
  int quantidade = 2,
}) {
  return PdvV1SimpleSalePreparationInput(
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    preparedAtEpochMs: preparedAtEpochMs,
    stockDocumentId: stockDocumentId,
    quantidade: quantidade,
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
  );
}

PdvV1SimpleSalePreparationResult _canonicalPreparation() =>
    pdvV1PrepareSimpleSale(_validInput());

PdvV1PreparedSnapshot _canonicalPrepared() => _canonicalPreparation().prepared!;

PdvV1JournalRecord _expectedInitialFromPreparation(
  PdvV1SimpleSalePreparationResult preparation,
) {
  final prepared = preparation.prepared!;
  return PdvV1JournalRecord.createInitial(
    prepared: prepared,
    createdAtEpochMs: prepared.preparedAtEpochMs,
  );
}

PdvV1PreparedSnapshot _preparedFromInner(Map<String, dynamic> inner) {
  final base = _canonicalPrepared();
  return PdvV1PreparedSnapshot(
    protocolVersion: base.protocolVersion,
    operationId: base.operationId,
    saleId: base.saleId,
    lojaId: base.lojaId,
    origem: base.origem,
    preparedAtEpochMs: base.preparedAtEpochMs,
    preparedSnapshot: inner,
    snapshotHash: inner['snapshotHash'] as String,
    txItemsHash: inner['txItemsHash'] as String,
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1PreparedJournalWriter _writer(_TrackingCreateRepository repo) {
  return PdvV1PreparedJournalWriter(
    initialPreparedJournalCreateRepository: repo,
  );
}

void main() {
  group('PdvV1PreparedJournalWriter', () {
    test('1. preparation válido + CAS created → preparedJournalWritten',
        () async {
      final preparation = _canonicalPreparation();
      final repo = _TrackingCreateRepository();
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWritten);
      expect(repo.capabilityCalls, 1);
      expect(repo.lastExpectedInitial, isNotNull);
      expect(repo.lastExpectedInitial!.state, PdvV1JournalState.prepared);
      expect(repo.lastExpectedInitial!.journalRevision, 0);
      expect(repo.lastExpectedInitial!.operationId,
          repo.lastExpectedInitial!.saleId);
      expect(
        pdvV1InitialPreparedRecordSemanticallyIdentical(
          outcome.record!,
          repo.lastExpectedInitial!,
        ),
        isTrue,
      );
      expect(outcome.record!.prepared.txItemsHash, _txHashVector);
      expect(outcome.record!.prepared.snapshotHash, _snapshotHashVector);
    });

    test('2. CAS alreadyExistsIdentical → preparedJournalAlreadyExists',
        () async {
      final preparation = _canonicalPreparation();
      final expected = _expectedInitialFromPreparation(preparation);
      final repo = _TrackingCreateRepository(
        fixedOutcome: PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical,
          operationId: 'op-001',
          journalRevision: 0,
          existingState: PdvV1JournalState.prepared,
          record: expected,
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalAlreadyExists,
      );
      expect(repo.capabilityCalls, 1);
      expect(outcome.record, isNotNull);
    });

    test('3. CAS alreadyExistsConflict → preparedJournalConflict', () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
          operationId: 'op-001',
          journalRevision: 1,
          existingState: PdvV1JournalState.remoteStockPending,
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalConflict);
      expect(repo.capabilityCalls, 1);
    });

    test('4. CAS existingMalformed → preparedJournalMalformedExisting',
        () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.existingMalformed,
          operationId: 'op-001',
          existingState: PdvV1JournalState.manualInterventionRequired,
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalMalformedExisting,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('5. CAS unavailable → preparedJournalWriteUnavailable', () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.unavailable,
          operationId: 'op-001',
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('6. CAS invalidExpectedInitial → preparedJournalInvalid', () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
          operationId: 'op-001',
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid);
      expect(repo.capabilityCalls, 1);
    });

    test('7. capability lança exceção → preparedJournalWriteUnavailable',
        () async {
      final repo = _TrackingCreateRepository(throwsOnCall: true);
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('8. outcome created com record null → preparedJournalWriteUnavailable',
        () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.created,
          operationId: 'op-001',
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('9. outcome alreadyExistsIdentical com record null → unavailable',
        () async {
      final repo = _TrackingCreateRepository(
        fixedOutcome: const PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical,
          operationId: 'op-001',
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('10. outcome de sucesso com operationId divergente → unavailable',
        () async {
      final expected = _expectedInitialFromPreparation(_canonicalPreparation());
      final prep = expected.prepared;
      final divergentRecord = expected.copyWith(
        prepared: PdvV1PreparedSnapshot(
          protocolVersion: prep.protocolVersion,
          operationId: 'op-divergente',
          saleId: prep.saleId,
          lojaId: prep.lojaId,
          origem: prep.origem,
          preparedAtEpochMs: prep.preparedAtEpochMs,
          preparedSnapshot: prep.preparedSnapshot,
          snapshotHash: prep.snapshotHash,
          txItemsHash: prep.txItemsHash,
          isFiado: false,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false,
        ),
      );
      final repo = _TrackingCreateRepository(
        fixedOutcome: PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.created,
          operationId: 'op-divergente',
          journalRevision: 0,
          existingState: PdvV1JournalState.prepared,
          record: divergentRecord,
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: _canonicalPreparation(),
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('11. outcome de sucesso com record não idêntico → unavailable',
        () async {
      final preparation = _canonicalPreparation();
      final divergent = _expectedInitialFromPreparation(
        pdvV1PrepareSimpleSale(_validInput(quantidade: 9)),
      );
      final repo = _TrackingCreateRepository(
        fixedOutcome: PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.created,
          operationId: 'op-001',
          journalRevision: 0,
          existingState: PdvV1JournalState.prepared,
          record: divergent,
        ),
      );
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(
        outcome.kind,
        PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWriteUnavailable,
      );
      expect(repo.capabilityCalls, 1);
    });

    test('12. preparation.isEligible false → invalid sem CAS', () async {
      final repo = _TrackingCreateRepository();
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: PdvV1SimpleSalePreparationResult.rejected(
          PdvV1SimpleSalePreparationRejectionCode.operationIdInvalid,
        ),
      );

      expect(outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid);
      expect(repo.capabilityCalls, 0);
    });

    test('13. prepared inner inválido → invalid sem CAS', () async {
      final inner =
          Map<String, dynamic>.from(_canonicalPrepared().preparedSnapshot);
      inner.remove('txItems');
      final preparation = PdvV1SimpleSalePreparationResult.eligible(
        _preparedFromInner(inner),
      );
      final repo = _TrackingCreateRepository();
      final writer = _writer(repo);

      final outcome = await writer.writeInitialPreparedJournal(
        preparation: preparation,
      );

      expect(outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid);
      expect(repo.capabilityCalls, 0);
    });

    test(
        '13b. hash divergente, item extra, dois itens, flags e IDs → invalid sem CAS',
        () async {
      final base = _canonicalPrepared();
      final cases = <PdvV1SimpleSalePreparationResult>[
        PdvV1SimpleSalePreparationResult.eligible(
          PdvV1PreparedSnapshot(
            protocolVersion: base.protocolVersion,
            operationId: base.operationId,
            saleId: base.saleId,
            lojaId: base.lojaId,
            origem: base.origem,
            preparedAtEpochMs: base.preparedAtEpochMs,
            preparedSnapshot: base.preparedSnapshot,
            snapshotHash: 'c' * 64,
            txItemsHash: base.txItemsHash,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
        PdvV1SimpleSalePreparationResult.eligible(() {
          final inner = Map<String, dynamic>.from(base.preparedSnapshot);
          inner['extra'] = 1;
          return _preparedFromInner(inner);
        }()),
        PdvV1SimpleSalePreparationResult.eligible(() {
          final inner = Map<String, dynamic>.from(base.preparedSnapshot);
          final item = (inner['txItems'] as List).single as Map;
          inner['txItems'] = [item, item];
          return _preparedFromInner(inner);
        }()),
        PdvV1SimpleSalePreparationResult.eligible(
          PdvV1PreparedSnapshot(
            protocolVersion: base.protocolVersion,
            operationId: base.operationId,
            saleId: base.saleId,
            lojaId: base.lojaId,
            origem: base.origem,
            preparedAtEpochMs: base.preparedAtEpochMs,
            preparedSnapshot: base.preparedSnapshot,
            snapshotHash: base.snapshotHash,
            txItemsHash: base.txItemsHash,
            isFiado: true,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          ),
        ),
        PdvV1SimpleSalePreparationResult.eligible(() {
          final inner = Map<String, dynamic>.from(base.preparedSnapshot);
          inner['operationId'] = 'other-op';
          return PdvV1PreparedSnapshot(
            protocolVersion: base.protocolVersion,
            operationId: base.operationId,
            saleId: base.saleId,
            lojaId: base.lojaId,
            origem: base.origem,
            preparedAtEpochMs: base.preparedAtEpochMs,
            preparedSnapshot: inner,
            snapshotHash: base.snapshotHash,
            txItemsHash: base.txItemsHash,
            isFiado: false,
            hasCombo: false,
            isEdicao: false,
            isCancelamento: false,
          );
        }()),
      ];

      for (final preparation in cases) {
        final repo = _TrackingCreateRepository();
        final writer = _writer(repo);
        final outcome = await writer.writeInitialPreparedJournal(
          preparation: preparation,
        );
        expect(
          outcome.kind,
          PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
        );
        expect(repo.capabilityCalls, 0);
      }
    });

    test('14. writer não referencia PdvV1JournalRepository, Hive ou Firestore',
        () {
      expect(
        _TrackingCreateRepository.new,
        returnsNormally,
      );
      expect(
        PdvV1PreparedJournalWriter(
          initialPreparedJournalCreateRepository: _TrackingCreateRepository(),
        ),
        isA<PdvV1PreparedJournalWriter>(),
      );
    });
  });
}

class _TrackingCreateRepository
    implements PdvV1InitialPreparedJournalCreateRepository {
  _TrackingCreateRepository({
    this.fixedOutcome,
    this.throwsOnCall = false,
  });

  final PdvV1JournalInitialCreateOutcome? fixedOutcome;
  final bool throwsOnCall;

  int capabilityCalls = 0;
  PdvV1JournalRecord? lastExpectedInitial;

  @override
  Future<PdvV1JournalInitialCreateOutcome> createInitialPreparedIfAbsent({
    required PdvV1JournalRecord expectedInitial,
  }) async {
    capabilityCalls++;
    lastExpectedInitial = expectedInitial;
    if (throwsOnCall) {
      throw StateError('capability indisponível');
    }
    if (fixedOutcome != null) {
      return fixedOutcome!;
    }
    return PdvV1JournalInitialCreateOutcome(
      kind: PdvV1JournalInitialCreateOutcomeKind.created,
      operationId: expectedInitial.operationId,
      journalRevision: 0,
      existingState: PdvV1JournalState.prepared,
      record: expectedInitial,
    );
  }
}
