import 'pdv_v1_hive_upsert_policy.dart';
import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_recovery_models.dart';

/// Orquestrador puro de recovery — apenas planeja decisões, sem I/O.
class PdvV1RecoveryOrchestrator {
  PdvV1RecoveryOrchestrator({
    PdvV1HiveUpsertPolicy? hiveUpsertPolicy,
  }) : _hiveUpsertPolicy = hiveUpsertPolicy ?? const PdvV1HiveUpsertPolicy();

  final PdvV1HiveUpsertPolicy _hiveUpsertPolicy;

  PdvV1RecoveryPlan plan(PdvV1RecoveryOrchestratorInput input) {
    final context = input.context;
    final evidence = input.evidence;
    final outcome = input.journalOutcome;

    if (outcome == null) {
      if (context.markerPresentWithoutJournal ||
          (evidence?.optionalMarker.presente == true)) {
        return _manualPlan(
          evidence: evidence,
          currentState: PdvV1JournalState.manualInterventionRequired,
          operationId: evidence?.requestedOperationId ?? '',
          saleId: evidence?.requestedSaleId ?? '',
          reasonCode: 'marker_without_journal',
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        );
      }
      return _invalidPlan(
        evidence: evidence,
        reasonCode: 'journal_absent',
        operationId: evidence?.requestedOperationId ?? '',
        saleId: evidence?.requestedSaleId ?? '',
      );
    }

    if (outcome.isMalformedReadOnly) {
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.manualInterventionRequired,
        currentState: PdvV1JournalState.manualInterventionRequired,
        targetState: PdvV1JournalState.manualInterventionRequired,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.preserveMalformedEvidence,
          PdvV1RecoveryPlannedAction.surfaceManualIntervention,
        ],
        reasonCode: pdvV1MalformedRecoveryReasonCode,
        operationId: '',
        saleId: '',
        journalRevisionAtPlan: outcome.record.journalRevision,
        journalIdentity: pdvV1MalformedSafeJournalIdentity(),
        isManualIntervention: true,
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: 'malformed',
          currentState: PdvV1JournalState.manualInterventionRequired,
          decision: PdvV1RecoveryDecision.manualInterventionRequired,
          targetState: PdvV1JournalState.manualInterventionRequired,
        ),
      );
    }

    final record = outcome.record;
    final state = record.state;
    final prep = record.prepared;
    final opId = record.operationId;
    final saleId = record.saleId;

    if (_scopeBlocked(prep)) {
      return _manualPlan(
        record: record,
        currentState: state,
        operationId: opId,
        saleId: saleId,
        reasonCode: 'scope_not_supported_7ab',
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
      );
    }

    if (state == PdvV1JournalState.operationCompleted ||
        state == PdvV1JournalState.manualInterventionRequired) {
      if (evidence != null) {
        return _manualPlan(
          record: record,
          currentState: state,
          operationId: opId,
          saleId: saleId,
          reasonCode: pdvV1UnexpectedRemoteEvidenceReasonCode,
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        );
      }
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.noAction,
        currentState: state,
        targetState: state,
        plannedActions: const [],
        reasonCode: 'terminal_state',
        operationId: opId,
        saleId: saleId,
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: opId,
          currentState: state,
          decision: PdvV1RecoveryDecision.noAction,
          targetState: state,
        ),
      );
    }

    final remoteRequirement = pdvV1DeriveRemoteVerificationRequirement(
      record: record,
    );

    if (remoteRequirement ==
        PdvV1RemoteVerificationRequirement.requiredForRecovery) {
      if (evidence == null) {
        return _invalidPlan(
          record: record,
          reasonCode: 'evidence_required',
          operationId: opId,
          saleId: saleId,
          currentState: state,
        );
      }

      final validation = evidence.validateAgainstJournal(record);
      if (!validation.valid &&
          evidence.verificationStatus !=
              PdvV1RemoteVerificationStatus.markerDivergentOrInvalid) {
        return _manualPlan(
          record: record,
          currentState: state,
          operationId: opId,
          saleId: saleId,
          reasonCode: validation.reasonCode,
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        );
      }

      switch (state) {
        case PdvV1JournalState.prepared:
          return _planPrepared(record, evidence, validation);
        case PdvV1JournalState.remoteStockPending:
          return _planRemoteStockPending(record, evidence, validation);
        default:
          return _invalidPlan(
            record: record,
            reasonCode: 'evidence_required',
            operationId: opId,
            saleId: saleId,
            currentState: state,
          );
      }
    }

    if (evidence != null &&
        remoteRequirement ==
            PdvV1RemoteVerificationRequirement.notRequiredForCurrentState) {
      return _manualPlan(
        record: record,
        currentState: state,
        operationId: opId,
        saleId: saleId,
        reasonCode: pdvV1UnexpectedRemoteEvidenceReasonCode,
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
      );
    }

    switch (state) {
      case PdvV1JournalState.remoteStockApplied:
        return _planRemoteStockApplied(record, input.hiveMatches);
      case PdvV1JournalState.hiveSaleCompleted:
        return _planHiveSaleCompleted(record);
      case PdvV1JournalState.hiveSalePending:
      case PdvV1JournalState.saleSyncPending:
      case PdvV1JournalState.saleSyncCompleted:
      case PdvV1JournalState.effectsPending:
      case PdvV1JournalState.effectsCompleted:
        return _requireIntegrationPlan(
          record: record,
          reasonCode: 'state_requires_integration',
        );
      case PdvV1JournalState.prepared:
      case PdvV1JournalState.remoteStockPending:
        return _invalidPlan(
          record: record,
          reasonCode: 'evidence_required',
          operationId: opId,
          saleId: saleId,
          currentState: state,
        );
      case PdvV1JournalState.operationCompleted:
      case PdvV1JournalState.manualInterventionRequired:
        return PdvV1RecoveryPlan(
          decision: PdvV1RecoveryDecision.noAction,
          currentState: state,
          targetState: state,
          plannedActions: const [],
          reasonCode: 'terminal_state',
          operationId: opId,
          saleId: saleId,
          journalRevisionAtPlan: record.journalRevision,
          journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
          idempotencyKey: pdvV1BuildIdempotencyKey(
            operationId: opId,
            currentState: state,
            decision: PdvV1RecoveryDecision.noAction,
            targetState: state,
          ),
        );
    }
  }

  PdvV1RecoveryPlan _planPrepared(
    PdvV1JournalRecord record,
    PdvV1RemoteVerificationEvidence evidence,
    PdvV1EvidenceValidationResult validation,
  ) {
    final opId = record.operationId;
    final saleId = record.saleId;
    if (evidence.verificationStatus ==
            PdvV1RemoteVerificationStatus.markerAbsentVerified &&
        validation.valid) {
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.replanRemoteStockTransaction,
        currentState: PdvV1JournalState.prepared,
        targetState: PdvV1JournalState.prepared,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ],
        reasonCode: 'prepared_replan_remote_stock',
        operationId: opId,
        saleId: saleId,
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        requiresExternalIntegration: true,
        evidenceValidated: true,
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: opId,
          currentState: PdvV1JournalState.prepared,
          decision: PdvV1RecoveryDecision.replanRemoteStockTransaction,
          targetState: PdvV1JournalState.prepared,
        ),
      );
    }
    return _manualPlan(
      record: record,
      currentState: PdvV1JournalState.prepared,
      operationId: opId,
      saleId: saleId,
      reasonCode: validation.valid
          ? 'prepared_evidence_incompatible'
          : validation.reasonCode,
      actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
    );
  }

  PdvV1RecoveryPlan _planRemoteStockPending(
    PdvV1JournalRecord record,
    PdvV1RemoteVerificationEvidence evidence,
    PdvV1EvidenceValidationResult validation,
  ) {
    final opId = record.operationId;
    final saleId = record.saleId;

    if (evidence.verificationStatus ==
        PdvV1RemoteVerificationStatus.markerVerificationUnavailable) {
      if (!validation.valid) {
        return _manualPlan(
          record: record,
          currentState: PdvV1JournalState.remoteStockPending,
          operationId: opId,
          saleId: saleId,
          reasonCode: validation.reasonCode,
          actions: const [
            PdvV1RecoveryPlannedAction.surfaceManualIntervention,
          ],
        );
      }
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.deferUntilVerification,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.remoteStockPending,
        plannedActions: const [PdvV1RecoveryPlannedAction.verifyMarkerAgain],
        reasonCode: 'verification_unavailable_deferred',
        operationId: opId,
        saleId: saleId,
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        isDeferred: true,
        evidenceValidated: true,
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: opId,
          currentState: PdvV1JournalState.remoteStockPending,
          decision: PdvV1RecoveryDecision.deferUntilVerification,
          targetState: PdvV1JournalState.remoteStockPending,
        ),
      );
    }

    if (evidence.verificationStatus ==
            PdvV1RemoteVerificationStatus.markerAbsentVerified &&
        validation.valid) {
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.replanRemoteStockTransaction,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.prepared,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
          PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture,
        ],
        reasonCode: 'pending_marker_absent_replan',
        operationId: opId,
        saleId: saleId,
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        requiresExternalIntegration: true,
        evidenceValidated: true,
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: opId,
          currentState: PdvV1JournalState.remoteStockPending,
          decision: PdvV1RecoveryDecision.replanRemoteStockTransaction,
          targetState: PdvV1JournalState.prepared,
        ),
      );
    }

    if (evidence.verificationStatus ==
            PdvV1RemoteVerificationStatus.markerAppliedCompatible &&
        validation.valid) {
      return PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.remoteStockApplied,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture,
        ],
        reasonCode: 'pending_marker_applied',
        operationId: opId,
        saleId: saleId,
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        evidenceValidated: true,
        idempotencyKey: pdvV1BuildIdempotencyKey(
          operationId: opId,
          currentState: PdvV1JournalState.remoteStockPending,
          decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
          targetState: PdvV1JournalState.remoteStockApplied,
        ),
      );
    }

    return _manualPlan(
      record: record,
      currentState: PdvV1JournalState.remoteStockPending,
      operationId: opId,
      saleId: saleId,
      reasonCode: evidence.verificationStatus ==
              PdvV1RemoteVerificationStatus.markerDivergentOrInvalid
          ? (evidence.divergentReason.isNotEmpty
              ? 'marker_divergent'
              : validation.reasonCode)
          : validation.reasonCode.isNotEmpty
              ? validation.reasonCode
              : 'pending_evidence_incompatible',
      actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
    );
  }

  PdvV1RecoveryPlan _planRemoteStockApplied(
    PdvV1JournalRecord record,
    List<PdvV1HiveSaleMatch> hiveMatches,
  ) {
    final opId = record.operationId;
    final saleId = record.saleId;
    final prep = record.prepared;
    final hiveResult = _hiveUpsertPolicy.decide(
      saleId: saleId,
      snapshotHash: prep.snapshotHash,
      found: hiveMatches,
    );

    switch (hiveResult.decision) {
      case PdvV1HiveUpsertDecision.insertOnce:
        return PdvV1RecoveryPlan(
          decision: PdvV1RecoveryDecision.insertHiveSaleOnce,
          currentState: PdvV1JournalState.remoteStockApplied,
          targetState: PdvV1JournalState.hiveSalePending,
          plannedActions: const [
            PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          ],
          reasonCode: 'hive_insert_once',
          operationId: opId,
          saleId: saleId,
          journalRevisionAtPlan: record.journalRevision,
          journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
          requiresExternalIntegration: true,
          idempotencyKey: pdvV1BuildIdempotencyKey(
            operationId: opId,
            currentState: PdvV1JournalState.remoteStockApplied,
            decision: PdvV1RecoveryDecision.insertHiveSaleOnce,
            targetState: PdvV1JournalState.hiveSalePending,
          ),
        );
      case PdvV1HiveUpsertDecision.reuseExisting:
        return PdvV1RecoveryPlan(
          decision: PdvV1RecoveryDecision.reuseExistingHiveSale,
          currentState: PdvV1JournalState.remoteStockApplied,
          targetState: PdvV1JournalState.hiveSaleCompleted,
          plannedActions: const [
            PdvV1RecoveryPlannedAction.planReuseHiveSaleFuture,
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          ],
          reasonCode: 'hive_reuse_existing',
          operationId: opId,
          saleId: saleId,
          journalRevisionAtPlan: record.journalRevision,
          journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
          requiresExternalIntegration: true,
          idempotencyKey: pdvV1BuildIdempotencyKey(
            operationId: opId,
            currentState: PdvV1JournalState.remoteStockApplied,
            decision: PdvV1RecoveryDecision.reuseExistingHiveSale,
            targetState: PdvV1JournalState.hiveSaleCompleted,
          ),
        );
      case PdvV1HiveUpsertDecision.manualInterventionRequired:
        return _manualPlan(
          record: record,
          currentState: PdvV1JournalState.remoteStockApplied,
          operationId: opId,
          saleId: saleId,
          reasonCode: hiveResult.reason.isNotEmpty
              ? 'hive_${hiveResult.reason}'
              : 'hive_manual',
          actions: const [
            PdvV1RecoveryPlannedAction.surfaceManualIntervention,
          ],
        );
    }
  }

  PdvV1RecoveryPlan _planHiveSaleCompleted(PdvV1JournalRecord record) {
    return _requireIntegrationPlan(
      record: record,
      reasonCode: 'hive_sale_completed_await_sync',
    );
  }

  PdvV1RecoveryPlan _requireIntegrationPlan({
    required PdvV1JournalRecord record,
    required String reasonCode,
  }) {
    return PdvV1RecoveryPlan(
      decision: PdvV1RecoveryDecision.requireExternalIntegration,
      currentState: record.state,
      targetState: record.state,
      plannedActions: const [
        PdvV1RecoveryPlannedAction.awaitExternalIntegration
      ],
      reasonCode: reasonCode,
      operationId: record.operationId,
      saleId: record.saleId,
      journalRevisionAtPlan: record.journalRevision,
      journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
      requiresExternalIntegration: true,
      idempotencyKey: pdvV1BuildIdempotencyKey(
        operationId: record.operationId,
        currentState: record.state,
        decision: PdvV1RecoveryDecision.requireExternalIntegration,
        targetState: record.state,
      ),
    );
  }

  bool _scopeBlocked(PdvV1PreparedSnapshot prep) {
    try {
      prep.validateForFoundation7AA();
      return false;
    } on PdvV1ScopeNotSupportedError {
      return true;
    } on PdvV1InternalError {
      return true;
    }
  }

  Map<String, dynamic> _journalIdentityWithoutRecord(
    PdvV1RemoteVerificationEvidence? evidence,
  ) {
    if (evidence == null) return const {};
    return {
      'operationId': evidence.requestedOperationId,
      'saleId': evidence.requestedSaleId,
      'lojaId': evidence.requestedLojaId,
      'origem': evidence.requestedOrigin,
      'protocolVersion': evidence.requestedProtocolVersion,
      'snapshotHash': '',
      'txItemsHash': evidence.requestedTxItemsHash,
    };
  }

  PdvV1RecoveryPlan _manualPlan({
    PdvV1JournalRecord? record,
    PdvV1RemoteVerificationEvidence? evidence,
    required PdvV1JournalState currentState,
    required String operationId,
    required String saleId,
    required String reasonCode,
    required List<PdvV1RecoveryPlannedAction> actions,
  }) {
    return PdvV1RecoveryPlan(
      decision: PdvV1RecoveryDecision.manualInterventionRequired,
      currentState: currentState,
      targetState: PdvV1JournalState.manualInterventionRequired,
      plannedActions: actions,
      reasonCode: reasonCode,
      operationId: operationId,
      saleId: saleId,
      journalRevisionAtPlan: record?.journalRevision ?? 0,
      journalIdentity: record != null
          ? pdvV1BuildJournalIdentityFromRecord(record)
          : _journalIdentityWithoutRecord(evidence),
      isManualIntervention: true,
      idempotencyKey: pdvV1BuildIdempotencyKey(
        operationId: operationId.isEmpty ? 'unknown' : operationId,
        currentState: currentState,
        decision: PdvV1RecoveryDecision.manualInterventionRequired,
        targetState: PdvV1JournalState.manualInterventionRequired,
      ),
    );
  }

  PdvV1RecoveryPlan _invalidPlan({
    PdvV1JournalRecord? record,
    PdvV1RemoteVerificationEvidence? evidence,
    required String reasonCode,
    required String operationId,
    required String saleId,
    PdvV1JournalState currentState = PdvV1JournalState.prepared,
  }) {
    return PdvV1RecoveryPlan(
      decision: PdvV1RecoveryDecision.invalidInput,
      currentState: currentState,
      targetState: currentState,
      plannedActions: const [],
      reasonCode: reasonCode,
      operationId: operationId,
      saleId: saleId,
      journalRevisionAtPlan: record?.journalRevision ?? 0,
      journalIdentity: record != null
          ? pdvV1BuildJournalIdentityFromRecord(record)
          : _journalIdentityWithoutRecord(evidence),
      idempotencyKey: pdvV1BuildIdempotencyKey(
        operationId: operationId.isEmpty ? 'unknown' : operationId,
        currentState: currentState,
        decision: PdvV1RecoveryDecision.invalidInput,
        targetState: currentState,
      ),
    );
  }
}
