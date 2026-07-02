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
    operationId: 'op-stage-1',
    saleId: 'sale-stage-1',
    lojaId: 'loja-stage-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-stage-1',
    txItemsHash: 'tx-stage-1',
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

PdvV1SimulatedStageStartRequest _stageStart({
  required PdvV1RecoveryPlanFingerprint fp,
  required PdvV1SimulatedConfirmationStage stage,
  required int revision,
  required PdvV1JournalState stateBefore,
  required PdvV1JournalState target,
}) {
  return PdvV1SimulatedStageStartRequest(
    planFingerprint: fp,
    operationId: 'op-stage-1',
    saleId: 'sale-stage-1',
    lojaId: 'loja-stage-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-stage-1',
    txItemsHash: 'tx-stage-1',
    expectedJournalRevision: revision,
    expectedStateBefore: stateBefore,
    expectedTargetState: target,
    stageToStart: stage,
    requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
    semanticPlanValidated: true,
    identityValidated: true,
  );
}

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();
  const executor = PdvV1RecoveryExecutorSimulator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('PdvV1SimulatedStageStartRequest', () {
    test('stage start saleSync válido: hiveSaleCompleted → saleSyncPending',
        () {
      final record = _journal(PdvV1JournalState.hiveSaleCompleted, revision: 3);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          stageStartRequest: _stageStart(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            revision: 3,
            stateBefore: PdvV1JournalState.hiveSaleCompleted,
            target: PdvV1JournalState.saleSyncPending,
          ),
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.saleSyncPending);
      expect(store.snapshot.journalRevision, 4);
      expect(
        run.executionOutcome!.transitionAuthorization!.authorizationKind,
        PdvV1SimulatedTransitionAuthorizationKind.stageStartSaleSyncTransition,
      );
    });

    test('stage start effects válido: saleSyncCompleted → effectsPending', () {
      final record = _journal(PdvV1JournalState.saleSyncCompleted, revision: 5);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          stageStartRequest: _stageStart(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            revision: 5,
            stateBefore: PdvV1JournalState.saleSyncCompleted,
            target: PdvV1JournalState.effectsPending,
          ),
        ),
      );
      expect(run.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.effectsPending);
      expect(store.snapshot.journalRevision, 6);
    });

    test('stage start saleSync antes de hiveSaleCompleted é recusado', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          stageStartRequest: _stageStart(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            revision: 0,
            stateBefore: PdvV1JournalState.hiveSaleCompleted,
            target: PdvV1JournalState.saleSyncPending,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'stage_start_state_before_mismatch');
    });

    test('stage start effects antes de saleSyncCompleted é recusado', () {
      final record = _journal(PdvV1JournalState.saleSyncPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          stageStartRequest: _stageStart(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            revision: 0,
            stateBefore: PdvV1JournalState.saleSyncCompleted,
            target: PdvV1JournalState.effectsPending,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'stage_start_state_before_mismatch');
    });

    test('stage start stale não altera store', () {
      final record = _journal(PdvV1JournalState.hiveSaleCompleted, revision: 2);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final before = store.snapshot.toJson();
      coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          stageStartRequest: _stageStart(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            revision: 0,
            stateBefore: PdvV1JournalState.hiveSaleCompleted,
            target: PdvV1JournalState.saleSyncPending,
          ),
        ),
      );
      expect(store.snapshot.toJson(), before);
    });

    test('dois stage start concorrentes: primeiro aceito, segundo stale', () {
      final record = _journal(PdvV1JournalState.hiveSaleCompleted, revision: 1);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
      final request = _stageStart(
        fp: fp,
        stage: PdvV1SimulatedConfirmationStage.saleSync,
        revision: 1,
        stateBefore: PdvV1JournalState.hiveSaleCompleted,
        target: PdvV1JournalState.saleSyncPending,
      );
      final first = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          stageStartRequest: request,
        ),
      );
      expect(first.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.journalRevision, 2);

      final second = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
          stageStartRequest: request,
        ),
      );
      expect(second.casApplyOutcome, isNull);
      expect(second.manualInterventionRequired, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.saleSyncPending);
      expect(store.snapshot.journalRevision, 2);
    });
  });
}
