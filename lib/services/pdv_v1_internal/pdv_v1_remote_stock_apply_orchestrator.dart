import 'pdv_v1_journal_record.dart';
import 'pdv_v1_journal_repository.dart';
import 'pdv_v1_remote_stock_apply_models.dart';
import 'pdv_v1_remote_stock_marker_executor.dart';
import 'pdv_v1_remote_stock_marker_models.dart';

/// Orquestrador interno R2-B — uma operação `remoteStockPending` por invocação.
class PdvV1RemoteStockApplyOrchestrator {
  PdvV1RemoteStockApplyOrchestrator({
    required PdvV1JournalRepository journalRepository,
    required PdvV1RemoteStockMarkerExecutor executor,
  })  : _journalRepository = journalRepository,
        _executor = executor;

  final PdvV1JournalRepository _journalRepository;
  final PdvV1RemoteStockMarkerExecutor _executor;

  Future<PdvV1RemoteStockApplyResult> applyPendingRemoteStock({
    required String operationId,
    required int expectedJournalRevision,
  }) async {
    final readOutcome = await _journalRepository.readByOperationId(operationId);
    if (readOutcome == null) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.journalNotFound,
      );
    }
    if (readOutcome.isMalformedReadOnly) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.journalMalformed,
      );
    }

    final record = readOutcome.record;
    if (record.journalRevision != expectedJournalRevision) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.staleJournalRevision,
      );
    }
    if (record.state != PdvV1JournalState.remoteStockPending) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.journalNotEligible,
      );
    }

    if (!pdvV1PreparedSnapshotIdentityEnvelopeMatchesJournal(record.prepared)) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible,
      );
    }

    final derivation = pdvV1DeriveRemoteStockMarkerPlan(record.prepared);
    if (!derivation.eligible || derivation.plan == null) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.preparedSnapshotNotEligible,
      );
    }

    final applyResult = await _executor.applyOnce(derivation.plan!);

    switch (applyResult.outcome) {
      case PdvV1RemoteStockMarkerApplyOutcome.applied:
        return _persistApplied(
          record: record,
          kind: PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalAdvanced,
        );
      case PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied:
        return _persistApplied(
          record: record,
          kind: PdvV1RemoteStockApplyOutcomeKind
              .remoteAlreadyAppliedJournalAdvanced,
        );
      case PdvV1RemoteStockMarkerApplyOutcome.remoteTransactionUnavailable:
        return const PdvV1RemoteStockApplyResult(
          kind: PdvV1RemoteStockApplyOutcomeKind.remotePendingNoMutation,
        );
      case PdvV1RemoteStockMarkerApplyOutcome.remoteMarkerIdentityConflict:
      case PdvV1RemoteStockMarkerApplyOutcome.stockDocumentInvalid:
      case PdvV1RemoteStockMarkerApplyOutcome.insufficientStock:
        return const PdvV1RemoteStockApplyResult(
          kind: PdvV1RemoteStockApplyOutcomeKind.manualRequiredNoMutation,
        );
    }
  }

  Future<PdvV1RemoteStockApplyResult> _persistApplied({
    required PdvV1JournalRecord record,
    required PdvV1RemoteStockApplyOutcomeKind kind,
  }) async {
    final candidate = record.copyWith(
      state: PdvV1JournalState.remoteStockApplied,
      journalRevision: record.journalRevision + 1,
    );

    final cas = await _journalRepository.persistIfRevisionMatches(
      operationId: record.operationId,
      expectedJournalRevision: record.journalRevision,
      candidateJournalRecord: candidate,
    );

    if (!cas.accepted) {
      return const PdvV1RemoteStockApplyResult(
        kind: PdvV1RemoteStockApplyOutcomeKind.remoteAppliedJournalNotAdvanced,
      );
    }

    return PdvV1RemoteStockApplyResult(kind: kind);
  }
}
