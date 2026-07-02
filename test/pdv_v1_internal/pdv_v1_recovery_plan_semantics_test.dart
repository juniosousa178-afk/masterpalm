import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_plan_semantics.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-sem-1',
    saleId: 'sale-sem-1',
    lojaId: 'loja-sem-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-sem-1',
    txItemsHash: 'tx-sem-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _journal(PdvV1JournalState state) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

PdvV1RemoteVerificationEvidence _evidence({
  PdvV1RemoteVerificationStatus status =
      PdvV1RemoteVerificationStatus.markerAppliedCompatible,
}) {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: 'op-sem-1',
    requestedSaleId: 'sale-sem-1',
    requestedLojaId: 'loja-sem-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-sem-1',
    verificationStatus: status,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-sem-1',
      operationId: 'op-sem-1',
      saleId: 'sale-sem-1',
      baixaAplicada: true,
      txItemsHash: 'tx-sem-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

void main() {
  const validator = PdvV1RecoveryPlanSemanticsValidator();
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('PdvV1RecoveryPlanSemanticsValidator', () {
    test('semântica rejeita Hive insert antes de remoteStockApplied', () {
      final bad = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.insertHiveSaleOnce,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.hiveSalePending,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ],
        reasonCode: 'bad',
        operationId: 'op-sem-1',
        saleId: 'sale-sem-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(_prep()),
        requiresExternalIntegration: true,
        idempotencyKey: 'bad',
      );
      final result = validator.validate(bad);
      expect(result.valid, isFalse);
      expect(result.violations,
          contains('insert_hive_before_remote_stock_applied'));
    });

    test('semântica rejeita operationCompleted antes de effectsCompleted', () {
      final bad = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.requireExternalIntegration,
        currentState: PdvV1JournalState.hiveSalePending,
        targetState: PdvV1JournalState.operationCompleted,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.awaitExternalIntegration
        ],
        reasonCode: 'bad',
        operationId: 'op-sem-1',
        saleId: 'sale-sem-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(_prep()),
        requiresExternalIntegration: true,
        idempotencyKey: 'bad',
      );
      final result = validator.validate(bad);
      expect(result.valid, isFalse);
      expect(
        result.violations,
        contains('operation_completed_before_effects_completed'),
      );
    });

    test('semântica rejeita action extra', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      final tampered = PdvV1RecoveryPlan(
        decision: plan.decision,
        currentState: plan.currentState,
        targetState: plan.targetState,
        plannedActions: [
          ...plan.plannedActions,
          PdvV1RecoveryPlannedAction.verifyMarkerAgain,
        ],
        reasonCode: plan.reasonCode,
        operationId: plan.operationId,
        saleId: plan.saleId,
        journalRevisionAtPlan: plan.journalRevisionAtPlan,
        journalIdentity: plan.journalIdentity,
        idempotencyKey: plan.idempotencyKey,
      );
      final result = validator.validate(tampered);
      expect(result.valid, isFalse);
      expect(
          result.violations, contains('continue_hive_upsert_actions_invalid'));
    });

    test('semântica rejeita ordem alterada', () {
      final bad = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.replanRemoteStockTransaction,
        currentState: PdvV1JournalState.prepared,
        targetState: PdvV1JournalState.prepared,
        plannedActions: const [
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
        ],
        reasonCode: 'bad',
        operationId: 'op-sem-1',
        saleId: 'sale-sem-1',
        journalRevisionAtPlan: 0,
        journalIdentity: pdvV1BuildJournalIdentity(_prep()),
        requiresExternalIntegration: true,
        idempotencyKey: 'bad',
      );
      final result = validator.validate(bad);
      expect(result.valid, isFalse);
      expect(result.violations, contains('replan_prepared_actions_invalid'));
    });

    test('semântica aceita continueWithHiveUpsert oficial', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      expect(validator.validate(plan).valid, isTrue);
    });

    test('semântica aceita deferUntilVerification oficial', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: PdvV1RemoteVerificationEvidence(
            requestedOperationId: 'op-sem-1',
            requestedSaleId: 'sale-sem-1',
            requestedLojaId: 'loja-sem-1',
            requestedOrigin: pdvV1OrigemProtocolValue,
            requestedProtocolVersion: pdvV1ProtocolVersion,
            requestedTxItemsHash: 'tx-sem-1',
            verificationStatus:
                PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
            optionalMarker: const PdvV1RemoteMarkerInput.ausente(),
            verificationSource: 'synthetic',
            verifiedAtEpochMs: 2,
          ),
        ),
      );
      expect(validator.validate(plan).valid, isTrue);
    });

    test('semântica rejeita duplicata', () {
      expect(
        () => PdvV1RecoveryPlan(
          decision: PdvV1RecoveryDecision.deferUntilVerification,
          currentState: PdvV1JournalState.remoteStockPending,
          targetState: PdvV1JournalState.remoteStockPending,
          plannedActions: const [
            PdvV1RecoveryPlannedAction.verifyMarkerAgain,
            PdvV1RecoveryPlannedAction.verifyMarkerAgain,
          ],
          reasonCode: 'dup',
          operationId: 'op-sem-1',
          saleId: 'sale-sem-1',
          journalRevisionAtPlan: 0,
          journalIdentity: pdvV1BuildJournalIdentity(_prep()),
          idempotencyKey: 'dup',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('duas gerações do mesmo planner preservam ordem e validação', () {
      final record = _journal(PdvV1JournalState.remoteStockApplied);
      final input = PdvV1RecoveryOrchestratorInput(
        journalOutcome: PdvV1JournalReadOutcome(record: record),
        evidence: _evidence(),
        hiveMatches: const [],
      );
      final plan1 = orchestrator.plan(input);
      final plan2 = orchestrator.plan(input);
      expect(plan1.plannedActions, plan2.plannedActions);
      expect(validator.validate(plan1).valid, isTrue);
      expect(validator.validate(plan2).valid, isTrue);
    });
  });
}
