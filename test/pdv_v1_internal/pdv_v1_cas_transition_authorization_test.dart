import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-auth-1',
    saleId: 'sale-auth-1',
    lojaId: 'loja-auth-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-auth-1',
    txItemsHash: 'tx-auth-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _journal(PdvV1JournalState state, {int revision = 0}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
  );
}

PdvV1RemoteVerificationEvidence _evidence() {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: 'op-auth-1',
    requestedSaleId: 'sale-auth-1',
    requestedLojaId: 'loja-auth-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-auth-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-auth-1',
      operationId: 'op-auth-1',
      saleId: 'sale-auth-1',
      baixaAplicada: true,
      txItemsHash: 'tx-auth-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

PdvV1RecoveryPlan _integrationPlan(PdvV1JournalRecord record) {
  return PdvV1RecoveryPlan(
    decision: PdvV1RecoveryDecision.requireExternalIntegration,
    currentState: record.state,
    targetState: record.state,
    plannedActions: const [PdvV1RecoveryPlannedAction.awaitExternalIntegration],
    reasonCode: 'state_requires_integration',
    operationId: 'op-auth-1',
    saleId: 'sale-auth-1',
    journalRevisionAtPlan: record.journalRevision,
    journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
    requiresExternalIntegration: true,
    idempotencyKey: 'integration-${record.state}',
  );
}

PdvV1SimulatedStageConfirmation _confirmation({
  required PdvV1RecoveryPlanFingerprint fp,
  required PdvV1SimulatedConfirmationStage stage,
  int expectedJournalRevision = 0,
  PdvV1JournalState? expectedStateBefore,
  PdvV1JournalState? expectedTargetState,
  List<String> requiredEffectsKeys = const [],
  List<String> completedEffectsKeys = const [],
}) {
  late PdvV1JournalState stateBefore;
  late PdvV1JournalState targetState;
  switch (stage) {
    case PdvV1SimulatedConfirmationStage.hiveSaleUpsert:
      stateBefore = expectedStateBefore ?? PdvV1JournalState.hiveSalePending;
      targetState = expectedTargetState ?? PdvV1JournalState.hiveSaleCompleted;
      break;
    case PdvV1SimulatedConfirmationStage.saleSync:
      stateBefore = expectedStateBefore ?? PdvV1JournalState.saleSyncPending;
      targetState = expectedTargetState ?? PdvV1JournalState.saleSyncCompleted;
      break;
    case PdvV1SimulatedConfirmationStage.effects:
      stateBefore = expectedStateBefore ?? PdvV1JournalState.effectsPending;
      targetState = expectedTargetState ?? PdvV1JournalState.effectsCompleted;
      break;
    case PdvV1SimulatedConfirmationStage.operationCompletion:
      stateBefore = expectedStateBefore ?? PdvV1JournalState.effectsCompleted;
      targetState = expectedTargetState ?? PdvV1JournalState.operationCompleted;
      break;
  }
  return PdvV1SimulatedStageConfirmation(
    planFingerprint: fp,
    expectedJournalRevision: expectedJournalRevision,
    operationId: 'op-auth-1',
    saleId: 'sale-auth-1',
    lojaId: 'loja-auth-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-auth-1',
    txItemsHash: 'tx-auth-1',
    expectedStateBefore: stateBefore,
    expectedTargetState: targetState,
    stage: stage,
    status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
    requiredEffectsKeys: requiredEffectsKeys,
    completedEffectsKeys: completedEffectsKeys,
  );
}

void main() {
  const executor = PdvV1RecoveryExecutorSimulator();
  final orchestrator = PdvV1RecoveryOrchestrator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('PdvV1SimulatedTransitionAuthorization e CAS', () {
    test('CAS aceita proposedStateAfter igual ao plan.targetState', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
        evidence: _evidence(),
      );
      final execution = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          context: PdvV1RecoveryExecutorContext(evidence: _evidence()),
        ),
      );
      expect(execution.proposedStateAfter, plan.targetState);
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isTrue);
    });

    test('CAS rejeita override sem authorization', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'override_without_auth',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
      );
      final before = store.snapshot.toJson();
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'unauthorized_transition_override');
      expect(store.snapshot.toJson(), before);
    });

    PdvV1SimulatedTransitionAuthorization validAuth({
      required PdvV1JournalRecord record,
      required PdvV1RecoveryPlan plan,
      required PdvV1RecoveryPlanFingerprint fp,
      required PdvV1JournalState stateAfter,
      required PdvV1SimulatedTransitionAuthorizationKind kind,
      PdvV1SimulatedConfirmationStage? stage,
    }) {
      return PdvV1SimulatedTransitionAuthorization(
        planFingerprint: fp,
        operationId: record.prepared.operationId,
        saleId: record.prepared.saleId,
        lojaId: record.prepared.lojaId,
        origem: record.prepared.origemProtocol,
        protocolVersion: record.prepared.protocolVersion,
        snapshotHash: record.prepared.snapshotHash,
        txItemsHash: record.prepared.txItemsHash,
        journalRevisionAtAuthorization: record.journalRevision,
        stateBefore: record.state,
        stateAfter: stateAfter,
        planTargetState: plan.targetState,
        authorizationKind: kind,
        confirmationStage: stage,
        confirmationStatus:
            PdvV1SimulatedConfirmationStatus.confirmedCompatible,
        semanticPlanValidated: true,
        identityValidated: true,
        issuedByExecutorOnly: true,
      );
    }

    test('CAS rejeita authorization com fingerprint divergente', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final badFp = PdvV1RecoveryPlanFingerprint(
        operationId: fp.operationId,
        saleId: fp.saleId,
        lojaId: fp.lojaId,
        origem: fp.origem,
        protocolVersion: fp.protocolVersion,
        snapshotHash: fp.snapshotHash,
        txItemsHash: 'tx-DIVERGENTE',
        currentState: fp.currentState,
        targetState: fp.targetState,
        decision: fp.decision,
        plannedActions: fp.plannedActions,
        journalRevisionAtPlan: fp.journalRevisionAtPlan,
        journalIdentity: fp.journalIdentity,
        verificationStatus: fp.verificationStatus,
        hiveMatchesCanonical: fp.hiveMatchesCanonical,
      );
      final auth = validAuth(
        record: record,
        plan: plan,
        fp: badFp,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        kind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      );
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'authorization_fingerprint_mismatch');
    });

    test('CAS rejeita authorization com saleId divergente', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final auth = PdvV1SimulatedTransitionAuthorization(
        planFingerprint: fp,
        operationId: record.prepared.operationId,
        saleId: 'sale-DIVERGENTE',
        lojaId: record.prepared.lojaId,
        origem: record.prepared.origemProtocol,
        protocolVersion: record.prepared.protocolVersion,
        snapshotHash: record.prepared.snapshotHash,
        txItemsHash: record.prepared.txItemsHash,
        journalRevisionAtAuthorization: record.journalRevision,
        stateBefore: record.state,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        planTargetState: plan.targetState,
        authorizationKind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
        confirmationStage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        confirmationStatus:
            PdvV1SimulatedConfirmationStatus.confirmedCompatible,
        semanticPlanValidated: true,
        identityValidated: true,
        issuedByExecutorOnly: true,
      );
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'authorization_identity_mismatch');
    });

    test('CAS rejeita authorization com revision divergente', () {
      final record = _journal(PdvV1JournalState.hiveSalePending, revision: 2);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final auth = validAuth(
        record: record,
        plan: plan,
        fp: fp,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        kind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      ).copyWithRevision(0);
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 3,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 2,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          expectedJournalRevision: 2,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'stale_authorization_revision');
    });

    test('CAS rejeita authorization com stateBefore divergente', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final auth = validAuth(
        record: record,
        plan: plan,
        fp: fp,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        kind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      ).copyWithStateBefore(PdvV1JournalState.saleSyncPending);
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(
          outcome.rejectionReasonCode, 'authorization_state_before_mismatch');
    });

    test('CAS rejeita authorization com planTargetState divergente', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final auth = validAuth(
        record: record,
        plan: plan,
        fp: fp,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        kind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      ).copyWithPlanTargetState(PdvV1JournalState.saleSyncCompleted);
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'authorization_plan_target_mismatch');
    });

    test('CAS rejeita authorization de estágio errado', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final auth = validAuth(
        record: record,
        plan: plan,
        fp: fp,
        stateAfter: PdvV1JournalState.hiveSaleCompleted,
        kind: PdvV1SimulatedTransitionAuthorizationKind
            .confirmedSaleSyncTransition,
        stage: PdvV1SimulatedConfirmationStage.saleSync,
      );
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: plan.decision,
        stateBefore: record.state,
        proposedStateAfter: PdvV1JournalState.hiveSaleCompleted,
        proposedActions: plan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'confirmed',
        idempotencyDiagnosticKey: plan.idempotencyKey,
        semanticPlanValidated: true,
        transitionAuthorization: auth,
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
        confirmation: _confirmation(
          fp: fp,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(
          outcome.rejectionReasonCode, 'authorization_sale_sync_stage_invalid');
    });

    test('Hive confirmation autorizada: hiveSalePending → hiveSaleCompleted',
        () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          ),
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.hiveSaleCompleted);
      expect(
        run.executionOutcome!.transitionAuthorization!.authorizationKind,
        PdvV1SimulatedTransitionAuthorizationKind
            .confirmedHiveSaleUpsertTransition,
      );
    });

    test(
        'SaleSync confirmation autorizada: saleSyncPending → saleSyncCompleted',
        () {
      final record = _journal(PdvV1JournalState.saleSyncPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
          ),
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.saleSyncCompleted);
    });

    test('Effects confirmation autorizada apenas com todos effects', () {
      final record = _journal(PdvV1JournalState.effectsPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            requiredEffectsKeys: const ['a', 'b'],
            completedEffectsKeys: const ['a', 'b'],
          ),
          requiredEffectsKeys: const ['a', 'b'],
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.effectsCompleted);
    });

    test(
        'Operation completion autorizada: effectsCompleted → operationCompleted',
        () {
      final record = _journal(PdvV1JournalState.effectsCompleted);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.operationCompletion,
            requiredEffectsKeys: const ['x'],
            completedEffectsKeys: const ['x'],
          ),
          requiredEffectsKeys: const ['x'],
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.operationCompleted);
    });

    test('Confirmação Hive em saleSyncPending é rejeitada pelo executor', () {
      final record = _journal(PdvV1JournalState.saleSyncPending);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            expectedStateBefore: PdvV1JournalState.saleSyncPending,
            expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.transitionAuthorization, isNull);
    });

    test('Confirmação SaleSync em hiveSalePending é rejeitada pelo executor',
        () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            expectedStateBefore: PdvV1JournalState.hiveSalePending,
            expectedTargetState: PdvV1JournalState.saleSyncCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.transitionAuthorization, isNull);
    });

    test('Confirmação stale não altera CAS store', () {
      final record = _journal(PdvV1JournalState.hiveSalePending, revision: 2);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final before = store.snapshot.toJson();
      coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            expectedJournalRevision: 0,
          ),
        ),
      );
      expect(store.snapshot.toJson(), before);
    });

    test('Plano stale não altera CAS store', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
          plan: plan,
          prep: record.prepared,
          evidence: _evidence(),
        ),
        proposedExecutionOutcome: executor.simulate(
          PdvV1RecoveryExecutorInput(
            journalOutcome: PdvV1JournalReadOutcome(record: record),
            plan: plan,
            context: PdvV1RecoveryExecutorContext(evidence: _evidence()),
          ),
        ),
        semanticPlanValidated: true,
      );
      final stalePlan = plan.copyWith(journalRevisionAtPlan: 0);
      final before = store.snapshot.toJson();
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: stalePlan,
        planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
          plan: stalePlan,
          prep: store.snapshot.prepared,
          evidence: _evidence(),
        ),
        proposedExecutionOutcome: PdvV1SimulatedExecutionOutcome(
          decision: stalePlan.decision,
          stateBefore: PdvV1JournalState.remoteStockApplied,
          proposedStateAfter: PdvV1JournalState.hiveSalePending,
          proposedActions: stalePlan.plannedActions,
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: stalePlan,
            prep: store.snapshot.prepared,
            evidence: _evidence(),
          ),
          proposedJournalRevision: 2,
          reasonCode: 'stale',
          idempotencyDiagnosticKey: stalePlan.idempotencyKey,
          semanticPlanValidated: true,
        ),
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.stalePlanRejected, isTrue);
      expect(store.snapshot.toJson(), before);
    });

    test('Journal malformado não atravessa a fronteira do plano', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {
          'secret': 'TOKEN',
          'prepared': {'operationId': 'op-mal'},
        },
        storageKey: 'op-mal',
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      expect(plan.journalIdentity['malformedBoundary'], isTrue);
      expect(plan.toJson().toString().contains('TOKEN'), isFalse);
    });

    test('Journal malformado não produz authorization', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {
          'prepared': {'operationId': 'op-mal-2'}
        },
        storageKey: 'op-mal-2',
      );
      final exec = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: outcome,
          plan: orchestrator.plan(
            PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
          ),
        ),
      );
      expect(exec.transitionAuthorization, isNull);
    });

    test('Journal malformado não aceita confirmação', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {
          'prepared': {'operationId': 'op-mal-3'}
        },
        storageKey: 'op-mal-3',
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: outcome.record.prepared,
      );
      final store = PdvV1RecoverySimulatedCasStore(outcome.record);
      final before = store.snapshot.toJson();
      coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: outcome,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          ),
        ),
      );
      expect(store.snapshot.toJson(), before);
    });

    test('Três execuções idênticas produzem o mesmo JSON', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final confirmation = _confirmation(
        fp: fp,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      );
      final runs = List.generate(3, (_) {
        final store = PdvV1RecoverySimulatedCasStore(record);
        final run = coordinator.run(
          PdvV1RecoverySimulationInput(
            store: store,
            journalOutcome: PdvV1JournalReadOutcome(record: record),
            confirmation: confirmation,
          ),
        );
        return jsonEncode(run.toJson());
      });
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });
  });
}

extension on PdvV1SimulatedTransitionAuthorization {
  PdvV1SimulatedTransitionAuthorization copyWithRevision(int revision) {
    return PdvV1SimulatedTransitionAuthorization(
      authorizationVersion: authorizationVersion,
      planFingerprint: planFingerprint,
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      origem: origem,
      protocolVersion: protocolVersion,
      snapshotHash: snapshotHash,
      txItemsHash: txItemsHash,
      journalRevisionAtAuthorization: revision,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      planTargetState: planTargetState,
      authorizationKind: authorizationKind,
      confirmationStage: confirmationStage,
      confirmationStatus: confirmationStatus,
      semanticPlanValidated: semanticPlanValidated,
      identityValidated: identityValidated,
      issuedByExecutorOnly: issuedByExecutorOnly,
    );
  }

  PdvV1SimulatedTransitionAuthorization copyWithStateBefore(
    PdvV1JournalState state,
  ) {
    return PdvV1SimulatedTransitionAuthorization(
      authorizationVersion: authorizationVersion,
      planFingerprint: planFingerprint,
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      origem: origem,
      protocolVersion: protocolVersion,
      snapshotHash: snapshotHash,
      txItemsHash: txItemsHash,
      journalRevisionAtAuthorization: journalRevisionAtAuthorization,
      stateBefore: state,
      stateAfter: stateAfter,
      planTargetState: planTargetState,
      authorizationKind: authorizationKind,
      confirmationStage: confirmationStage,
      confirmationStatus: confirmationStatus,
      semanticPlanValidated: semanticPlanValidated,
      identityValidated: identityValidated,
      issuedByExecutorOnly: issuedByExecutorOnly,
    );
  }

  PdvV1SimulatedTransitionAuthorization copyWithPlanTargetState(
    PdvV1JournalState target,
  ) {
    return PdvV1SimulatedTransitionAuthorization(
      authorizationVersion: authorizationVersion,
      planFingerprint: planFingerprint,
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      origem: origem,
      protocolVersion: protocolVersion,
      snapshotHash: snapshotHash,
      txItemsHash: txItemsHash,
      journalRevisionAtAuthorization: journalRevisionAtAuthorization,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      planTargetState: target,
      authorizationKind: authorizationKind,
      confirmationStage: confirmationStage,
      confirmationStatus: confirmationStatus,
      semanticPlanValidated: semanticPlanValidated,
      identityValidated: identityValidated,
      issuedByExecutorOnly: issuedByExecutorOnly,
    );
  }
}

extension on PdvV1RecoveryPlan {
  PdvV1RecoveryPlan copyWith({
    String? idempotencyKey,
    int? journalRevisionAtPlan,
  }) {
    return PdvV1RecoveryPlan(
      decision: decision,
      currentState: currentState,
      targetState: targetState,
      plannedActions: plannedActions,
      reasonCode: reasonCode,
      operationId: operationId,
      saleId: saleId,
      journalRevisionAtPlan:
          journalRevisionAtPlan ?? this.journalRevisionAtPlan,
      journalIdentity: journalIdentity,
      requiresExternalIntegration: requiresExternalIntegration,
      isManualIntervention: isManualIntervention,
      isDeferred: isDeferred,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}
