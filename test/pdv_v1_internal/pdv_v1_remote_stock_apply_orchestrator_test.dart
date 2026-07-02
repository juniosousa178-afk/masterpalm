import 'package:flutter_test/flutter_test.dart';
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

Map<String, dynamic> _identityEnvelopeForPrep({
  String operationId = 'op-r2b-1',
  String saleId = 'sale-r2b-1',
  String lojaId = 'loja-r2b-1',
  String origem = pdvV1OrigemProtocolValue,
  int protocolVersion = pdvV1ProtocolVersion,
  String snapshotHash = 'snap-r2b-1',
  String txItemsHash = 'tx-r2b-1',
}) {
  return {
    pdvV1PreparedSnapshotIdentityOperationIdKey: operationId,
    pdvV1PreparedSnapshotIdentitySaleIdKey: saleId,
    pdvV1PreparedSnapshotIdentityLojaIdKey: lojaId,
    pdvV1PreparedSnapshotIdentityOrigemKey: origem,
    pdvV1PreparedSnapshotIdentityProtocolVersionKey: protocolVersion,
    pdvV1PreparedSnapshotIdentitySnapshotHashKey: snapshotHash,
    pdvV1PreparedSnapshotIdentityTxItemsHashKey: txItemsHash,
  };
}

Map<String, dynamic> _innerWithIdentity(Map<String, dynamic> payload) {
  return {
    ..._identityEnvelopeForPrep(),
    ...payload,
  };
}

Map<String, dynamic> _eligibleInnerSnapshot({
  String productId = 'prod-r2b-1',
  int quantidade = 2,
  String operationId = 'op-r2b-1',
  String saleId = 'sale-r2b-1',
  String lojaId = 'loja-r2b-1',
  String origem = pdvV1OrigemProtocolValue,
  int protocolVersion = pdvV1ProtocolVersion,
  String snapshotHash = 'snap-r2b-1',
  String txItemsHash = 'tx-r2b-1',
}) {
  return {
    ..._identityEnvelopeForPrep(
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      origem: origem,
      protocolVersion: protocolVersion,
      snapshotHash: snapshotHash,
      txItemsHash: txItemsHash,
    ),
    pdvV1PreparedSnapshotTxItemsKey: [
      {
        pdvV1PreparedSnapshotSimpleItemProductIdKey: productId,
        pdvV1PreparedSnapshotSimpleItemQuantidadeKey: quantidade,
      },
    ],
  };
}

PdvV1PreparedSnapshot _prep({
  Map<String, dynamic>? inner,
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
  String operationId = 'op-r2b-1',
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: operationId,
    saleId: 'sale-r2b-1',
    lojaId: 'loja-r2b-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: inner ?? _eligibleInnerSnapshot(),
    snapshotHash: 'snap-r2b-1',
    txItemsHash: 'tx-r2b-1',
    isFiado: isFiado,
    hasCombo: hasCombo,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

PdvV1JournalRecord _pending({
  int revision = 0,
  PdvV1PreparedSnapshot? prepared,
  int attempts = 0,
  String ultimoErro = '',
}) {
  return PdvV1JournalRecord(
    prepared: prepared ?? _prep(),
    state: PdvV1JournalState.remoteStockPending,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
    attempts: attempts,
    ultimoErroSanitizado: ultimoErro,
  );
}

class _MemoryJournalRepository implements PdvV1JournalRepository {
  final Map<String, PdvV1JournalRecord> records = {};
  bool casRejectNext = false;
  int persistIfRevisionMatchesCalls = 0;

  @override
  Future<PdvV1JournalReadOutcome?> readByOperationId(String operationId) async {
    final record = records[operationId];
    if (record == null) return null;
    return PdvV1JournalReadOutcome(
      record: record,
      isMalformedReadOnly: record.isMalformedReadOnly,
    );
  }

  @override
  Future<PdvV1JournalPersistCasOutcome> persistIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalRecord candidateJournalRecord,
  }) async {
    persistIfRevisionMatchesCalls++;
    final stored = records[operationId];
    if (stored == null) {
      return PdvV1JournalPersistCasOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'not_found',
        operationId: operationId,
        stateBefore: candidateJournalRecord.state,
        stateAfter: candidateJournalRecord.state,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
      );
    }
    if (casRejectNext) {
      casRejectNext = false;
      return PdvV1JournalPersistCasOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: stored.journalRevision,
        storedRevisionAfter: stored.journalRevision,
        rejectionReasonCode: 'revision_mismatch',
        operationId: operationId,
        stateBefore: stored.state,
        stateAfter: stored.state,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
      );
    }
    if (expectedJournalRevision != stored.journalRevision) {
      return PdvV1JournalPersistCasOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: stored.journalRevision,
        storedRevisionAfter: stored.journalRevision,
        rejectionReasonCode: 'stale_journal_revision',
        operationId: operationId,
        stateBefore: stored.state,
        stateAfter: stored.state,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
      );
    }
    records[operationId] = candidateJournalRecord;
    return PdvV1JournalPersistCasOutcome(
      accepted: true,
      expectedRevision: expectedJournalRevision,
      storedRevisionBefore: stored.journalRevision,
      storedRevisionAfter: candidateJournalRecord.journalRevision,
      rejectionReasonCode: '',
      operationId: operationId,
      stateBefore: stored.state,
      stateAfter: candidateJournalRecord.state,
      recordPersisted: true,
      persistedOnlyToInjectedBox: true,
    );
  }

  @override
  Future<void> put(PdvV1JournalRecord record) async {
    records[record.operationId] = record;
  }

  @override
  Future<PdvV1JournalRecord> transition({
    required String operationId,
    required PdvV1JournalState to,
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<PdvV1JournalRecord> reconcileRemoteStockPending({
    required String operationId,
    required PdvV1RemoteStockResolution resolution,
    required int updatedAtEpochMs,
  }) =>
      throw UnimplementedError();

  @override
  Future<PdvV1JournalSameStatePatchPersistOutcome>
      persistAuthorizedSameStatePatchIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalSameStatePatch patch,
    required PdvV1JournalSameStatePatchAuthorization authorization,
  }) =>
          throw UnimplementedError();
}

class _RecordingPort implements PdvV1RemoteStockMarkerTransactionPort {
  _RecordingPort({this.forcedOutcome});

  PdvV1RemoteStockMarkerApplyOutcome? forcedOutcome;
  bool throwUnavailable = false;
  int applyCalls = 0;
  int transactionPortCalls = 0;
  PdvV1RemoteStockMarkerPlan? lastPlan;

  @override
  Future<PdvV1RemoteStockMarkerApplyOutcome> runAtomicApply({
    required PdvV1RemoteStockMarkerPlan plan,
    required Future<PdvV1RemoteStockMarkerApplyOutcome> Function(
      PdvV1RemoteStockMarkerTransactionReadWrite txn,
    ) body,
  }) async {
    applyCalls++;
    transactionPortCalls++;
    lastPlan = plan;
    if (throwUnavailable) {
      throw Exception('unavailable');
    }
    if (forcedOutcome != null) {
      return forcedOutcome!;
    }
    return body(_FakeTxn());
  }
}

class _FakeTxn implements PdvV1RemoteStockMarkerTransactionReadWrite {
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
      {pdvV1RemoteStockQuantityField: 99};

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

PdvV1RemoteStockApplyOrchestrator _orchestrator({
  required _MemoryJournalRepository repo,
  required _RecordingPort port,
}) {
  return PdvV1RemoteStockApplyOrchestrator(
    journalRepository: repo,
    executor: PdvV1RemoteStockMarkerExecutor(port),
  );
}

void _expectNoRemoteOrCasEffects({
  required _RecordingPort port,
  required _MemoryJournalRepository repo,
  required PdvV1JournalRecord before,
}) {
  expect(port.applyCalls, 0);
  expect(port.transactionPortCalls, 0);
  expect(repo.persistIfRevisionMatchesCalls, 0);
  final after = repo.records[before.prepared.operationId]!;
  expect(after.state, before.state);
  expect(after.journalRevision, before.journalRevision);
  expect(after.attempts, before.attempts);
  expect(after.ultimoErroSanitizado, before.ultimoErroSanitizado);
  expect(after.prepared.snapshotHash, before.prepared.snapshotHash);
  expect(after.prepared.txItemsHash, before.prepared.txItemsHash);
}

void main() {
  group('PdvV1RemoteStockApplyOrchestrator R2-B', () {
    test('1. pending elegível + applied avança rev 0→1 remoteStockApplied',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalAdvanced);
      expect(port.applyCalls, 1);
      expect(repo.records['op-r2b-1']!.state,
          PdvV1JournalState.remoteStockApplied);
      expect(repo.records['op-r2b-1']!.journalRevision, 1);
    });

    test('2. alreadyApplied avança journal uma vez preservando attempts/erro',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort(
          forcedOutcome: PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied);
      repo.records['op-r2b-1'] =
          _pending(attempts: 2, ultimoErro: 'erro-preservado');
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(
        result.kind,
        PdvV1RemoteStockApplyOutcomeKind.remoteAlreadyAppliedJournalAdvanced,
      );
      final stored = repo.records['op-r2b-1']!;
      expect(stored.journalRevision, 1);
      expect(stored.attempts, 2);
      expect(stored.ultimoErroSanitizado, 'erro-preservado');
    });

    test('3. journal já remoteStockApplied não chama executor', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending().copyWith(
        state: PdvV1JournalState.remoteStockApplied,
        journalRevision: 1,
      );
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 1,
      );

      expect(result.kind, PdvV1RemoteStockApplyOutcomeKind.journalNotEligible);
      expect(port.applyCalls, 0);
    });

    test('4. revision stale não chama executor', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(revision: 1);
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(
          result.kind, PdvV1RemoteStockApplyOutcomeKind.staleJournalRevision);
      expect(port.applyCalls, 0);
    });

    test('5. journal malformado não chama executor', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending().copyWith(isMalformedReadOnly: true);
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind, PdvV1RemoteStockApplyOutcomeKind.journalMalformed);
      expect(port.applyCalls, 0);
    });

    test('5b. journalNotFound direto sem efeitos', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-not-found',
        expectedJournalRevision: 0,
      );

      expect(result.kind, PdvV1RemoteStockApplyOutcomeKind.journalNotFound);
      expect(port.applyCalls, 0);
      expect(port.transactionPortCalls, 0);
      expect(repo.persistIfRevisionMatchesCalls, 0);
      expect(repo.records, isEmpty);
    });

    test('6. snapshot sem item → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(inner: const {}),
      );
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('7. snapshot com dois itens → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _innerWithIdentity({
            pdvV1PreparedSnapshotTxItemsKey: [
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: 'a',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 1,
              },
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: 'b',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 1,
              },
            ],
          }),
        ),
      );
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('8. snapshot com variação (campo extra) → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _innerWithIdentity({
            pdvV1PreparedSnapshotTxItemsKey: [
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: 'p1',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 1,
                'tamanho': 'M',
              },
            ],
          }),
        ),
      );
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('9. snapshot combo → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(prepared: _prep(hasCombo: true));
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('10. snapshot fiado → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(prepared: _prep(isFiado: true));
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('11. snapshot edição → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(prepared: _prep(isEdicao: true));
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('12. snapshot cancelamento → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] =
          _pending(prepared: _prep(isCancelamento: true));
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('13. quantidade inválida → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      for (final txItems in [
        [
          {
            pdvV1PreparedSnapshotSimpleItemProductIdKey: 'p',
            pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 0,
          },
        ],
        [
          {
            pdvV1PreparedSnapshotSimpleItemProductIdKey: 'p',
            pdvV1PreparedSnapshotSimpleItemQuantidadeKey: -1,
          },
        ],
        [
          {
            pdvV1PreparedSnapshotSimpleItemProductIdKey: 'p',
            pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 1.5,
          },
        ],
        [
          {pdvV1PreparedSnapshotSimpleItemProductIdKey: 'p'},
        ],
      ]) {
        repo.records['op-r2b-1'] = _pending(
          prepared: _prep(
            inner: _innerWithIdentity({
              pdvV1PreparedSnapshotTxItemsKey: txItems,
            }),
          ),
        );
        final orch = _orchestrator(repo: repo, port: port);
        final result = await orch.applyPendingRemoteStock(
          operationId: 'op-r2b-1',
          expectedJournalRevision: 0,
        );
        expect(result.kind,
            PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      }
      expect(port.applyCalls, 0);
    });

    test('14. productId vazio → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _innerWithIdentity({
            pdvV1PreparedSnapshotTxItemsKey: [
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: '',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 1,
              },
            ],
          }),
        ),
      );
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      expect(port.applyCalls, 0);
    });

    test('15. remoteTransactionUnavailable mantém journal pending', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort()..throwUnavailable = true;
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.remotePendingNoMutation);
      expect(port.applyCalls, 1);
      expect(repo.records['op-r2b-1']!.state,
          PdvV1JournalState.remoteStockPending);
      expect(repo.records['op-r2b-1']!.journalRevision, 0);
    });

    test('16. remoteMarkerIdentityConflict → manualRequiredNoMutation',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort(
        forcedOutcome:
            PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict,
      );
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.manualRequiredNoMutation);
      expect(repo.records['op-r2b-1']!.state,
          PdvV1JournalState.remoteStockPending);
    });

    test('17. stockDocumentInvalid → manualRequiredNoMutation', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort(
        forcedOutcome: PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid,
      );
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.manualRequiredNoMutation);
    });

    test('18. insufficientStock → manualRequiredNoMutation', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort(
        forcedOutcome: PdvV1RemoteStockMarkerApplyOutcome.insufficientStock,
      );
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.manualRequiredNoMutation);
    });

    test('19. CAS rejeitado após applied → remoteAppliedJournalNotAdvanced',
        () async {
      final repo = _MemoryJournalRepository()..casRejectNext = true;
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending();
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalNotAdvanced);
      expect(port.applyCalls, 1);
      expect(repo.records['op-r2b-1']!.state,
          PdvV1JournalState.remoteStockPending);
      expect(repo.records['op-r2b-1']!.journalRevision, 0);
    });

    test('21. inner operationId divergente → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(operationId: 'op-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('22. inner saleId divergente → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(saleId: 'sale-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('23. inner lojaId divergente → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(lojaId: 'loja-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('24. inner origem divergente → preparedSnapshotNotEligible', () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(origem: 'origem-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('25. inner protocolVersion divergente → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(protocolVersion: 99),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('26. inner snapshotHash divergente → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(snapshotHash: 'snap-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('27. inner txItemsHash divergente → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _eligibleInnerSnapshot(txItemsHash: 'tx-DIVERGENT'),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test(
        '28. campo de identidade ausente no inner → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: {
            pdvV1PreparedSnapshotTxItemsKey: [
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: 'prod-r2b-1',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 2,
              },
            ],
          },
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('29. protocolVersion string no inner → preparedSnapshotNotEligible',
        () async {
      final repo = _MemoryJournalRepository();
      final port = _RecordingPort();
      repo.records['op-r2b-1'] = _pending(
        prepared: _prep(
          inner: _innerWithIdentity({
            pdvV1PreparedSnapshotIdentityProtocolVersionKey: '1',
            pdvV1PreparedSnapshotTxItemsKey: [
              {
                pdvV1PreparedSnapshotSimpleItemProductIdKey: 'prod-r2b-1',
                pdvV1PreparedSnapshotSimpleItemQuantidadeKey: 2,
              },
            ],
          }),
        ),
      );
      final before = repo.records['op-r2b-1']!;
      final orch = _orchestrator(repo: repo, port: port);

      final result = await orch.applyPendingRemoteStock(
        operationId: 'op-r2b-1',
        expectedJournalRevision: 0,
      );

      expect(result.kind,
          PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible);
      _expectNoRemoteOrCasEffects(port: port, repo: repo, before: before);
    });

    test('20. API pública não aceita plan/stock/quantity externos', () {
      final source = PdvV1RemoteStockApplyOrchestrator(
        journalRepository: _MemoryJournalRepository(),
        executor: PdvV1RemoteStockMarkerExecutor(_RecordingPort()),
      ).applyPendingRemoteStock.toString();
      expect(source, isNot(contains('stockDocumentId')));
      expect(source, isNot(contains('quantityToDebit')));
      expect(source, isNot(contains('PdvV1RemoteStockMarkerPlan')));
    });
  });
}
