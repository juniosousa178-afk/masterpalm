import 'pdv_v1_journal_record.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_recovery_models.dart';
import 'pdv_v1_recovery_plan_semantics.dart';

/// Store CAS simulada — somente memória, sem Box, Hive ou Firebase.
class PdvV1RecoverySimulatedCasStore {
  PdvV1RecoverySimulatedCasStore(PdvV1JournalRecord initial)
      : _record = _copyRecord(initial),
        _semanticsValidator = const PdvV1RecoveryPlanSemanticsValidator();

  PdvV1JournalRecord _record;
  final PdvV1RecoveryPlanSemanticsValidator _semanticsValidator;

  PdvV1JournalRecord get snapshot => _copyRecord(_record);

  PdvV1SimulatedCasApplyOutcome applySimulatedOutcome({
    required int expectedJournalRevision,
    required PdvV1RecoveryPlan plan,
    required PdvV1RecoveryPlanFingerprint planFingerprint,
    required PdvV1SimulatedExecutionOutcome proposedExecutionOutcome,
    required bool semanticPlanValidated,
    PdvV1SimulatedStageConfirmation? confirmation,
    PdvV1SimulatedStageStartRequest? stageStartRequest,
    List<String> requiredEffectsKeys = const [],
  }) {
    final revisionBefore = _record.journalRevision;
    final stateBefore = _record.state;
    final currentSnapshot = snapshot;
    final prep = _record.prepared;

    if (_record.isMalformedReadOnly) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'journal_malformed',
      );
    }

    if (pdvV1JournalStateIsTerminal(stateBefore)) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'terminal_state',
      );
    }

    if (expectedJournalRevision != revisionBefore) {
      return PdvV1SimulatedCasApplyOutcome(
        accepted: false,
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        revisionBefore: revisionBefore,
        revisionAfter: revisionBefore,
        rejectionReasonCode: 'stale_plan_revision',
        proposedExecutionOutcome: proposedExecutionOutcome,
        currentJournalSnapshot: currentSnapshot,
        stalePlanRejected: true,
        persistedOnlyInMemory: false,
      );
    }

    if (planFingerprint.toCanonicalDiagnosticKey().isEmpty) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'missing_fingerprint',
      );
    }

    if (proposedExecutionOutcome.planFingerprint.toCanonicalDiagnosticKey() !=
        planFingerprint.toCanonicalDiagnosticKey()) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'fingerprint_mismatch',
      );
    }

    if (!_planIdentityCompatible(plan, prep)) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'plan_identity_incompatible',
      );
    }

    final semantics = _semanticsValidator.validate(plan);
    if (!semantics.valid ||
        !semanticPlanValidated ||
        !proposedExecutionOutcome.semanticPlanValidated) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: semantics.valid
            ? 'semantic_plan_not_validated'
            : semantics.reasonCode,
      );
    }

    if (proposedExecutionOutcome.stateBefore != stateBefore) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'execution_state_before_mismatch',
      );
    }

    final expectedProposedRevision =
        proposedExecutionOutcome.proposedStateAfter != stateBefore
            ? revisionBefore + 1
            : revisionBefore;
    if (proposedExecutionOutcome.proposedJournalRevision !=
        expectedProposedRevision) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'proposed_revision_incorrect',
      );
    }

    final proposedAfter = proposedExecutionOutcome.proposedStateAfter;
    if (plan.targetState != proposedAfter) {
      final auth = proposedExecutionOutcome.transitionAuthorization;
      if (auth == null) {
        return _reject(
          revisionBefore: revisionBefore,
          stateBefore: stateBefore,
          currentSnapshot: currentSnapshot,
          proposed: proposedExecutionOutcome,
          reasonCode: 'unauthorized_transition_override',
        );
      }
      final authValidation = pdvV1ValidateTransitionAuthorization(
        authorization: auth,
        record: _record,
        prep: prep,
        plan: plan,
        fingerprint: planFingerprint,
        proposedStateAfter: proposedAfter,
        confirmation: confirmation,
        stageStartRequest: stageStartRequest,
        requiredEffectsKeys: requiredEffectsKeys,
      );
      if (!authValidation.valid) {
        return _reject(
          revisionBefore: revisionBefore,
          stateBefore: stateBefore,
          currentSnapshot: currentSnapshot,
          proposed: proposedExecutionOutcome,
          reasonCode: authValidation.reasonCode,
        );
      }
    } else if (proposedAfter != stateBefore &&
        proposedExecutionOutcome.transitionAuthorization != null) {
      final auth = proposedExecutionOutcome.transitionAuthorization!;
      if (auth.authorizationKind !=
          PdvV1SimulatedTransitionAuthorizationKind.planTargetTransition) {
        return _reject(
          revisionBefore: revisionBefore,
          stateBefore: stateBefore,
          currentSnapshot: currentSnapshot,
          proposed: proposedExecutionOutcome,
          reasonCode: 'unexpected_authorization_kind',
        );
      }
      final authValidation = pdvV1ValidateTransitionAuthorization(
        authorization: auth,
        record: _record,
        prep: prep,
        plan: plan,
        fingerprint: planFingerprint,
        proposedStateAfter: proposedAfter,
        confirmation: confirmation,
        stageStartRequest: stageStartRequest,
        requiredEffectsKeys: requiredEffectsKeys,
      );
      if (!authValidation.valid) {
        return _reject(
          revisionBefore: revisionBefore,
          stateBefore: stateBefore,
          currentSnapshot: currentSnapshot,
          proposed: proposedExecutionOutcome,
          reasonCode: authValidation.reasonCode,
        );
      }
    }

    if (proposedExecutionOutcome.isManualIntervention) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: proposedExecutionOutcome.reasonCode.isNotEmpty
            ? proposedExecutionOutcome.reasonCode
            : 'manual_intervention_not_applied',
      );
    }

    if (proposedAfter == PdvV1JournalState.manualInterventionRequired ||
        proposedAfter == PdvV1JournalState.operationCompleted &&
            stateBefore != PdvV1JournalState.effectsCompleted) {
      return _reject(
        revisionBefore: revisionBefore,
        stateBefore: stateBefore,
        currentSnapshot: currentSnapshot,
        proposed: proposedExecutionOutcome,
        reasonCode: 'unauthorized_terminal_transition',
      );
    }

    _record = _record.copyWith(
      state: proposedAfter,
      journalRevision: expectedProposedRevision,
      updatedAtEpochMs: _record.updatedAtEpochMs + 1,
    );

    return PdvV1SimulatedCasApplyOutcome(
      accepted: true,
      stateBefore: stateBefore,
      stateAfter: proposedAfter,
      revisionBefore: revisionBefore,
      revisionAfter: expectedProposedRevision,
      rejectionReasonCode: '',
      proposedExecutionOutcome: proposedExecutionOutcome,
      currentJournalSnapshot: snapshot,
      stalePlanRejected: false,
      persistedOnlyInMemory: true,
    );
  }

  PdvV1SimulatedCasApplyOutcome _reject({
    required int revisionBefore,
    required PdvV1JournalState stateBefore,
    required PdvV1JournalRecord currentSnapshot,
    required PdvV1SimulatedExecutionOutcome proposed,
    required String reasonCode,
  }) {
    return PdvV1SimulatedCasApplyOutcome(
      accepted: false,
      stateBefore: stateBefore,
      stateAfter: stateBefore,
      revisionBefore: revisionBefore,
      revisionAfter: revisionBefore,
      rejectionReasonCode: reasonCode,
      proposedExecutionOutcome: proposed,
      currentJournalSnapshot: currentSnapshot,
      stalePlanRejected: reasonCode == 'stale_plan_revision',
      persistedOnlyInMemory: false,
    );
  }

  bool _planIdentityCompatible(
    PdvV1RecoveryPlan plan,
    PdvV1PreparedSnapshot prep,
  ) {
    if (pdvV1RecoveryPlanIsMalformedBoundary(plan)) return true;
    if (plan.operationId != prep.operationId) return false;
    if (plan.saleId != prep.saleId) return false;
    if (plan.currentState != _record.state) return false;
    if (plan.journalRevisionAtPlan != _record.journalRevision) return false;
    return true;
  }

  static PdvV1JournalRecord _copyRecord(PdvV1JournalRecord source) {
    return source.copyWith(
      subestados: Map<String, dynamic>.from(source.subestados),
    );
  }
}

/// Resultado explícito de tentativa CAS simulada.
class PdvV1SimulatedCasApplyOutcome {
  const PdvV1SimulatedCasApplyOutcome({
    required this.accepted,
    required this.stateBefore,
    required this.stateAfter,
    required this.revisionBefore,
    required this.revisionAfter,
    required this.rejectionReasonCode,
    required this.proposedExecutionOutcome,
    required this.currentJournalSnapshot,
    required this.stalePlanRejected,
    required this.persistedOnlyInMemory,
  });

  final bool accepted;
  final PdvV1JournalState stateBefore;
  final PdvV1JournalState stateAfter;
  final int revisionBefore;
  final int revisionAfter;
  final String rejectionReasonCode;
  final PdvV1SimulatedExecutionOutcome proposedExecutionOutcome;
  final PdvV1JournalRecord currentJournalSnapshot;
  final bool stalePlanRejected;
  final bool persistedOnlyInMemory;

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'stateBefore': stateBefore.name,
        'stateAfter': stateAfter.name,
        'revisionBefore': revisionBefore,
        'revisionAfter': revisionAfter,
        'rejectionReasonCode': rejectionReasonCode,
        'proposedExecutionOutcome': proposedExecutionOutcome.toJson(),
        'currentJournalSnapshot': currentJournalSnapshot.toJson(),
        'stalePlanRejected': stalePlanRejected,
        'persistedOnlyInMemory': persistedOnlyInMemory,
      };
}
