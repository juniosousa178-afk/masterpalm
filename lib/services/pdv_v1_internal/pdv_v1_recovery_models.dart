import 'pdv_v1_hive_upsert_policy.dart';
import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';

const pdvV1RemoteEvidenceVersion = 1;

/// Status tipado de uma futura verificação remota (sem I/O).
enum PdvV1RemoteVerificationStatus {
  markerAbsentVerified,
  markerAppliedCompatible,
  markerDivergentOrInvalid,
  markerVerificationUnavailable,
}

/// Evidência pura de verificação remota — não consulta Firebase.
class PdvV1RemoteVerificationEvidence {
  PdvV1RemoteVerificationEvidence({
    required this.requestedOperationId,
    required this.requestedSaleId,
    required this.requestedLojaId,
    required this.requestedOrigin,
    required this.requestedProtocolVersion,
    required this.requestedTxItemsHash,
    required this.verificationStatus,
    this.optionalMarker = const PdvV1RemoteMarkerInput.ausente(),
    required this.verificationSource,
    required this.verifiedAtEpochMs,
    this.evidenceVersion = pdvV1RemoteEvidenceVersion,
    this.divergentReason = '',
  });

  final String requestedOperationId;
  final String requestedSaleId;
  final String requestedLojaId;
  final String requestedOrigin;
  final int requestedProtocolVersion;
  final String requestedTxItemsHash;
  final PdvV1RemoteVerificationStatus verificationStatus;
  final PdvV1RemoteMarkerInput optionalMarker;
  final String verificationSource;
  final int verifiedAtEpochMs;
  final int evidenceVersion;
  final String divergentReason;

  Map<String, dynamic> toJson() => {
        'requestedOperationId': requestedOperationId,
        'requestedSaleId': requestedSaleId,
        'requestedLojaId': requestedLojaId,
        'requestedOrigin': requestedOrigin,
        'requestedProtocolVersion': requestedProtocolVersion,
        'requestedTxItemsHash': requestedTxItemsHash,
        'verificationStatus': verificationStatus.name,
        'optionalMarker': optionalMarker.toJson(),
        'verificationSource': verificationSource,
        'verifiedAtEpochMs': verifiedAtEpochMs,
        'evidenceVersion': evidenceVersion,
        'divergentReason': divergentReason,
      };

  /// Valida evidência contra journal pendente — fail-closed.
  PdvV1EvidenceValidationResult validateAgainstJournal(
      PdvV1JournalRecord record) {
    if (record.isMalformedReadOnly) {
      return const PdvV1EvidenceValidationResult(
        valid: false,
        reasonCode: 'journal_malformed',
        reasonMessage: 'Journal malformado.',
      );
    }

    final prep = record.prepared;
    final identityMismatch = !_identityMatchesJournal(prep);
    if (identityMismatch) {
      return const PdvV1EvidenceValidationResult(
        valid: false,
        reasonCode: 'identity_mismatch',
        reasonMessage: 'Identidade da evidência diverge do journal.',
      );
    }

    switch (verificationStatus) {
      case PdvV1RemoteVerificationStatus.markerAbsentVerified:
        if (!_requestedIdentityComplete()) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'incomplete_identity',
            reasonMessage: 'Identidade incompleta para ausência verificada.',
          );
        }
        if (optionalMarker.presente) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'marker_must_be_absent',
            reasonMessage: 'Ausência verificada não pode incluir marcador.',
          );
        }
        return const PdvV1EvidenceValidationResult(valid: true);

      case PdvV1RemoteVerificationStatus.markerAppliedCompatible:
        if (!optionalMarker.presente) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'marker_required',
            reasonMessage: 'Marcador obrigatório para compatível.',
          );
        }
        if (!optionalMarker.baixaAplicada) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'baixa_not_applied',
            reasonMessage: 'Marcador sem baixaAplicada.',
          );
        }
        if (!_markerMatchesJournal(optionalMarker, prep)) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'marker_incompatible',
            reasonMessage: 'Marcador incompatível com journal.',
          );
        }
        return const PdvV1EvidenceValidationResult(valid: true);

      case PdvV1RemoteVerificationStatus.markerDivergentOrInvalid:
        final reason = divergentReason.trim();
        if (reason.isEmpty) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'divergent_reason_required',
            reasonMessage: 'Motivo divergente obrigatório.',
          );
        }
        return PdvV1EvidenceValidationResult(
          valid: true,
          reasonCode: 'marker_divergent',
          reasonMessage: reason,
        );

      case PdvV1RemoteVerificationStatus.markerVerificationUnavailable:
        if (optionalMarker.presente && optionalMarker.baixaAplicada) {
          return const PdvV1EvidenceValidationResult(
            valid: false,
            reasonCode: 'unavailable_with_trusted_marker',
            reasonMessage: 'Indisponível não pode conter marcador confiável.',
          );
        }
        return const PdvV1EvidenceValidationResult(valid: true);
    }
  }

  bool _requestedIdentityComplete() {
    return requestedOperationId.trim().isNotEmpty &&
        requestedSaleId.trim().isNotEmpty &&
        requestedLojaId.trim().isNotEmpty &&
        requestedOrigin.trim().isNotEmpty &&
        requestedProtocolVersion == pdvV1ProtocolVersion &&
        requestedTxItemsHash.trim().isNotEmpty;
  }

  bool _identityMatchesJournal(PdvV1PreparedSnapshot prep) {
    return requestedOperationId == prep.operationId &&
        requestedSaleId == prep.saleId &&
        requestedLojaId == prep.lojaId &&
        requestedOrigin == prep.origemProtocol &&
        requestedProtocolVersion == prep.protocolVersion &&
        requestedTxItemsHash == prep.txItemsHash;
  }

  bool _markerMatchesJournal(
    PdvV1RemoteMarkerInput marker,
    PdvV1PreparedSnapshot prep,
  ) {
    return marker.validoV1 &&
        marker.operationId == prep.operationId &&
        marker.saleId == prep.saleId &&
        marker.lojaId == prep.lojaId &&
        marker.txItemsHash == prep.txItemsHash &&
        marker.baixaAplicada;
  }
}

class PdvV1EvidenceValidationResult {
  const PdvV1EvidenceValidationResult({
    required this.valid,
    this.reasonCode = '',
    this.reasonMessage = '',
  });

  final bool valid;
  final String reasonCode;
  final String reasonMessage;
}

/// Contexto sintético de recovery — somente flags em memória.
class PdvV1RecoveryContext {
  const PdvV1RecoveryContext({
    this.markerPresentWithoutJournal = false,
    this.recoveryAttemptLabel = '',
  });

  final bool markerPresentWithoutJournal;
  final String recoveryAttemptLabel;

  Map<String, dynamic> toJson() => {
        'markerPresentWithoutJournal': markerPresentWithoutJournal,
        'recoveryAttemptLabel': recoveryAttemptLabel,
      };
}

/// Decisão pura do plano de recovery.
enum PdvV1RecoveryDecision {
  noAction,
  deferUntilVerification,
  replanRemoteStockTransaction,
  continueWithHiveUpsert,
  reuseExistingHiveSale,
  insertHiveSaleOnce,
  requireExternalIntegration,
  manualInterventionRequired,
  invalidInput,
}

/// Ações planejadas — descrições técnicas, não executáveis.
enum PdvV1RecoveryPlannedAction {
  verifyMarkerAgain,
  persistPlannedTransitionFuture,
  planRemoteStockTransactionFuture,
  planHiveInsertOnceFuture,
  planReuseHiveSaleFuture,
  awaitExternalIntegration,
  preserveMalformedEvidence,
  surfaceManualIntervention,
}

/// Plano serializável de recovery — sem I/O.
class PdvV1RecoveryPlan {
  PdvV1RecoveryPlan({
    required this.decision,
    required this.currentState,
    required this.targetState,
    required List<PdvV1RecoveryPlannedAction> plannedActions,
    required this.reasonCode,
    required this.operationId,
    required this.saleId,
    required this.journalRevisionAtPlan,
    required Map<String, dynamic> journalIdentity,
    this.isDeferred = false,
    this.isManualIntervention = false,
    this.requiresExternalIntegration = false,
    this.evidenceValidated = false,
    required this.idempotencyKey,
  })  : plannedActions = pdvV1FreezePlannedActionsSemantic(plannedActions),
        journalIdentity = Map<String, dynamic>.unmodifiable(
          Map<String, dynamic>.from(journalIdentity),
        );

  final PdvV1RecoveryDecision decision;
  final PdvV1JournalState currentState;
  final PdvV1JournalState targetState;
  final List<PdvV1RecoveryPlannedAction> plannedActions;
  final String reasonCode;
  final String operationId;
  final String saleId;
  final int journalRevisionAtPlan;
  final Map<String, dynamic> journalIdentity;
  final bool isDeferred;
  final bool isManualIntervention;
  final bool requiresExternalIntegration;
  final bool evidenceValidated;
  final String idempotencyKey;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        'currentState': currentState.name,
        'targetState': targetState.name,
        'plannedActions': plannedActions.map((a) => a.name).toList(),
        'reasonCode': reasonCode,
        'operationId': operationId,
        'saleId': saleId,
        'journalRevisionAtPlan': journalRevisionAtPlan,
        'journalIdentity': Map<String, dynamic>.from(journalIdentity),
        'isDeferred': isDeferred,
        'isManualIntervention': isManualIntervention,
        'requiresExternalIntegration': requiresExternalIntegration,
        'evidenceValidated': evidenceValidated,
        'idempotencyKey': idempotencyKey,
      };

  @override
  bool operator ==(Object other) {
    if (other is! PdvV1RecoveryPlan) return false;
    return idempotencyKey == other.idempotencyKey &&
        decision == other.decision &&
        currentState == other.currentState &&
        targetState == other.targetState &&
        _listEquals(plannedActions, other.plannedActions) &&
        reasonCode == other.reasonCode &&
        operationId == other.operationId &&
        saleId == other.saleId &&
        journalRevisionAtPlan == other.journalRevisionAtPlan &&
        _mapEquals(journalIdentity, other.journalIdentity) &&
        isDeferred == other.isDeferred &&
        isManualIntervention == other.isManualIntervention &&
        requiresExternalIntegration == other.requiresExternalIntegration &&
        evidenceValidated == other.evidenceValidated;
  }

  @override
  int get hashCode => Object.hash(
        idempotencyKey,
        decision,
        currentState,
        targetState,
        reasonCode,
        operationId,
        saleId,
        journalRevisionAtPlan,
        isDeferred,
        isManualIntervention,
        requiresExternalIntegration,
        evidenceValidated,
      );
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

List<PdvV1RecoveryPlannedAction> pdvV1FreezePlannedActionsSemantic(
  List<PdvV1RecoveryPlannedAction> actions,
) {
  final copy = List<PdvV1RecoveryPlannedAction>.from(actions);
  final seen = <PdvV1RecoveryPlannedAction>{};
  for (final action in copy) {
    if (seen.contains(action)) {
      throw PdvV1ValidationError(
        'plannedActions contém duplicata semântica: ${action.name}',
      );
    }
    seen.add(action);
  }
  return List<PdvV1RecoveryPlannedAction>.unmodifiable(copy);
}

Map<String, dynamic> pdvV1BuildJournalIdentity(PdvV1PreparedSnapshot prep) {
  return {
    'operationId': prep.operationId,
    'saleId': prep.saleId,
    'lojaId': prep.lojaId,
    'origem': prep.origemProtocol,
    'protocolVersion': prep.protocolVersion,
    'snapshotHash': prep.snapshotHash,
    'txItemsHash': prep.txItemsHash,
  };
}

Map<String, dynamic> pdvV1BuildJournalIdentityFromRecord(
    PdvV1JournalRecord record) {
  if (record.isMalformedReadOnly) {
    return pdvV1MalformedSafeJournalIdentity();
  }
  return pdvV1BuildJournalIdentity(record.prepared);
}

const pdvV1MalformedRecoveryReasonCode = 'journal_malformed';

/// Identidade explícita de que nenhum candidato malformado foi aceito para recovery.
Map<String, dynamic> pdvV1MalformedSafeJournalIdentity() {
  return const {
    'identityAcceptedForRecovery': false,
    'malformedBoundary': true,
  };
}

bool pdvV1RecoveryPlanIsMalformedBoundary(PdvV1RecoveryPlan plan) {
  return plan.journalIdentity['malformedBoundary'] == true;
}

/// Exigência de evidência remota derivada apenas do estado e validade do journal.
enum PdvV1RemoteVerificationRequirement {
  requiredForRecovery,
  notRequiredForCurrentState,
  prohibitedForMalformedOrTerminal,
}

const pdvV1PostBaixaVerificationStatus = 'not_required_for_state';
const pdvV1SimulatedTransitionAuthorizationVersion = 1;
const pdvV1SimulatedStageStartRequestVersion = 1;
const pdvV1UnexpectedRemoteEvidenceReasonCode =
    'unexpected_remote_evidence_for_state';

bool pdvV1HasUnexpectedRemoteEvidence({
  required PdvV1JournalRecord record,
  PdvV1RemoteVerificationEvidence? evidence,
  bool isMalformedReadOnly = false,
}) {
  if (evidence == null) {
    return false;
  }
  final requirement = pdvV1DeriveRemoteVerificationRequirement(
    record: record,
    isMalformedReadOnly: isMalformedReadOnly,
  );
  return requirement ==
          PdvV1RemoteVerificationRequirement.notRequiredForCurrentState ||
      requirement ==
          PdvV1RemoteVerificationRequirement.prohibitedForMalformedOrTerminal;
}

PdvV1RemoteVerificationRequirement pdvV1DeriveRemoteVerificationRequirement({
  required PdvV1JournalRecord record,
  bool isMalformedReadOnly = false,
}) {
  if (isMalformedReadOnly || record.isMalformedReadOnly) {
    return PdvV1RemoteVerificationRequirement.prohibitedForMalformedOrTerminal;
  }
  switch (record.state) {
    case PdvV1JournalState.prepared:
    case PdvV1JournalState.remoteStockPending:
      return PdvV1RemoteVerificationRequirement.requiredForRecovery;
    case PdvV1JournalState.remoteStockApplied:
    case PdvV1JournalState.hiveSalePending:
    case PdvV1JournalState.hiveSaleCompleted:
    case PdvV1JournalState.saleSyncPending:
    case PdvV1JournalState.saleSyncCompleted:
    case PdvV1JournalState.effectsPending:
    case PdvV1JournalState.effectsCompleted:
      return PdvV1RemoteVerificationRequirement.notRequiredForCurrentState;
    case PdvV1JournalState.operationCompleted:
    case PdvV1JournalState.manualInterventionRequired:
      return PdvV1RemoteVerificationRequirement
          .prohibitedForMalformedOrTerminal;
  }
}

bool pdvV1RemoteRequirementAcceptsEvidence(
  PdvV1RemoteVerificationRequirement requirement,
) {
  return requirement == PdvV1RemoteVerificationRequirement.requiredForRecovery;
}

PdvV1RemoteVerificationEvidence? pdvV1EvidenceForRecoveryFingerprint({
  required PdvV1JournalRecord record,
  bool isMalformedReadOnly = false,
  PdvV1RemoteVerificationEvidence? evidence,
}) {
  final requirement = pdvV1DeriveRemoteVerificationRequirement(
    record: record,
    isMalformedReadOnly: isMalformedReadOnly,
  );
  if (!pdvV1RemoteRequirementAcceptsEvidence(requirement)) {
    return null;
  }
  return evidence;
}

String pdvV1VerificationStatusForFingerprint({
  required PdvV1JournalState currentState,
  bool isMalformedReadOnly = false,
  PdvV1RemoteVerificationEvidence? evidence,
}) {
  if (isMalformedReadOnly) {
    return 'prohibited_for_state';
  }
  switch (currentState) {
    case PdvV1JournalState.prepared:
    case PdvV1JournalState.remoteStockPending:
      return evidence?.verificationStatus.name ?? 'none';
    case PdvV1JournalState.remoteStockApplied:
    case PdvV1JournalState.hiveSalePending:
    case PdvV1JournalState.hiveSaleCompleted:
    case PdvV1JournalState.saleSyncPending:
    case PdvV1JournalState.saleSyncCompleted:
    case PdvV1JournalState.effectsPending:
    case PdvV1JournalState.effectsCompleted:
      return pdvV1PostBaixaVerificationStatus;
    case PdvV1JournalState.operationCompleted:
    case PdvV1JournalState.manualInterventionRequired:
      return 'prohibited_for_state';
  }
}

/// Tipo de autorização emitida somente pelo executor simulado.
enum PdvV1SimulatedTransitionAuthorizationKind {
  planTargetTransition,
  confirmedHiveSaleUpsertTransition,
  confirmedSaleSyncTransition,
  confirmedEffectsTransition,
  confirmedOperationCompletionTransition,
  stageStartSaleSyncTransition,
  stageStartEffectsTransition,
}

/// Autorização tipada de transição — somente simulação em memória.
class PdvV1SimulatedTransitionAuthorization {
  const PdvV1SimulatedTransitionAuthorization({
    this.authorizationVersion = pdvV1SimulatedTransitionAuthorizationVersion,
    required this.planFingerprint,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.journalRevisionAtAuthorization,
    required this.stateBefore,
    required this.stateAfter,
    required this.planTargetState,
    required this.authorizationKind,
    this.confirmationStage,
    this.confirmationStatus,
    this.stageToStart,
    required this.semanticPlanValidated,
    required this.identityValidated,
    required this.issuedByExecutorOnly,
  });

  final int authorizationVersion;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final int journalRevisionAtAuthorization;
  final PdvV1JournalState stateBefore;
  final PdvV1JournalState stateAfter;
  final PdvV1JournalState planTargetState;
  final PdvV1SimulatedTransitionAuthorizationKind authorizationKind;
  final PdvV1SimulatedConfirmationStage? confirmationStage;
  final PdvV1SimulatedConfirmationStatus? confirmationStatus;
  final PdvV1SimulatedConfirmationStage? stageToStart;
  final bool semanticPlanValidated;
  final bool identityValidated;
  final bool issuedByExecutorOnly;

  Map<String, dynamic> toJson() => {
        'authorizationVersion': authorizationVersion,
        'planFingerprint': planFingerprint.toJson(),
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origem,
        'protocolVersion': protocolVersion,
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'journalRevisionAtAuthorization': journalRevisionAtAuthorization,
        'stateBefore': stateBefore.name,
        'stateAfter': stateAfter.name,
        'planTargetState': planTargetState.name,
        'authorizationKind': authorizationKind.name,
        if (confirmationStage != null)
          'confirmationStage': confirmationStage!.name,
        if (confirmationStatus != null)
          'confirmationStatus': confirmationStatus!.name,
        if (stageToStart != null) 'stageToStart': stageToStart!.name,
        'semanticPlanValidated': semanticPlanValidated,
        'identityValidated': identityValidated,
        'issuedByExecutorOnly': issuedByExecutorOnly,
      };
}

class PdvV1TransitionAuthorizationValidation {
  const PdvV1TransitionAuthorizationValidation({
    required this.valid,
    this.reasonCode = '',
  });

  final bool valid;
  final String reasonCode;
}

PdvV1TransitionAuthorizationValidation pdvV1ValidateTransitionAuthorization({
  required PdvV1SimulatedTransitionAuthorization authorization,
  required PdvV1JournalRecord record,
  required PdvV1PreparedSnapshot prep,
  required PdvV1RecoveryPlan plan,
  required PdvV1RecoveryPlanFingerprint fingerprint,
  required PdvV1JournalState proposedStateAfter,
  PdvV1SimulatedStageConfirmation? confirmation,
  PdvV1SimulatedStageStartRequest? stageStartRequest,
  List<String> requiredEffectsKeys = const [],
}) {
  if (!authorization.issuedByExecutorOnly) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_not_executor_issued',
    );
  }
  if (!authorization.identityValidated ||
      !authorization.semanticPlanValidated) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_flags_invalid',
    );
  }
  if (authorization.journalRevisionAtAuthorization != record.journalRevision) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'stale_authorization_revision',
    );
  }
  if (authorization.planFingerprint.toCanonicalDiagnosticKey() !=
      fingerprint.toCanonicalDiagnosticKey()) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_fingerprint_mismatch',
    );
  }
  if (authorization.operationId != prep.operationId ||
      authorization.saleId != prep.saleId ||
      authorization.lojaId != prep.lojaId ||
      authorization.origem != prep.origemProtocol ||
      authorization.protocolVersion != prep.protocolVersion ||
      authorization.snapshotHash != prep.snapshotHash ||
      authorization.txItemsHash != prep.txItemsHash) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_identity_mismatch',
    );
  }
  if (authorization.stateBefore != record.state) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_state_before_mismatch',
    );
  }
  if (authorization.stateAfter != proposedStateAfter) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_state_after_mismatch',
    );
  }
  if (authorization.planTargetState != plan.targetState) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_plan_target_mismatch',
    );
  }
  if (prep.isFiado || prep.hasCombo || prep.isEdicao || prep.isCancelamento) {
    return const PdvV1TransitionAuthorizationValidation(
      valid: false,
      reasonCode: 'authorization_scope_blocked',
    );
  }

  switch (authorization.authorizationKind) {
    case PdvV1SimulatedTransitionAuthorizationKind.planTargetTransition:
      if (proposedStateAfter != plan.targetState) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_kind_plan_target_mismatch',
        );
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind
          .confirmedHiveSaleUpsertTransition:
      if (authorization.stateBefore != PdvV1JournalState.hiveSalePending ||
          authorization.stateAfter != PdvV1JournalState.hiveSaleCompleted ||
          confirmation?.stage !=
              PdvV1SimulatedConfirmationStage.hiveSaleUpsert ||
          confirmation?.status !=
              PdvV1SimulatedConfirmationStatus.confirmedCompatible ||
          confirmation?.expectedTargetState !=
              PdvV1JournalState.hiveSaleCompleted) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_hive_stage_invalid',
        );
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind.confirmedSaleSyncTransition:
      if (authorization.stateBefore != PdvV1JournalState.saleSyncPending ||
          authorization.stateAfter != PdvV1JournalState.saleSyncCompleted ||
          confirmation?.stage != PdvV1SimulatedConfirmationStage.saleSync ||
          confirmation?.status !=
              PdvV1SimulatedConfirmationStatus.confirmedCompatible ||
          confirmation?.expectedTargetState !=
              PdvV1JournalState.saleSyncCompleted) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_sale_sync_stage_invalid',
        );
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind.confirmedEffectsTransition:
      final required = requiredEffectsKeys.isNotEmpty
          ? requiredEffectsKeys
          : confirmation?.requiredEffectsKeys ?? const [];
      final completed = confirmation?.completedEffectsKeys ?? const [];
      if (authorization.stateBefore != PdvV1JournalState.effectsPending ||
          authorization.stateAfter != PdvV1JournalState.effectsCompleted ||
          confirmation?.stage != PdvV1SimulatedConfirmationStage.effects ||
          confirmation?.status !=
              PdvV1SimulatedConfirmationStatus.confirmedCompatible) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_effects_stage_invalid',
        );
      }
      for (final key in required) {
        if (!completed.contains(key)) {
          return const PdvV1TransitionAuthorizationValidation(
            valid: false,
            reasonCode: 'authorization_effects_incomplete',
          );
        }
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind
          .confirmedOperationCompletionTransition:
      final required = requiredEffectsKeys.isNotEmpty
          ? requiredEffectsKeys
          : confirmation?.requiredEffectsKeys ?? const [];
      final completed = confirmation?.completedEffectsKeys ?? const [];
      if (authorization.stateBefore != PdvV1JournalState.effectsCompleted ||
          authorization.stateAfter != PdvV1JournalState.operationCompleted ||
          confirmation?.stage !=
              PdvV1SimulatedConfirmationStage.operationCompletion ||
          confirmation?.status !=
              PdvV1SimulatedConfirmationStatus.confirmedCompatible) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_operation_completion_stage_invalid',
        );
      }
      for (final key in required) {
        if (!completed.contains(key)) {
          return const PdvV1TransitionAuthorizationValidation(
            valid: false,
            reasonCode: 'authorization_effects_not_proven_for_completion',
          );
        }
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind.stageStartSaleSyncTransition:
      if (authorization.stateBefore != PdvV1JournalState.hiveSaleCompleted ||
          authorization.stateAfter != PdvV1JournalState.saleSyncPending ||
          stageStartRequest?.stageToStart !=
              PdvV1SimulatedConfirmationStage.saleSync ||
          stageStartRequest?.expectedStateBefore !=
              PdvV1JournalState.hiveSaleCompleted ||
          stageStartRequest?.expectedTargetState !=
              PdvV1JournalState.saleSyncPending) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_stage_start_sale_sync_invalid',
        );
      }
      break;
    case PdvV1SimulatedTransitionAuthorizationKind.stageStartEffectsTransition:
      if (authorization.stateBefore != PdvV1JournalState.saleSyncCompleted ||
          authorization.stateAfter != PdvV1JournalState.effectsPending ||
          stageStartRequest?.stageToStart !=
              PdvV1SimulatedConfirmationStage.effects ||
          stageStartRequest?.expectedStateBefore !=
              PdvV1JournalState.saleSyncCompleted ||
          stageStartRequest?.expectedTargetState !=
              PdvV1JournalState.effectsPending) {
        return const PdvV1TransitionAuthorizationValidation(
          valid: false,
          reasonCode: 'authorization_stage_start_effects_invalid',
        );
      }
      break;
  }

  return const PdvV1TransitionAuthorizationValidation(valid: true);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Entrada em memória do orquestrador — sem Box, Firebase ou callbacks.
class PdvV1RecoveryOrchestratorInput {
  const PdvV1RecoveryOrchestratorInput({
    this.journalOutcome,
    this.evidence,
    this.hiveMatches = const [],
    this.context = const PdvV1RecoveryContext(),
  });

  final PdvV1JournalReadOutcome? journalOutcome;
  final PdvV1RemoteVerificationEvidence? evidence;
  final List<PdvV1HiveSaleMatch> hiveMatches;
  final PdvV1RecoveryContext context;
}

String pdvV1BuildIdempotencyKey({
  required String operationId,
  required PdvV1JournalState currentState,
  required PdvV1RecoveryDecision decision,
  required PdvV1JournalState targetState,
}) {
  return '$operationId:${currentState.name}:${decision.name}:${targetState.name}';
}

const pdvV1RecoveryPlanFingerprintVersion = 2;
const pdvV1SimulatedConfirmationVersion = 1;

/// Fingerprint diagnóstico — não é autorização isolada de execução.
class PdvV1RecoveryPlanFingerprint {
  PdvV1RecoveryPlanFingerprint({
    this.fingerprintVersion = pdvV1RecoveryPlanFingerprintVersion,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.currentState,
    required this.targetState,
    required this.decision,
    required List<PdvV1RecoveryPlannedAction> plannedActions,
    required this.journalRevisionAtPlan,
    required Map<String, dynamic> journalIdentity,
    required this.verificationStatus,
    this.evidenceVersion = pdvV1RemoteEvidenceVersion,
    this.markerIdentitySummary = const {},
    required List<Map<String, dynamic>> hiveMatchesCanonical,
  })  : plannedActions = pdvV1FreezePlannedActionsSemantic(plannedActions),
        journalIdentity = Map<String, dynamic>.unmodifiable(
          Map<String, dynamic>.from(journalIdentity),
        ),
        hiveMatchesCanonical = List<Map<String, dynamic>>.unmodifiable(
          _canonicalHiveMatchesMaps(hiveMatchesCanonical),
        );

  final int fingerprintVersion;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final PdvV1JournalState currentState;
  final PdvV1JournalState targetState;
  final PdvV1RecoveryDecision decision;
  final List<PdvV1RecoveryPlannedAction> plannedActions;
  final int journalRevisionAtPlan;
  final Map<String, dynamic> journalIdentity;
  final String verificationStatus;
  final int evidenceVersion;
  final Map<String, dynamic> markerIdentitySummary;
  final List<Map<String, dynamic>> hiveMatchesCanonical;

  Map<String, dynamic> toJson() => {
        'fingerprintVersion': fingerprintVersion,
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origem,
        'protocolVersion': protocolVersion,
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'currentState': currentState.name,
        'targetState': targetState.name,
        'decision': decision.name,
        'plannedActions': plannedActions.map((a) => a.name).toList(),
        'journalRevisionAtPlan': journalRevisionAtPlan,
        'journalIdentity': Map<String, dynamic>.from(journalIdentity),
        'verificationStatus': verificationStatus,
        'evidenceVersion': evidenceVersion,
        'markerIdentitySummary': markerIdentitySummary,
        'hiveMatchesCanonical': hiveMatchesCanonical,
      };

  String toCanonicalDiagnosticKey() {
    final actions = plannedActions.map((a) => a.name).join('>');
    final matches = hiveMatchesCanonical.map((m) => m.toString()).join('|');
    final marker = markerIdentitySummary.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');
    final identity =
        journalIdentity.entries.map((e) => '${e.key}=${e.value}').join('|');
    return [
      'fpv$fingerprintVersion',
      operationId,
      saleId,
      lojaId,
      origem,
      '$protocolVersion',
      snapshotHash,
      txItemsHash,
      currentState.name,
      targetState.name,
      decision.name,
      actions,
      '$journalRevisionAtPlan',
      identity,
      verificationStatus,
      '$evidenceVersion',
      marker,
      matches,
    ].join(':');
  }

  bool identityMatchesConfirmation(PdvV1SimulatedStageConfirmation c) {
    return c.operationId == operationId &&
        c.saleId == saleId &&
        c.lojaId == lojaId &&
        c.origem == origem &&
        c.protocolVersion == protocolVersion &&
        c.snapshotHash == snapshotHash &&
        c.txItemsHash == txItemsHash &&
        c.expectedJournalRevision == journalRevisionAtPlan &&
        c.planFingerprint.toCanonicalDiagnosticKey() ==
            toCanonicalDiagnosticKey();
  }

  @override
  bool operator ==(Object other) {
    if (other is! PdvV1RecoveryPlanFingerprint) return false;
    return toCanonicalDiagnosticKey() == other.toCanonicalDiagnosticKey();
  }

  @override
  int get hashCode => toCanonicalDiagnosticKey().hashCode;
}

List<Map<String, dynamic>> _canonicalHiveMatchesMaps(
  List<Map<String, dynamic>> maps,
) {
  final copy = maps.map(Map<String, dynamic>.from).toList();
  copy.sort((a, b) {
    final ka = '${a['hiveKey']}:${a['saleId']}:${a['snapshotHash']}';
    final kb = '${b['hiveKey']}:${b['saleId']}:${b['snapshotHash']}';
    return ka.compareTo(kb);
  });
  return copy;
}

Map<String, dynamic> pdvV1BuildMarkerIdentitySummary(
  PdvV1RemoteMarkerInput marker,
) {
  if (!marker.presente) return const {};
  return {
    'presente': true,
    'operationId': marker.operationId,
    'saleId': marker.saleId,
    'lojaId': marker.lojaId,
    'txItemsHash': marker.txItemsHash,
    'baixaAplicada': marker.baixaAplicada,
  };
}

PdvV1RecoveryPlanFingerprint pdvV1BuildRecoveryPlanFingerprint({
  required PdvV1RecoveryPlan plan,
  required PdvV1PreparedSnapshot prep,
  PdvV1RemoteVerificationEvidence? evidence,
  List<PdvV1HiveSaleMatch> hiveMatches = const [],
}) {
  if (pdvV1RecoveryPlanIsMalformedBoundary(plan)) {
    return PdvV1RecoveryPlanFingerprint(
      operationId: '',
      saleId: '',
      lojaId: '',
      origem: '',
      protocolVersion: 0,
      snapshotHash: '',
      txItemsHash: '',
      currentState: plan.currentState,
      targetState: plan.targetState,
      decision: plan.decision,
      plannedActions: plan.plannedActions,
      journalRevisionAtPlan: plan.journalRevisionAtPlan,
      journalIdentity: pdvV1MalformedSafeJournalIdentity(),
      verificationStatus: 'malformed_boundary',
      hiveMatchesCanonical: const [],
    );
  }
  return PdvV1RecoveryPlanFingerprint(
    operationId: plan.operationId,
    saleId: plan.saleId,
    lojaId: prep.lojaId,
    origem: prep.origemProtocol,
    protocolVersion: prep.protocolVersion,
    snapshotHash: prep.snapshotHash,
    txItemsHash: prep.txItemsHash,
    currentState: plan.currentState,
    targetState: plan.targetState,
    decision: plan.decision,
    plannedActions: plan.plannedActions,
    journalRevisionAtPlan: plan.journalRevisionAtPlan,
    journalIdentity: plan.journalIdentity,
    verificationStatus: pdvV1VerificationStatusForFingerprint(
      currentState: plan.currentState,
      evidence: evidence,
    ),
    evidenceVersion: evidence?.evidenceVersion ?? pdvV1RemoteEvidenceVersion,
    markerIdentitySummary: evidence == null
        ? const {}
        : pdvV1BuildMarkerIdentitySummary(evidence.optionalMarker),
    hiveMatchesCanonical: pdvV1CanonicalHiveMatchesJson(hiveMatches),
  );
}

/// Estágio sintético de confirmação futura.
enum PdvV1SimulatedConfirmationStage {
  hiveSaleUpsert,
  saleSync,
  effects,
  operationCompletion,
}

/// Status tipado de confirmação sintética.
enum PdvV1SimulatedConfirmationStatus {
  confirmedCompatible,
  deferred,
  unavailable,
  divergentOrInvalid,
}

/// Tipo de pedido de início de etapa pendente — somente memória.
enum PdvV1SimulatedStageStartRequestKind {
  pendingStageEntry,
}

class PdvV1StageStartRequestValidation {
  const PdvV1StageStartRequestValidation({
    required this.valid,
    this.reasonCode = '',
  });

  final bool valid;
  final String reasonCode;
}

/// Pedido tipado para entrar em estado Pending — não executa integração.
class PdvV1SimulatedStageStartRequest {
  const PdvV1SimulatedStageStartRequest({
    this.requestVersion = pdvV1SimulatedStageStartRequestVersion,
    required this.planFingerprint,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.expectedJournalRevision,
    required this.expectedStateBefore,
    required this.expectedTargetState,
    required this.stageToStart,
    required this.requestKind,
    required this.semanticPlanValidated,
    required this.identityValidated,
  });

  final int requestVersion;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final int expectedJournalRevision;
  final PdvV1JournalState expectedStateBefore;
  final PdvV1JournalState expectedTargetState;
  final PdvV1SimulatedConfirmationStage stageToStart;
  final PdvV1SimulatedStageStartRequestKind requestKind;
  final bool semanticPlanValidated;
  final bool identityValidated;

  Map<String, dynamic> toJson() => {
        'requestVersion': requestVersion,
        'planFingerprint': planFingerprint.toJson(),
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origem,
        'protocolVersion': protocolVersion,
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'expectedJournalRevision': expectedJournalRevision,
        'expectedStateBefore': expectedStateBefore.name,
        'expectedTargetState': expectedTargetState.name,
        'stageToStart': stageToStart.name,
        'requestKind': requestKind.name,
        'semanticPlanValidated': semanticPlanValidated,
        'identityValidated': identityValidated,
      };
}

PdvV1StageStartRequestValidation pdvV1ValidateStageStartRequest({
  required PdvV1SimulatedStageStartRequest request,
  required PdvV1JournalRecord record,
  required PdvV1PreparedSnapshot prep,
  required PdvV1RecoveryPlan plan,
  required PdvV1RecoveryPlanFingerprint fingerprint,
}) {
  if (!request.identityValidated || !request.semanticPlanValidated) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_flags_invalid',
    );
  }
  if (request.requestKind !=
      PdvV1SimulatedStageStartRequestKind.pendingStageEntry) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_kind_invalid',
    );
  }
  if (request.expectedJournalRevision != record.journalRevision) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stale_stage_start_revision',
    );
  }
  if (request.planFingerprint.toCanonicalDiagnosticKey() !=
      fingerprint.toCanonicalDiagnosticKey()) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_fingerprint_mismatch',
    );
  }
  if (request.operationId != prep.operationId ||
      request.saleId != prep.saleId ||
      request.lojaId != prep.lojaId ||
      request.origem != prep.origemProtocol ||
      request.protocolVersion != prep.protocolVersion ||
      request.snapshotHash != prep.snapshotHash ||
      request.txItemsHash != prep.txItemsHash) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_identity_mismatch',
    );
  }
  if (request.expectedStateBefore != record.state) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_state_before_mismatch',
    );
  }
  if (!plan.requiresExternalIntegration) {
    return const PdvV1StageStartRequestValidation(
      valid: false,
      reasonCode: 'stage_start_plan_not_integration',
    );
  }
  switch (request.stageToStart) {
    case PdvV1SimulatedConfirmationStage.saleSync:
      if (record.state != PdvV1JournalState.hiveSaleCompleted ||
          request.expectedTargetState != PdvV1JournalState.saleSyncPending) {
        return const PdvV1StageStartRequestValidation(
          valid: false,
          reasonCode: 'stage_start_sale_sync_state_invalid',
        );
      }
      break;
    case PdvV1SimulatedConfirmationStage.effects:
      if (record.state != PdvV1JournalState.saleSyncCompleted ||
          request.expectedTargetState != PdvV1JournalState.effectsPending) {
        return const PdvV1StageStartRequestValidation(
          valid: false,
          reasonCode: 'stage_start_effects_state_invalid',
        );
      }
      break;
    case PdvV1SimulatedConfirmationStage.hiveSaleUpsert:
    case PdvV1SimulatedConfirmationStage.operationCompletion:
      return const PdvV1StageStartRequestValidation(
        valid: false,
        reasonCode: 'stage_start_stage_not_allowed',
      );
  }
  return const PdvV1StageStartRequestValidation(valid: true);
}

/// Confirmação tipada sintética — não prova execução real.
class PdvV1SimulatedStageConfirmation {
  PdvV1SimulatedStageConfirmation({
    this.confirmationVersion = pdvV1SimulatedConfirmationVersion,
    required this.planFingerprint,
    required this.expectedJournalRevision,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.expectedStateBefore,
    required this.expectedTargetState,
    required this.stage,
    required this.status,
    List<String> requiredEffectsKeys = const [],
    List<String> completedEffectsKeys = const [],
    this.reasonCode = '',
  })  : requiredEffectsKeys = List<String>.unmodifiable(
          List<String>.from(requiredEffectsKeys)..sort(),
        ),
        completedEffectsKeys = List<String>.unmodifiable(
          List<String>.from(completedEffectsKeys)..sort(),
        );

  final int confirmationVersion;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final int expectedJournalRevision;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final PdvV1JournalState expectedStateBefore;
  final PdvV1JournalState expectedTargetState;
  final PdvV1SimulatedConfirmationStage stage;
  final PdvV1SimulatedConfirmationStatus status;
  final List<String> requiredEffectsKeys;
  final List<String> completedEffectsKeys;
  final String reasonCode;

  Map<String, dynamic> toJson() => {
        'confirmationVersion': confirmationVersion,
        'planFingerprint': planFingerprint.toJson(),
        'expectedJournalRevision': expectedJournalRevision,
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origem,
        'protocolVersion': protocolVersion,
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'expectedStateBefore': expectedStateBefore.name,
        'expectedTargetState': expectedTargetState.name,
        'stage': stage.name,
        'status': status.name,
        'requiredEffectsKeys': requiredEffectsKeys,
        'completedEffectsKeys': completedEffectsKeys,
        'reasonCode': reasonCode,
      };
}

/// Contexto sintético do executor — somente dados em memória.
class PdvV1RecoveryExecutorContext {
  const PdvV1RecoveryExecutorContext({
    this.hiveMatches = const [],
    this.evidence,
    this.requiredEffectsKeys = const [],
  });

  final List<PdvV1HiveSaleMatch> hiveMatches;
  final PdvV1RemoteVerificationEvidence? evidence;
  final List<String> requiredEffectsKeys;
}

/// Entrada do executor simulado.
class PdvV1RecoveryExecutorInput {
  const PdvV1RecoveryExecutorInput({
    required this.journalOutcome,
    required this.plan,
    this.confirmation,
    this.stageStartRequest,
    this.context = const PdvV1RecoveryExecutorContext(),
  });

  final PdvV1JournalReadOutcome journalOutcome;
  final PdvV1RecoveryPlan plan;
  final PdvV1SimulatedStageConfirmation? confirmation;
  final PdvV1SimulatedStageStartRequest? stageStartRequest;
  final PdvV1RecoveryExecutorContext context;
}

/// Resultado simulado — apenas proposta em memória.
class PdvV1SimulatedExecutionOutcome {
  PdvV1SimulatedExecutionOutcome({
    required this.decision,
    required this.stateBefore,
    required this.proposedStateAfter,
    required List<PdvV1RecoveryPlannedAction> proposedActions,
    required this.planFingerprint,
    required this.proposedJournalRevision,
    this.transitionAuthorization,
    this.confirmationValidated = false,
    this.semanticPlanValidated = true,
    this.requiresFuturePersistence = false,
    this.requiresExternalIntegration = false,
    this.isDeferred = false,
    this.isManualIntervention = false,
    required this.reasonCode,
    required this.idempotencyDiagnosticKey,
  }) : proposedActions = List<PdvV1RecoveryPlannedAction>.unmodifiable(
          List<PdvV1RecoveryPlannedAction>.from(proposedActions),
        );

  final PdvV1RecoveryDecision decision;
  final PdvV1JournalState stateBefore;
  final PdvV1JournalState proposedStateAfter;
  final List<PdvV1RecoveryPlannedAction> proposedActions;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final int proposedJournalRevision;
  final PdvV1SimulatedTransitionAuthorization? transitionAuthorization;
  final bool confirmationValidated;
  final bool semanticPlanValidated;
  final bool requiresFuturePersistence;
  final bool requiresExternalIntegration;
  final bool isDeferred;
  final bool isManualIntervention;
  final String reasonCode;
  final String idempotencyDiagnosticKey;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        'stateBefore': stateBefore.name,
        'proposedStateAfter': proposedStateAfter.name,
        'proposedActions': proposedActions.map((a) => a.name).toList(),
        'planFingerprint': planFingerprint.toJson(),
        'proposedJournalRevision': proposedJournalRevision,
        if (transitionAuthorization != null)
          'transitionAuthorization': transitionAuthorization!.toJson(),
        'confirmationValidated': confirmationValidated,
        'semanticPlanValidated': semanticPlanValidated,
        'requiresFuturePersistence': requiresFuturePersistence,
        'requiresExternalIntegration': requiresExternalIntegration,
        'isDeferred': isDeferred,
        'isManualIntervention': isManualIntervention,
        'reasonCode': reasonCode,
        'idempotencyDiagnosticKey': idempotencyDiagnosticKey,
      };
}

const pdvV1JournalSameStatePatchAuthorizationVersion = 1;

/// Autorização tipada para patch same-state — emitida somente pelo executor simulado.
class PdvV1JournalSameStatePatchAuthorization {
  const PdvV1JournalSameStatePatchAuthorization({
    this.authorizationVersion = pdvV1JournalSameStatePatchAuthorizationVersion,
    required this.patchKind,
    required this.planFingerprint,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.expectedJournalRevision,
    required this.expectedState,
    required this.expectedAttempts,
    required this.stage,
    required this.failureCode,
    this.semanticPlanValidated = true,
    this.identityValidated = true,
    this.issuedByExecutorOnly = true,
  });

  final int authorizationVersion;
  final PdvV1JournalSameStatePatchKind patchKind;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final int expectedJournalRevision;
  final PdvV1JournalState expectedState;
  final int expectedAttempts;
  final PdvV1SimulatedConfirmationStage stage;
  final PdvV1RetryableStageFailureCode failureCode;
  final bool semanticPlanValidated;
  final bool identityValidated;
  final bool issuedByExecutorOnly;

  Map<String, dynamic> toJson() => {
        'authorizationVersion': authorizationVersion,
        'patchKind': patchKind.name,
        'planFingerprint': planFingerprint.toJson(),
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origem,
        'protocolVersion': protocolVersion,
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'expectedJournalRevision': expectedJournalRevision,
        'expectedState': expectedState.name,
        'expectedAttempts': expectedAttempts,
        'stage': stage.name,
        'failureCode': failureCode.canonicalCode,
        'semanticPlanValidated': semanticPlanValidated,
        'identityValidated': identityValidated,
        'issuedByExecutorOnly': issuedByExecutorOnly,
      };
}

/// Resultado da emissão de patch pelo executor — sem persistência.
class PdvV1JournalSameStatePatchIssueOutcome {
  const PdvV1JournalSameStatePatchIssueOutcome({
    required this.authorized,
    required this.rejectionReasonCode,
    this.patch,
    this.authorization,
  });

  final bool authorized;
  final String rejectionReasonCode;
  final PdvV1JournalSameStatePatch? patch;
  final PdvV1JournalSameStatePatchAuthorization? authorization;

  Map<String, dynamic> toJson() => {
        'authorized': authorized,
        'rejectionReasonCode': rejectionReasonCode,
        if (patch != null) 'patch': patch!.toJson(),
        if (authorization != null) 'authorization': authorization!.toJson(),
      };
}

/// Entrada para emissão de patch retryable pelo executor simulado.
class PdvV1RecoveryExecutorSameStatePatchInput {
  const PdvV1RecoveryExecutorSameStatePatchInput({
    required this.journalOutcome,
    required this.plan,
    required this.planFingerprint,
    required this.stage,
    this.evidence,
    this.confirmation,
    this.stageStartRequest,
  });

  final PdvV1JournalReadOutcome journalOutcome;
  final PdvV1RecoveryPlan plan;
  final PdvV1RecoveryPlanFingerprint planFingerprint;
  final PdvV1SimulatedConfirmationStage stage;
  final PdvV1RemoteVerificationEvidence? evidence;
  final PdvV1SimulatedStageConfirmation? confirmation;
  final PdvV1SimulatedStageStartRequest? stageStartRequest;
}

PdvV1JournalSameStatePatchIssueOutcome pdvV1RejectSameStatePatchIssue(
  String reasonCode,
) {
  return PdvV1JournalSameStatePatchIssueOutcome(
    authorized: false,
    rejectionReasonCode: reasonCode,
  );
}

/// Validação direta de autorização contra journal armazenado — fail-closed.
String? pdvV1ValidateSameStatePatchAuthorization({
  required PdvV1JournalRecord stored,
  required PdvV1JournalSameStatePatch patch,
  required PdvV1JournalSameStatePatchAuthorization authorization,
  required int expectedJournalRevision,
}) {
  if (authorization.patchKind !=
      PdvV1JournalSameStatePatchKind.recordRetryableStageFailure) {
    return 'patch_kind_not_supported';
  }
  if (patch.patchKind != authorization.patchKind) {
    return 'patch_kind_mismatch';
  }
  if (authorization.authorizationVersion !=
      pdvV1JournalSameStatePatchAuthorizationVersion) {
    return 'authorization_version_mismatch';
  }
  if (expectedJournalRevision != stored.journalRevision) {
    return 'stale_journal_revision';
  }
  if (authorization.expectedJournalRevision != stored.journalRevision) {
    return 'stale_journal_revision';
  }
  if (stored.isMalformedReadOnly) {
    return 'journal_malformed_patch_denied';
  }
  if (pdvV1JournalStateIsTerminal(stored.state)) {
    return 'terminal_state_patch_denied';
  }
  if (authorization.operationId != stored.operationId ||
      authorization.saleId != stored.saleId ||
      authorization.lojaId != stored.lojaId ||
      authorization.origem != stored.prepared.origemProtocol ||
      authorization.protocolVersion != stored.prepared.protocolVersion ||
      authorization.snapshotHash != stored.prepared.snapshotHash ||
      authorization.txItemsHash != stored.prepared.txItemsHash) {
    return 'identity_mismatch';
  }
  if (patch.expectedState != stored.state ||
      authorization.expectedState != stored.state) {
    return 'patch_state_mismatch';
  }
  if (authorization.stage.name != patch.stageName) {
    return 'patch_stage_mismatch';
  }
  final allowedState =
      pdvV1JournalStateForRetryablePatchStageName(patch.stageName);
  if (allowedState == null || allowedState != stored.state) {
    return 'patch_state_mismatch';
  }
  final allowedCode =
      pdvV1RetryableFailureCodeForPatchStageName(patch.stageName);
  if (allowedCode == null ||
      patch.failureCode != allowedCode ||
      authorization.failureCode != allowedCode) {
    return 'patch_failure_code_mismatch';
  }
  if (stored.attempts < 0) {
    return 'patch_attempts_mismatch';
  }
  if (stored.attempts >= pdvV1MaxRetryableStageFailureAttempts) {
    return 'retry_attempt_limit_reached';
  }
  final nextAttempts = stored.attempts + 1;
  if (patch.expectedAttempts != nextAttempts ||
      authorization.expectedAttempts != nextAttempts) {
    return 'patch_attempts_mismatch';
  }
  if (patch.failureCode != authorization.failureCode) {
    return 'patch_failure_code_mismatch';
  }
  return null;
}
