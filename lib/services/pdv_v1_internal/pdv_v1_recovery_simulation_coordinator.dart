import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_recovery_executor.dart';
import 'pdv_v1_recovery_models.dart';
import 'pdv_v1_recovery_orchestrator.dart';
import 'pdv_v1_recovery_plan_semantics.dart';
import 'pdv_v1_recovery_simulated_cas_store.dart';

/// Entrada sintética do coordenador — somente memória.
class PdvV1RecoverySimulationInput {
  const PdvV1RecoverySimulationInput({
    this.store,
    required this.journalOutcome,
    this.evidence,
    this.hiveMatches = const [],
    this.confirmation,
    this.stageStartRequest,
    this.context = const PdvV1RecoveryContext(),
    this.requiredEffectsKeys = const [],
  });

  final PdvV1RecoverySimulatedCasStore? store;
  final PdvV1JournalReadOutcome journalOutcome;
  final PdvV1RemoteVerificationEvidence? evidence;
  final List<PdvV1HiveSaleMatch> hiveMatches;
  final PdvV1SimulatedStageConfirmation? confirmation;
  final PdvV1SimulatedStageStartRequest? stageStartRequest;
  final PdvV1RecoveryContext context;
  final List<String> requiredEffectsKeys;
}

/// Resultado serializável e imutável de uma execução completa simulada.
class PdvV1RecoverySimulationRunOutcome {
  PdvV1RecoverySimulationRunOutcome({
    required this.initialJournal,
    this.generatedPlan,
    required this.semanticValidation,
    this.executionOutcome,
    this.casApplyOutcome,
    required this.finalJournalSnapshot,
    required this.allStepsDeterministic,
    required this.externalIntegrationNeverExecuted,
    required this.manualInterventionRequired,
    required this.deferred,
    required this.reasonCode,
  });

  final PdvV1JournalRecord initialJournal;
  final PdvV1RecoveryPlan? generatedPlan;
  final PdvV1RecoveryPlanSemanticsValidationResult semanticValidation;
  final PdvV1SimulatedExecutionOutcome? executionOutcome;
  final PdvV1SimulatedCasApplyOutcome? casApplyOutcome;
  final PdvV1JournalRecord finalJournalSnapshot;
  final bool allStepsDeterministic;
  final bool externalIntegrationNeverExecuted;
  final bool manualInterventionRequired;
  final bool deferred;
  final String reasonCode;

  Map<String, dynamic> toJson() => {
        'initialJournal': initialJournal.toJson(),
        if (generatedPlan != null) 'generatedPlan': generatedPlan!.toJson(),
        'semanticValidation': semanticValidation.toJson(),
        if (executionOutcome != null)
          'executionOutcome': executionOutcome!.toJson(),
        if (casApplyOutcome != null)
          'casApplyOutcome': casApplyOutcome!.toJson(),
        'finalJournalSnapshot': finalJournalSnapshot.toJson(),
        'allStepsDeterministic': allStepsDeterministic,
        'externalIntegrationNeverExecuted': externalIntegrationNeverExecuted,
        'manualInterventionRequired': manualInterventionRequired,
        'deferred': deferred,
        'reasonCode': reasonCode,
      };
}

/// Coordenador em memória: snapshot → plano → semântica → executor → CAS.
class PdvV1RecoverySimulationCoordinator {
  PdvV1RecoverySimulationCoordinator({
    PdvV1RecoveryOrchestrator? orchestrator,
    PdvV1RecoveryExecutorSimulator? executor,
    PdvV1RecoveryPlanSemanticsValidator? semanticsValidator,
  })  : _orchestrator = orchestrator ?? PdvV1RecoveryOrchestrator(),
        _executor = executor ?? const PdvV1RecoveryExecutorSimulator(),
        _semanticsValidator =
            semanticsValidator ?? const PdvV1RecoveryPlanSemanticsValidator();

  final PdvV1RecoveryOrchestrator _orchestrator;
  final PdvV1RecoveryExecutorSimulator _executor;
  final PdvV1RecoveryPlanSemanticsValidator _semanticsValidator;

  PdvV1RecoverySimulationRunOutcome run(PdvV1RecoverySimulationInput input) {
    final store = input.store ??
        PdvV1RecoverySimulatedCasStore(input.journalOutcome.record);
    final initialJournal = store.snapshot;
    final journalOutcome = PdvV1JournalReadOutcome(
      record: initialJournal,
      isMalformedReadOnly: input.journalOutcome.isMalformedReadOnly,
      malformedEvidence: input.journalOutcome.malformedEvidence,
    );

    final plan = _orchestrator.plan(
      PdvV1RecoveryOrchestratorInput(
        journalOutcome: journalOutcome,
        evidence: input.evidence,
        hiveMatches: input.hiveMatches,
        context: input.context,
      ),
    );

    final semanticValidation = _semanticsValidator.validate(plan);
    if (!semanticValidation.valid) {
      return PdvV1RecoverySimulationRunOutcome(
        initialJournal: initialJournal,
        generatedPlan: plan,
        semanticValidation: semanticValidation,
        finalJournalSnapshot: store.snapshot,
        allStepsDeterministic: true,
        externalIntegrationNeverExecuted: true,
        manualInterventionRequired: true,
        deferred: false,
        reasonCode: semanticValidation.reasonCode,
      );
    }

    if (journalOutcome.isMalformedReadOnly) {
      return PdvV1RecoverySimulationRunOutcome(
        initialJournal: initialJournal,
        generatedPlan: plan,
        semanticValidation: semanticValidation,
        finalJournalSnapshot: store.snapshot,
        allStepsDeterministic: true,
        externalIntegrationNeverExecuted: true,
        manualInterventionRequired: true,
        deferred: false,
        reasonCode: pdvV1MalformedRecoveryReasonCode,
      );
    }

    final fingerprint = pdvV1BuildRecoveryPlanFingerprint(
      plan: plan,
      prep: initialJournal.prepared,
      evidence: pdvV1EvidenceForRecoveryFingerprint(
        record: initialJournal,
        isMalformedReadOnly: journalOutcome.isMalformedReadOnly,
        evidence: input.evidence,
      ),
      hiveMatches: input.hiveMatches,
    );

    final executionOutcome = _executor.simulate(
      PdvV1RecoveryExecutorInput(
        journalOutcome: journalOutcome,
        plan: plan,
        confirmation: input.confirmation,
        stageStartRequest: input.stageStartRequest,
        context: PdvV1RecoveryExecutorContext(
          hiveMatches: input.hiveMatches,
          evidence: input.evidence,
          requiredEffectsKeys: input.requiredEffectsKeys,
        ),
      ),
    );

    if (executionOutcome.isManualIntervention) {
      return PdvV1RecoverySimulationRunOutcome(
        initialJournal: initialJournal,
        generatedPlan: plan,
        semanticValidation: semanticValidation,
        executionOutcome: executionOutcome,
        finalJournalSnapshot: store.snapshot,
        allStepsDeterministic: true,
        externalIntegrationNeverExecuted: true,
        manualInterventionRequired: true,
        deferred: false,
        reasonCode: executionOutcome.reasonCode,
      );
    }

    if (executionOutcome.isDeferred) {
      return PdvV1RecoverySimulationRunOutcome(
        initialJournal: initialJournal,
        generatedPlan: plan,
        semanticValidation: semanticValidation,
        executionOutcome: executionOutcome,
        finalJournalSnapshot: store.snapshot,
        allStepsDeterministic: true,
        externalIntegrationNeverExecuted: true,
        manualInterventionRequired: false,
        deferred: true,
        reasonCode: executionOutcome.reasonCode,
      );
    }

    if (executionOutcome.decision == PdvV1RecoveryDecision.noAction) {
      return PdvV1RecoverySimulationRunOutcome(
        initialJournal: initialJournal,
        generatedPlan: plan,
        semanticValidation: semanticValidation,
        executionOutcome: executionOutcome,
        finalJournalSnapshot: store.snapshot,
        allStepsDeterministic: true,
        externalIntegrationNeverExecuted: true,
        manualInterventionRequired: false,
        deferred: false,
        reasonCode: executionOutcome.reasonCode,
      );
    }

    final casApplyOutcome = store.applySimulatedOutcome(
      expectedJournalRevision: plan.journalRevisionAtPlan,
      plan: plan,
      planFingerprint: fingerprint,
      proposedExecutionOutcome: executionOutcome,
      semanticPlanValidated: semanticValidation.valid,
      confirmation: input.confirmation,
      stageStartRequest: input.stageStartRequest,
      requiredEffectsKeys: input.requiredEffectsKeys,
    );

    return PdvV1RecoverySimulationRunOutcome(
      initialJournal: initialJournal,
      generatedPlan: plan,
      semanticValidation: semanticValidation,
      executionOutcome: executionOutcome,
      casApplyOutcome: casApplyOutcome,
      finalJournalSnapshot: store.snapshot,
      allStepsDeterministic: true,
      externalIntegrationNeverExecuted: true,
      manualInterventionRequired: !casApplyOutcome.accepted &&
          (executionOutcome.isManualIntervention ||
              casApplyOutcome.stalePlanRejected),
      deferred: executionOutcome.isDeferred,
      reasonCode: casApplyOutcome.accepted
          ? executionOutcome.reasonCode
          : casApplyOutcome.rejectionReasonCode,
    );
  }
}
