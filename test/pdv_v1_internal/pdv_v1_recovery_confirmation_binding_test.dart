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
    operationId: 'op-conf-1',
    saleId: 'sale-conf-1',
    lojaId: 'loja-conf-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-conf-1',
    txItemsHash: 'tx-conf-1',
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

PdvV1RecoveryPlan _integrationPlan(PdvV1JournalRecord record) {
  return PdvV1RecoveryPlan(
    decision: PdvV1RecoveryDecision.requireExternalIntegration,
    currentState: record.state,
    targetState: record.state,
    plannedActions: const [PdvV1RecoveryPlannedAction.awaitExternalIntegration],
    reasonCode: 'state_requires_integration',
    operationId: 'op-conf-1',
    saleId: 'sale-conf-1',
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
  PdvV1SimulatedConfirmationStatus status =
      PdvV1SimulatedConfirmationStatus.confirmedCompatible,
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
    operationId: 'op-conf-1',
    saleId: 'sale-conf-1',
    lojaId: 'loja-conf-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-conf-1',
    txItemsHash: 'tx-conf-1',
    expectedStateBefore: stateBefore,
    expectedTargetState: targetState,
    stage: stage,
    status: status,
    requiredEffectsKeys: requiredEffectsKeys,
    completedEffectsKeys: completedEffectsKeys,
  );
}

void main() {
  const executor = PdvV1RecoveryExecutorSimulator();
  final orchestrator = PdvV1RecoveryOrchestrator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('Confirmação vinculada a stage e estado', () {
    test('confirmação Hive correta em hiveSalePending avança em memória', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
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
      expect(run.semanticValidation.valid, isTrue);
      expect(run.executionOutcome, isNotNull);
      expect(run.executionOutcome!.isManualIntervention, isFalse,
          reason: run.executionOutcome!.reasonCode);
      expect(run.casApplyOutcome, isNotNull);
      expect(run.casApplyOutcome!.accepted, isTrue,
          reason: run.casApplyOutcome!.rejectionReasonCode);
      expect(store.snapshot.state, PdvV1JournalState.hiveSaleCompleted);
    });

    test('confirmação Hive em saleSyncPending gera manual', () {
      final record = _journal(PdvV1JournalState.saleSyncPending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
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
      expect(outcome.reasonCode, 'hive_confirmation_on_sale_sync_pending');
    });

    test('confirmação saleSync em hiveSalePending gera manual', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
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
      expect(outcome.reasonCode, 'sale_sync_confirmation_on_hive_pending');
    });

    test('confirmação com targetState divergente gera manual', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            expectedTargetState: PdvV1JournalState.saleSyncCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'confirmation_target_state_divergent');
    });

    test('confirmação effects sem todos efeitos mantém pending', () {
      final record = _journal(PdvV1JournalState.effectsPending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            completedEffectsKeys: const ['a'],
          ),
          context: const PdvV1RecoveryExecutorContext(
            requiredEffectsKeys: ['a', 'b'],
          ),
        ),
      );
      expect(outcome.proposedStateAfter, PdvV1JournalState.effectsPending);
      expect(outcome.isDeferred, isTrue);
    });

    test('operationCompletion fora de effectsCompleted gera manual', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.operationCompletion,
            expectedStateBefore: PdvV1JournalState.effectsCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
    });

    test('confirmação stale não altera store', () {
      final record = _journal(PdvV1JournalState.hiveSalePending, revision: 2);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
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

    test('confirmação tardia de saleSync com revision antiga', () {
      final record = _journal(PdvV1JournalState.saleSyncPending, revision: 3);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            expectedJournalRevision: 1,
          ),
        ),
      );
      expect(outcome.reasonCode, 'stale_confirmation_revision');
    });
  });
}
