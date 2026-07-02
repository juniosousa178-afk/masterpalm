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
    operationId: 'op-cas-1',
    saleId: 'sale-cas-1',
    lojaId: 'loja-cas-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-cas-1',
    txItemsHash: 'tx-cas-1',
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
    requestedOperationId: 'op-cas-1',
    requestedSaleId: 'sale-cas-1',
    requestedLojaId: 'loja-cas-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-cas-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-cas-1',
      operationId: 'op-cas-1',
      saleId: 'sale-cas-1',
      baixaAplicada: true,
      txItemsHash: 'tx-cas-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

void main() {
  const executor = PdvV1RecoveryExecutorSimulator();
  final orchestrator = PdvV1RecoveryOrchestrator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('PdvV1RecoverySimulatedCasStore', () {
    test('CAS aceita plano compatível com revision atual', () {
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
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isTrue);
      expect(outcome.stateAfter, PdvV1JournalState.remoteStockApplied);
      expect(store.snapshot.journalRevision, 1);
    });

    test('CAS incrementa revision em transição real', () {
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
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.revisionBefore, 0);
      expect(outcome.revisionAfter, 1);
    });

    test('CAS mantém revision em deferimento', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final unavailable = PdvV1RemoteVerificationEvidence(
        requestedOperationId: 'op-cas-1',
        requestedSaleId: 'sale-cas-1',
        requestedLojaId: 'loja-cas-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-cas-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
        optionalMarker: const PdvV1RemoteMarkerInput.ausente(),
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: unavailable,
        ),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
        evidence: unavailable,
      );
      final execution = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          context: PdvV1RecoveryExecutorContext(evidence: unavailable),
        ),
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isTrue);
      expect(outcome.revisionAfter, 0);
      expect(outcome.stateAfter, PdvV1JournalState.remoteStockPending);
    });

    test('CAS rejeita revision antiga sem alterar store', () {
      final record = _journal(
        PdvV1JournalState.remoteStockApplied,
        revision: 2,
      );
      final store = PdvV1RecoverySimulatedCasStore(record);
      final stalePlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.remoteStockApplied,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture,
        ],
        reasonCode: 'stale',
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(record.prepared),
        idempotencyKey: 'stale',
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: stalePlan,
        prep: record.prepared,
      );
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        stateBefore: PdvV1JournalState.remoteStockPending,
        proposedStateAfter: PdvV1JournalState.remoteStockApplied,
        proposedActions: stalePlan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'stale',
        idempotencyDiagnosticKey: 'stale',
      );
      final before = store.snapshot.toJson();
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: stalePlan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.stalePlanRejected, isTrue);
      expect(outcome.rejectionReasonCode, 'stale_plan_revision');
      expect(store.snapshot.toJson(), before);
    });

    test('dois planos da revision 0: primeiro avança, segundo rejeitado', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final evidence = _evidence();
      final planA = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: evidence,
        ),
      );
      final planB = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: evidence,
        ),
      );
      expect(planA.journalRevisionAtPlan, 0);
      expect(planB.journalRevisionAtPlan, 0);

      final runA = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: evidence,
        ),
      );
      expect(runA.casApplyOutcome!.accepted, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.remoteStockApplied);
      expect(store.snapshot.journalRevision, 1);

      final fpB = pdvV1BuildRecoveryPlanFingerprint(
        plan: planB,
        prep: record.prepared,
        evidence: evidence,
      );
      final execB = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
          plan: planB,
          context: PdvV1RecoveryExecutorContext(evidence: evidence),
        ),
      );
      expect(execB.isManualIntervention, isTrue);
      expect(execB.reasonCode, 'plan_journal_mismatch');

      final casB = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: planB,
        planFingerprint: fpB,
        proposedExecutionOutcome: execB,
        semanticPlanValidated: true,
      );
      expect(casB.accepted, isFalse);
      expect(store.snapshot.state, PdvV1JournalState.remoteStockApplied);
      expect(store.snapshot.journalRevision, 1);
    });

    test('dois planos com mesma revisão e targetStates diferentes', () {
      final record = _journal(PdvV1JournalState.remoteStockApplied);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final insertPlan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          hiveMatches: const [],
        ),
      );
      final reusePlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.reuseExistingHiveSale,
        currentState: PdvV1JournalState.remoteStockApplied,
        targetState: PdvV1JournalState.hiveSaleCompleted,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.planReuseHiveSaleFuture,
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ],
        reasonCode: 'hive_reuse_existing',
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(record.prepared),
        requiresExternalIntegration: true,
        idempotencyKey: 'reuse',
      );
      expect(insertPlan.targetState, PdvV1JournalState.hiveSalePending);
      expect(reusePlan.targetState, PdvV1JournalState.hiveSaleCompleted);

      final fpInsert = pdvV1BuildRecoveryPlanFingerprint(
        plan: insertPlan,
        prep: record.prepared,
      );
      final execInsert = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: insertPlan,
        ),
      );
      store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: insertPlan,
        planFingerprint: fpInsert,
        proposedExecutionOutcome: execInsert,
        semanticPlanValidated: true,
      );
      expect(store.snapshot.state, PdvV1JournalState.hiveSalePending);

      final fpReuse = pdvV1BuildRecoveryPlanFingerprint(
        plan: reusePlan,
        prep: record.prepared,
      );
      final execReuse = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
          plan: reusePlan,
        ),
      );
      final casReuse = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: reusePlan,
        planFingerprint: fpReuse,
        proposedExecutionOutcome: execReuse,
        semanticPlanValidated: true,
      );
      expect(casReuse.accepted, isFalse);
      expect(store.snapshot.state, PdvV1JournalState.hiveSalePending);
    });

    test('journal terminal recebendo plano antigo não altera store', () {
      final record =
          _journal(PdvV1JournalState.operationCompleted, revision: 5);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final stalePlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.remoteStockApplied,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture,
        ],
        reasonCode: 'old',
        operationId: 'op-cas-1',
        saleId: 'sale-cas-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(record.prepared),
        idempotencyKey: 'old',
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: stalePlan,
        prep: record.prepared,
      );
      final execution = PdvV1SimulatedExecutionOutcome(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        stateBefore: PdvV1JournalState.remoteStockPending,
        proposedStateAfter: PdvV1JournalState.remoteStockApplied,
        proposedActions: stalePlan.plannedActions,
        planFingerprint: fp,
        proposedJournalRevision: 1,
        reasonCode: 'old',
        idempotencyDiagnosticKey: 'old',
      );
      final outcome = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: stalePlan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(outcome.accepted, isFalse);
      expect(store.snapshot.state, PdvV1JournalState.operationCompleted);
      expect(store.snapshot.journalRevision, 5);
    });
  });
}
