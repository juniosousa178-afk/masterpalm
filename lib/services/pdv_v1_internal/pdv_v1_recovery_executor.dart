import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_recovery_models.dart';

/// Executor simulado de recovery — somente propostas em memória, sem I/O.
class PdvV1RecoveryExecutorSimulator {
  const PdvV1RecoveryExecutorSimulator();

  PdvV1SimulatedExecutionOutcome simulate(PdvV1RecoveryExecutorInput input) {
    final outcome = input.journalOutcome;
    final plan = input.plan;
    final record = outcome.record;
    final stateBefore = record.state;
    final prep = record.prepared;

    if (outcome.isMalformedReadOnly) {
      return _terminalManual(
        record: record,
        stateBefore: PdvV1JournalState.manualInterventionRequired,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: pdvV1MalformedRecoveryReasonCode,
        actions: const [
          PdvV1RecoveryPlannedAction.preserveMalformedEvidence,
          PdvV1RecoveryPlannedAction.surfaceManualIntervention,
        ],
      );
    }

    if (stateBefore == PdvV1JournalState.operationCompleted ||
        stateBefore == PdvV1JournalState.manualInterventionRequired) {
      if (pdvV1HasUnexpectedRemoteEvidence(
        record: record,
        evidence: input.context.evidence,
        isMalformedReadOnly: outcome.isMalformedReadOnly,
      )) {
        return _terminalManual(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: input.context.evidence,
          hiveMatches: input.context.hiveMatches,
          reasonCode: pdvV1UnexpectedRemoteEvidenceReasonCode,
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        );
      }
      return _noActionTerminal(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: 'terminal_state',
      );
    }

    if (!_planMatchesJournal(plan, record)) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: 'plan_journal_mismatch',
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
      );
    }

    if (pdvV1HasUnexpectedRemoteEvidence(
      record: record,
      evidence: input.context.evidence,
      isMalformedReadOnly: outcome.isMalformedReadOnly,
    )) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: pdvV1UnexpectedRemoteEvidenceReasonCode,
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
      );
    }

    if (plan.journalRevisionAtPlan != record.journalRevision) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: 'stale_plan_revision',
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
      );
    }

    final fingerprint = pdvV1BuildRecoveryPlanFingerprint(
      plan: plan,
      prep: prep,
      evidence: pdvV1EvidenceForRecoveryFingerprint(
        record: record,
        isMalformedReadOnly: outcome.isMalformedReadOnly,
        evidence: input.context.evidence,
      ),
      hiveMatches: input.context.hiveMatches,
    );

    if (plan.decision == PdvV1RecoveryDecision.invalidInput) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode:
            plan.reasonCode.isNotEmpty ? plan.reasonCode : 'invalid_plan',
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        fingerprint: fingerprint,
      );
    }

    if (plan.isManualIntervention ||
        plan.decision == PdvV1RecoveryDecision.manualInterventionRequired) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: plan.reasonCode,
        actions: plan.plannedActions,
        fingerprint: fingerprint,
      );
    }

    if (plan.decision == PdvV1RecoveryDecision.deferUntilVerification) {
      return PdvV1SimulatedExecutionOutcome(
        decision: PdvV1RecoveryDecision.deferUntilVerification,
        stateBefore: stateBefore,
        proposedStateAfter: stateBefore,
        proposedActions: plan.plannedActions,
        planFingerprint: fingerprint,
        proposedJournalRevision: record.journalRevision,
        isDeferred: true,
        reasonCode: plan.reasonCode,
        idempotencyDiagnosticKey: plan.idempotencyKey,
      );
    }

    final stageStartRequest = input.stageStartRequest;
    if (stageStartRequest != null && input.confirmation != null) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: input.context.evidence,
        hiveMatches: input.context.hiveMatches,
        reasonCode: 'stage_start_and_confirmation_conflict',
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        fingerprint: fingerprint,
      );
    }

    if (stageStartRequest != null) {
      return _simulateStageStart(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        fingerprint: fingerprint,
        request: stageStartRequest,
      );
    }

    final confirmation = input.confirmation;
    if (confirmation != null) {
      final validation = _validateConfirmation(
        confirmation: confirmation,
        fingerprint: fingerprint,
        prep: prep,
        record: record,
        stateBefore: stateBefore,
      );
      if (!validation.valid) {
        return _terminalManual(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: input.context.evidence,
          hiveMatches: input.context.hiveMatches,
          reasonCode: validation.reasonCode,
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
          fingerprint: fingerprint,
        );
      }
    }

    switch (plan.decision) {
      case PdvV1RecoveryDecision.noAction:
        return _noActionTerminal(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: input.context.evidence,
          hiveMatches: input.context.hiveMatches,
          reasonCode: plan.reasonCode,
          fingerprint: fingerprint,
        );

      case PdvV1RecoveryDecision.replanRemoteStockTransaction:
        const replanTarget = PdvV1JournalState.prepared;
        return _outcomeWithPlanTargetTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: replanTarget,
          proposedActions: plan.plannedActions,
          requiresFuturePersistence: true,
          requiresExternalIntegration: true,
        );

      case PdvV1RecoveryDecision.continueWithHiveUpsert:
        const continueTarget = PdvV1JournalState.remoteStockApplied;
        return _outcomeWithPlanTargetTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: continueTarget,
          proposedActions: plan.plannedActions,
          requiresFuturePersistence: true,
        );

      case PdvV1RecoveryDecision.insertHiveSaleOnce:
        const insertTarget = PdvV1JournalState.hiveSalePending;
        return _outcomeWithPlanTargetTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: insertTarget,
          proposedActions: plan.plannedActions,
          requiresFuturePersistence: true,
          requiresExternalIntegration: true,
        );

      case PdvV1RecoveryDecision.reuseExistingHiveSale:
        const reuseTarget = PdvV1JournalState.hiveSaleCompleted;
        return _outcomeWithPlanTargetTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: reuseTarget,
          proposedActions: plan.plannedActions,
          requiresExternalIntegration: true,
        );

      case PdvV1RecoveryDecision.requireExternalIntegration:
        return _simulateIntegrationStage(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          fingerprint: fingerprint,
          confirmation: confirmation,
          requiredEffectsKeys: input.context.requiredEffectsKeys,
        );

      case PdvV1RecoveryDecision.deferUntilVerification:
      case PdvV1RecoveryDecision.manualInterventionRequired:
      case PdvV1RecoveryDecision.invalidInput:
        throw StateError('ramo inalcançável');
    }
  }

  int _proposedRevision(
    PdvV1JournalRecord record,
    PdvV1JournalState proposedStateAfter,
  ) {
    if (proposedStateAfter != record.state) {
      return record.journalRevision + 1;
    }
    return record.journalRevision;
  }

  PdvV1SimulatedExecutionOutcome _simulateIntegrationStage({
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
    required PdvV1RecoveryPlan plan,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1SimulatedStageConfirmation? confirmation,
    required List<String> requiredEffectsKeys,
  }) {
    if (confirmation == null) {
      return PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: stateBefore,
        proposedStateAfter: stateBefore,
        proposedActions: plan.plannedActions,
        planFingerprint: fingerprint,
        proposedJournalRevision: record.journalRevision,
        requiresExternalIntegration: true,
        reasonCode: plan.reasonCode,
        idempotencyDiagnosticKey: plan.idempotencyKey,
      );
    }

    switch (confirmation.status) {
      case PdvV1SimulatedConfirmationStatus.deferred:
      case PdvV1SimulatedConfirmationStatus.unavailable:
        return PdvV1SimulatedExecutionOutcome(
          decision: plan.decision,
          stateBefore: stateBefore,
          proposedStateAfter: stateBefore,
          proposedActions: plan.plannedActions,
          planFingerprint: fingerprint,
          proposedJournalRevision: record.journalRevision,
          requiresExternalIntegration: true,
          isDeferred: true,
          reasonCode: confirmation.reasonCode.isNotEmpty
              ? confirmation.reasonCode
              : plan.reasonCode,
          idempotencyDiagnosticKey: plan.idempotencyKey,
        );
      case PdvV1SimulatedConfirmationStatus.divergentOrInvalid:
        return _terminalManual(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: null,
          hiveMatches: const [],
          reasonCode: confirmation.reasonCode.isNotEmpty
              ? confirmation.reasonCode
              : 'confirmation_divergent',
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
          fingerprint: fingerprint,
        );
      case PdvV1SimulatedConfirmationStatus.confirmedCompatible:
        break;
    }

    switch (stateBefore) {
      case PdvV1JournalState.hiveSalePending:
        if (confirmation.stage !=
            PdvV1SimulatedConfirmationStage.hiveSaleUpsert) {
          return _stayPending(
            record: record,
            stateBefore: stateBefore,
            plan: plan,
            fingerprint: fingerprint,
            reasonCode: 'wrong_confirmation_stage',
          );
        }
        const hiveCompleted = PdvV1JournalState.hiveSaleCompleted;
        return _outcomeWithConfirmedTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: hiveCompleted,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .confirmedHiveSaleUpsertTransition,
          confirmation: confirmation,
          reasonCode: 'hive_sale_upsert_confirmed',
        );

      case PdvV1JournalState.saleSyncPending:
        if (confirmation.stage != PdvV1SimulatedConfirmationStage.saleSync) {
          return _stayPending(
            record: record,
            stateBefore: stateBefore,
            plan: plan,
            fingerprint: fingerprint,
            reasonCode: 'wrong_confirmation_stage',
          );
        }
        const syncCompleted = PdvV1JournalState.saleSyncCompleted;
        return _outcomeWithConfirmedTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: syncCompleted,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .confirmedSaleSyncTransition,
          confirmation: confirmation,
          reasonCode: 'sale_sync_confirmed',
        );

      case PdvV1JournalState.effectsPending:
        if (confirmation.stage != PdvV1SimulatedConfirmationStage.effects) {
          return _stayPending(
            record: record,
            stateBefore: stateBefore,
            plan: plan,
            fingerprint: fingerprint,
            reasonCode: 'wrong_confirmation_stage',
          );
        }
        final required = requiredEffectsKeys.isNotEmpty
            ? requiredEffectsKeys
            : confirmation.requiredEffectsKeys;
        if (!_effectsComplete(required, confirmation.completedEffectsKeys)) {
          return PdvV1SimulatedExecutionOutcome(
            decision: plan.decision,
            stateBefore: stateBefore,
            proposedStateAfter: stateBefore,
            proposedActions: plan.plannedActions,
            planFingerprint: fingerprint,
            proposedJournalRevision: record.journalRevision,
            requiresExternalIntegration: true,
            isDeferred: true,
            reasonCode: 'effects_incomplete',
            idempotencyDiagnosticKey: plan.idempotencyKey,
          );
        }
        const effectsCompleted = PdvV1JournalState.effectsCompleted;
        return _outcomeWithConfirmedTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: effectsCompleted,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .confirmedEffectsTransition,
          confirmation: confirmation,
          reasonCode: 'effects_confirmed',
        );

      case PdvV1JournalState.effectsCompleted:
        if (confirmation.stage !=
            PdvV1SimulatedConfirmationStage.operationCompletion) {
          return _stayPending(
            record: record,
            stateBefore: stateBefore,
            plan: plan,
            fingerprint: fingerprint,
            reasonCode: 'wrong_confirmation_stage',
          );
        }
        final required = requiredEffectsKeys.isNotEmpty
            ? requiredEffectsKeys
            : confirmation.requiredEffectsKeys;
        if (!_effectsComplete(required, confirmation.completedEffectsKeys)) {
          return _terminalManual(
            record: record,
            stateBefore: stateBefore,
            plan: plan,
            prep: prep,
            evidence: null,
            hiveMatches: const [],
            reasonCode: 'effects_not_confirmed_for_completion',
            actions: const [
              PdvV1RecoveryPlannedAction.surfaceManualIntervention
            ],
            fingerprint: fingerprint,
          );
        }
        const operationCompleted = PdvV1JournalState.operationCompleted;
        return _outcomeWithConfirmedTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: operationCompleted,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .confirmedOperationCompletionTransition,
          confirmation: confirmation,
          reasonCode: 'operation_completed_confirmed',
        );

      case PdvV1JournalState.saleSyncCompleted:
        return _terminalManual(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: null,
          hiveMatches: const [],
          reasonCode: 'cannot_skip_to_operation_from_sale_sync',
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
          fingerprint: fingerprint,
        );

      default:
        return _stayPending(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          fingerprint: fingerprint,
          reasonCode: plan.reasonCode,
        );
    }
  }

  PdvV1SimulatedExecutionOutcome _stayPending({
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
    required PdvV1RecoveryPlan plan,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required String reasonCode,
  }) {
    return PdvV1SimulatedExecutionOutcome(
      decision: plan.decision,
      stateBefore: stateBefore,
      proposedStateAfter: stateBefore,
      proposedActions: plan.plannedActions,
      planFingerprint: fingerprint,
      proposedJournalRevision: record.journalRevision,
      requiresExternalIntegration: true,
      reasonCode: reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  bool _effectsComplete(List<String> required, List<String> completed) {
    if (required.isEmpty) return true;
    for (final key in required) {
      if (!completed.contains(key)) return false;
    }
    return true;
  }

  bool _planMatchesJournal(PdvV1RecoveryPlan plan, PdvV1JournalRecord record) {
    if (plan.operationId != record.operationId) return false;
    if (plan.saleId != record.saleId) return false;
    if (plan.currentState != record.state) return false;
    return true;
  }

  _ConfirmationValidation _validateConfirmation({
    required PdvV1SimulatedStageConfirmation confirmation,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1PreparedSnapshot prep,
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
  }) {
    if (confirmation.expectedJournalRevision != record.journalRevision) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'stale_confirmation_revision',
      );
    }
    if (!fingerprint.identityMatchesConfirmation(confirmation)) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'confirmation_identity_mismatch',
      );
    }
    if (confirmation.saleId != prep.saleId ||
        confirmation.operationId != prep.operationId ||
        confirmation.lojaId != prep.lojaId ||
        confirmation.origem != prep.origemProtocol ||
        confirmation.protocolVersion != prep.protocolVersion ||
        confirmation.snapshotHash != prep.snapshotHash ||
        confirmation.txItemsHash != prep.txItemsHash) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'confirmation_prep_mismatch',
      );
    }
    if (stateBefore == PdvV1JournalState.saleSyncPending &&
        confirmation.stage == PdvV1SimulatedConfirmationStage.hiveSaleUpsert) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'hive_confirmation_on_sale_sync_pending',
      );
    }
    if (stateBefore == PdvV1JournalState.hiveSalePending &&
        confirmation.stage == PdvV1SimulatedConfirmationStage.saleSync) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'sale_sync_confirmation_on_hive_pending',
      );
    }
    if (confirmation.expectedStateBefore != stateBefore) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'confirmation_state_before_divergent',
      );
    }
    if (confirmation.expectedTargetState !=
        _expectedTargetForStage(confirmation.stage)) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'confirmation_target_state_divergent',
      );
    }
    if (!_stageStateBindingValid(confirmation)) {
      return const _ConfirmationValidation(
        valid: false,
        reasonCode: 'confirmation_stage_state_binding_invalid',
      );
    }
    return const _ConfirmationValidation(valid: true);
  }

  bool _stageStateBindingValid(PdvV1SimulatedStageConfirmation confirmation) {
    switch (confirmation.stage) {
      case PdvV1SimulatedConfirmationStage.hiveSaleUpsert:
        return confirmation.expectedStateBefore ==
                PdvV1JournalState.hiveSalePending &&
            confirmation.expectedTargetState ==
                PdvV1JournalState.hiveSaleCompleted;
      case PdvV1SimulatedConfirmationStage.saleSync:
        return confirmation.expectedStateBefore ==
                PdvV1JournalState.saleSyncPending &&
            confirmation.expectedTargetState ==
                PdvV1JournalState.saleSyncCompleted;
      case PdvV1SimulatedConfirmationStage.effects:
        return confirmation.expectedStateBefore ==
                PdvV1JournalState.effectsPending &&
            confirmation.expectedTargetState ==
                PdvV1JournalState.effectsCompleted;
      case PdvV1SimulatedConfirmationStage.operationCompletion:
        return confirmation.expectedStateBefore ==
                PdvV1JournalState.effectsCompleted &&
            confirmation.expectedTargetState ==
                PdvV1JournalState.operationCompleted;
    }
  }

  PdvV1JournalState _expectedTargetForStage(
    PdvV1SimulatedConfirmationStage stage,
  ) {
    switch (stage) {
      case PdvV1SimulatedConfirmationStage.hiveSaleUpsert:
        return PdvV1JournalState.hiveSaleCompleted;
      case PdvV1SimulatedConfirmationStage.saleSync:
        return PdvV1JournalState.saleSyncCompleted;
      case PdvV1SimulatedConfirmationStage.effects:
        return PdvV1JournalState.effectsCompleted;
      case PdvV1SimulatedConfirmationStage.operationCompletion:
        return PdvV1JournalState.operationCompleted;
    }
  }

  PdvV1SimulatedExecutionOutcome _outcomeWithPlanTargetTransition({
    required PdvV1JournalRecord record,
    required PdvV1RecoveryPlan plan,
    required PdvV1JournalState stateBefore,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1JournalState proposedStateAfter,
    required List<PdvV1RecoveryPlannedAction> proposedActions,
    bool requiresFuturePersistence = false,
    bool requiresExternalIntegration = false,
  }) {
    return PdvV1SimulatedExecutionOutcome(
      decision: plan.decision,
      stateBefore: stateBefore,
      proposedStateAfter: proposedStateAfter,
      proposedActions: proposedActions,
      planFingerprint: fingerprint,
      proposedJournalRevision: _proposedRevision(record, proposedStateAfter),
      transitionAuthorization: _issueTransitionAuthorization(
        record: record,
        prep: prep,
        plan: plan,
        fingerprint: fingerprint,
        stateBefore: stateBefore,
        stateAfter: proposedStateAfter,
        kind: PdvV1SimulatedTransitionAuthorizationKind.planTargetTransition,
      ),
      requiresFuturePersistence: requiresFuturePersistence,
      requiresExternalIntegration: requiresExternalIntegration,
      reasonCode: plan.reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  PdvV1SimulatedExecutionOutcome _simulateStageStart({
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
    required PdvV1RecoveryPlan plan,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1SimulatedStageStartRequest request,
  }) {
    final validation = pdvV1ValidateStageStartRequest(
      request: request,
      record: record,
      prep: prep,
      plan: plan,
      fingerprint: fingerprint,
    );
    if (!validation.valid) {
      return _terminalManual(
        record: record,
        stateBefore: stateBefore,
        plan: plan,
        prep: prep,
        evidence: null,
        hiveMatches: const [],
        reasonCode: validation.reasonCode,
        actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        fingerprint: fingerprint,
      );
    }

    switch (request.stageToStart) {
      case PdvV1SimulatedConfirmationStage.saleSync:
        return _outcomeWithStageStartTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: PdvV1JournalState.saleSyncPending,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .stageStartSaleSyncTransition,
          stageToStart: request.stageToStart,
          reasonCode: 'sale_sync_stage_started',
        );
      case PdvV1SimulatedConfirmationStage.effects:
        return _outcomeWithStageStartTransition(
          record: record,
          plan: plan,
          stateBefore: stateBefore,
          prep: prep,
          fingerprint: fingerprint,
          proposedStateAfter: PdvV1JournalState.effectsPending,
          authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
              .stageStartEffectsTransition,
          stageToStart: request.stageToStart,
          reasonCode: 'effects_stage_started',
        );
      case PdvV1SimulatedConfirmationStage.hiveSaleUpsert:
      case PdvV1SimulatedConfirmationStage.operationCompletion:
        return _terminalManual(
          record: record,
          stateBefore: stateBefore,
          plan: plan,
          prep: prep,
          evidence: null,
          hiveMatches: const [],
          reasonCode: 'stage_start_stage_not_allowed',
          actions: const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
          fingerprint: fingerprint,
        );
    }
  }

  PdvV1SimulatedExecutionOutcome _outcomeWithStageStartTransition({
    required PdvV1JournalRecord record,
    required PdvV1RecoveryPlan plan,
    required PdvV1JournalState stateBefore,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1JournalState proposedStateAfter,
    required PdvV1SimulatedTransitionAuthorizationKind authorizationKind,
    required PdvV1SimulatedConfirmationStage stageToStart,
    required String reasonCode,
  }) {
    return PdvV1SimulatedExecutionOutcome(
      decision: plan.decision,
      stateBefore: stateBefore,
      proposedStateAfter: proposedStateAfter,
      proposedActions: plan.plannedActions,
      planFingerprint: fingerprint,
      proposedJournalRevision: _proposedRevision(record, proposedStateAfter),
      transitionAuthorization: _issueTransitionAuthorization(
        record: record,
        prep: prep,
        plan: plan,
        fingerprint: fingerprint,
        stateBefore: stateBefore,
        stateAfter: proposedStateAfter,
        kind: authorizationKind,
        stageToStart: stageToStart,
      ),
      requiresExternalIntegration: true,
      reasonCode: reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  PdvV1SimulatedExecutionOutcome _outcomeWithConfirmedTransition({
    required PdvV1JournalRecord record,
    required PdvV1RecoveryPlan plan,
    required PdvV1JournalState stateBefore,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1JournalState proposedStateAfter,
    required PdvV1SimulatedTransitionAuthorizationKind authorizationKind,
    required PdvV1SimulatedStageConfirmation confirmation,
    required String reasonCode,
  }) {
    return PdvV1SimulatedExecutionOutcome(
      decision: plan.decision,
      stateBefore: stateBefore,
      proposedStateAfter: proposedStateAfter,
      proposedActions: const [],
      planFingerprint: fingerprint,
      proposedJournalRevision: _proposedRevision(record, proposedStateAfter),
      transitionAuthorization: _issueTransitionAuthorization(
        record: record,
        prep: prep,
        plan: plan,
        fingerprint: fingerprint,
        stateBefore: stateBefore,
        stateAfter: proposedStateAfter,
        kind: authorizationKind,
        confirmationStage: confirmation.stage,
        confirmationStatus: confirmation.status,
      ),
      confirmationValidated: true,
      requiresExternalIntegration: true,
      reasonCode: reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  PdvV1SimulatedTransitionAuthorization _issueTransitionAuthorization({
    required PdvV1JournalRecord record,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RecoveryPlan plan,
    required PdvV1RecoveryPlanFingerprint fingerprint,
    required PdvV1JournalState stateBefore,
    required PdvV1JournalState stateAfter,
    required PdvV1SimulatedTransitionAuthorizationKind kind,
    PdvV1SimulatedConfirmationStage? confirmationStage,
    PdvV1SimulatedConfirmationStatus? confirmationStatus,
    PdvV1SimulatedConfirmationStage? stageToStart,
  }) {
    return PdvV1SimulatedTransitionAuthorization(
      planFingerprint: fingerprint,
      operationId: prep.operationId,
      saleId: prep.saleId,
      lojaId: prep.lojaId,
      origem: prep.origemProtocol,
      protocolVersion: prep.protocolVersion,
      snapshotHash: prep.snapshotHash,
      txItemsHash: prep.txItemsHash,
      journalRevisionAtAuthorization: record.journalRevision,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      planTargetState: plan.targetState,
      authorizationKind: kind,
      confirmationStage: confirmationStage,
      confirmationStatus: confirmationStatus,
      stageToStart: stageToStart,
      semanticPlanValidated: true,
      identityValidated: true,
      issuedByExecutorOnly: true,
    );
  }

  PdvV1SimulatedExecutionOutcome _noActionTerminal({
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
    required PdvV1RecoveryPlan plan,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RemoteVerificationEvidence? evidence,
    required List<PdvV1HiveSaleMatch> hiveMatches,
    required String reasonCode,
    PdvV1RecoveryPlanFingerprint? fingerprint,
  }) {
    final fp = fingerprint ??
        pdvV1BuildRecoveryPlanFingerprint(
          plan: plan,
          prep: prep,
          evidence: pdvV1EvidenceForRecoveryFingerprint(
            record: record,
            evidence: evidence,
          ),
          hiveMatches: hiveMatches,
        );
    return PdvV1SimulatedExecutionOutcome(
      decision: PdvV1RecoveryDecision.noAction,
      stateBefore: stateBefore,
      proposedStateAfter: stateBefore,
      proposedActions: const [],
      planFingerprint: fp,
      proposedJournalRevision: record.journalRevision,
      reasonCode: reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  PdvV1SimulatedExecutionOutcome _terminalManual({
    required PdvV1JournalRecord record,
    required PdvV1JournalState stateBefore,
    required PdvV1RecoveryPlan plan,
    required PdvV1PreparedSnapshot prep,
    required PdvV1RemoteVerificationEvidence? evidence,
    required List<PdvV1HiveSaleMatch> hiveMatches,
    required String reasonCode,
    required List<PdvV1RecoveryPlannedAction> actions,
    PdvV1RecoveryPlanFingerprint? fingerprint,
  }) {
    final fp = fingerprint ??
        pdvV1BuildRecoveryPlanFingerprint(
          plan: plan,
          prep: prep,
          evidence: pdvV1EvidenceForRecoveryFingerprint(
            record: record,
            evidence: evidence,
          ),
          hiveMatches: hiveMatches,
        );
    const proposed = PdvV1JournalState.manualInterventionRequired;
    return PdvV1SimulatedExecutionOutcome(
      decision: PdvV1RecoveryDecision.manualInterventionRequired,
      stateBefore: stateBefore,
      proposedStateAfter: proposed,
      proposedActions: actions,
      planFingerprint: fp,
      proposedJournalRevision: _proposedRevision(record, proposed),
      isManualIntervention: true,
      reasonCode: reasonCode,
      idempotencyDiagnosticKey: plan.idempotencyKey,
    );
  }

  /// Emite patch same-state autorizado — somente falha retryable tipada em stage pendente.
  PdvV1JournalSameStatePatchIssueOutcome proposeRetryableStageFailurePatch(
    PdvV1RecoveryExecutorSameStatePatchInput input,
  ) {
    final outcome = input.journalOutcome;
    final record = outcome.record;
    final plan = input.plan;
    final prep = record.prepared;
    final fingerprint = input.planFingerprint;

    if (outcome.isMalformedReadOnly) {
      return pdvV1RejectSameStatePatchIssue('journal_malformed_patch_denied');
    }

    if (pdvV1JournalStateIsTerminal(record.state)) {
      return pdvV1RejectSameStatePatchIssue('terminal_state_patch_denied');
    }

    if (pdvV1HasUnexpectedRemoteEvidence(
      record: record,
      evidence: input.evidence,
      isMalformedReadOnly: outcome.isMalformedReadOnly,
    )) {
      return pdvV1RejectSameStatePatchIssue(
        pdvV1UnexpectedRemoteEvidenceReasonCode,
      );
    }

    if (plan.decision == PdvV1RecoveryDecision.deferUntilVerification) {
      return pdvV1RejectSameStatePatchIssue('marker_verification_unavailable');
    }

    if (plan.journalRevisionAtPlan != record.journalRevision) {
      return pdvV1RejectSameStatePatchIssue('stale_plan_revision');
    }

    if (plan.decision == PdvV1RecoveryDecision.invalidInput ||
        plan.isManualIntervention) {
      return pdvV1RejectSameStatePatchIssue(
        plan.reasonCode.isNotEmpty ? plan.reasonCode : 'invalid_plan',
      );
    }

    if (!_planMatchesJournal(plan, record)) {
      return pdvV1RejectSameStatePatchIssue('plan_journal_mismatch');
    }

    if (fingerprint.journalRevisionAtPlan != record.journalRevision ||
        fingerprint.currentState != record.state) {
      return pdvV1RejectSameStatePatchIssue('stale_plan_revision');
    }

    if (!fingerprint.identityMatchesConfirmation(
      PdvV1SimulatedStageConfirmation(
        planFingerprint: fingerprint,
        expectedJournalRevision: record.journalRevision,
        operationId: prep.operationId,
        saleId: prep.saleId,
        lojaId: prep.lojaId,
        origem: prep.origemProtocol,
        protocolVersion: prep.protocolVersion,
        snapshotHash: prep.snapshotHash,
        txItemsHash: prep.txItemsHash,
        expectedStateBefore: record.state,
        expectedTargetState: record.state,
        stage: input.stage,
        status: PdvV1SimulatedConfirmationStatus.unavailable,
      ),
    )) {
      return pdvV1RejectSameStatePatchIssue('identity_mismatch');
    }

    final confirmation = input.confirmation;
    if (confirmation != null) {
      if (confirmation.expectedJournalRevision != record.journalRevision) {
        return pdvV1RejectSameStatePatchIssue('stale_confirmation_revision');
      }
      if (confirmation.status ==
          PdvV1SimulatedConfirmationStatus.divergentOrInvalid) {
        return pdvV1RejectSameStatePatchIssue('confirmation_divergent');
      }
      if (confirmation.stage != input.stage) {
        return pdvV1RejectSameStatePatchIssue('confirmation_stage_mismatch');
      }
    }

    final stageStartRequest = input.stageStartRequest;
    if (stageStartRequest != null) {
      if (stageStartRequest.expectedJournalRevision != record.journalRevision) {
        return pdvV1RejectSameStatePatchIssue('stale_stage_start_revision');
      }
    }

    final allowedState = pdvV1JournalStateForRetryablePatchStageName(
      input.stage.name,
    );
    final allowedCode = pdvV1RetryableFailureCodeForPatchStageName(
      input.stage.name,
    );
    if (allowedState == null || allowedCode == null) {
      return pdvV1RejectSameStatePatchIssue('patch_stage_mismatch');
    }
    if (record.state != allowedState) {
      return pdvV1RejectSameStatePatchIssue('patch_state_mismatch');
    }

    if (record.attempts < 0) {
      return pdvV1RejectSameStatePatchIssue('patch_attempts_mismatch');
    }
    if (record.attempts >= pdvV1MaxRetryableStageFailureAttempts) {
      return pdvV1RejectSameStatePatchIssue('retry_attempt_limit_reached');
    }

    final nextAttempts = record.attempts + 1;
    final patch = PdvV1JournalSameStatePatch(
      patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
      expectedState: record.state,
      expectedAttempts: nextAttempts,
      stageName: input.stage.name,
      failureCode: allowedCode,
    );

    final authorization = PdvV1JournalSameStatePatchAuthorization(
      patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
      planFingerprint: fingerprint,
      operationId: prep.operationId,
      saleId: prep.saleId,
      lojaId: prep.lojaId,
      origem: prep.origemProtocol,
      protocolVersion: prep.protocolVersion,
      snapshotHash: prep.snapshotHash,
      txItemsHash: prep.txItemsHash,
      expectedJournalRevision: record.journalRevision,
      expectedState: record.state,
      expectedAttempts: nextAttempts,
      stage: input.stage,
      failureCode: allowedCode,
      semanticPlanValidated: true,
      identityValidated: true,
      issuedByExecutorOnly: true,
    );

    return PdvV1JournalSameStatePatchIssueOutcome(
      authorized: true,
      rejectionReasonCode: '',
      patch: patch,
      authorization: authorization,
    );
  }
}

class _ConfirmationValidation {
  const _ConfirmationValidation({required this.valid, this.reasonCode = ''});
  final bool valid;
  final String reasonCode;
}
