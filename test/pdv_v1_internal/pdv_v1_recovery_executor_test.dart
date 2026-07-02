import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-ex-1',
    saleId: 'sale-ex-1',
    lojaId: 'loja-ex-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-ex-1',
    txItemsHash: 'tx-ex-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _journal(PdvV1JournalState state,
    {int journalRevision = 0}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: journalRevision,
  );
}

PdvV1RemoteVerificationEvidence _evidence({
  PdvV1RemoteVerificationStatus status =
      PdvV1RemoteVerificationStatus.markerAppliedCompatible,
}) {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: 'op-ex-1',
    requestedSaleId: 'sale-ex-1',
    requestedLojaId: 'loja-ex-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-ex-1',
    verificationStatus: status,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-ex-1',
      operationId: 'op-ex-1',
      saleId: 'sale-ex-1',
      baixaAplicada: true,
      txItemsHash: 'tx-ex-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

PdvV1SimulatedStageConfirmation _confirmation({
  required PdvV1RecoveryPlanFingerprint fp,
  required PdvV1SimulatedConfirmationStage stage,
  PdvV1SimulatedConfirmationStatus status =
      PdvV1SimulatedConfirmationStatus.confirmedCompatible,
  List<String> requiredEffectsKeys = const [],
  List<String> completedEffectsKeys = const [],
  int expectedJournalRevision = 0,
  PdvV1JournalState? expectedStateBefore,
  PdvV1JournalState? expectedTargetState,
}) {
  PdvV1JournalState stateBefore;
  PdvV1JournalState targetState;
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
    operationId: 'op-ex-1',
    saleId: 'sale-ex-1',
    lojaId: 'loja-ex-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-ex-1',
    txItemsHash: 'tx-ex-1',
    expectedStateBefore: stateBefore,
    expectedTargetState: targetState,
    stage: stage,
    status: status,
    requiredEffectsKeys: requiredEffectsKeys,
    completedEffectsKeys: completedEffectsKeys,
  );
}

PdvV1RecoveryPlan _integrationPlan(PdvV1JournalRecord record) {
  return PdvV1RecoveryPlan(
    decision: PdvV1RecoveryDecision.requireExternalIntegration,
    currentState: record.state,
    targetState: record.state,
    plannedActions: const [PdvV1RecoveryPlannedAction.awaitExternalIntegration],
    reasonCode: 'state_requires_integration',
    operationId: 'op-ex-1',
    saleId: 'sale-ex-1',
    journalRevisionAtPlan: record.journalRevision,
    journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
    requiresExternalIntegration: true,
    idempotencyKey: 'integration-${record.state}',
  );
}

void main() {
  const executor = PdvV1RecoveryExecutorSimulator();
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('PdvV1RecoveryExecutorSimulator', () {
    test('executor não aceita plano inválido', () {
      final record = _journal(PdvV1JournalState.prepared);
      final badPlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.continueWithHiveUpsert,
        currentState: PdvV1JournalState.remoteStockPending,
        targetState: PdvV1JournalState.remoteStockApplied,
        plannedActions: const [],
        reasonCode: 'mismatch',
        operationId: 'OUTRO',
        saleId: 'sale-ex-1',
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        idempotencyKey: 'bad',
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: badPlan,
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'plan_journal_mismatch');
    });

    test('executor não muta Journal recebido', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final before = record.toJson();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(
            status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
          ),
        ),
      );
      executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          context: PdvV1RecoveryExecutorContext(evidence: _evidence()),
        ),
      );
      expect(record.toJson(), before);
    });

    test('executor não executa callback ou I/O', () {
      final dir = Directory('lib/services/pdv_v1_internal');
      final content = dir
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('pdv_v1_recovery_executor.dart'))
          .readAsStringSync();
      expect(content.contains('Firebase'), isFalse);
      expect(content.contains('Hive.openBox'), isFalse);
      expect(content.contains('void Function'), isFalse);
      expect(content.contains('Future<void> Function'), isFalse);
    });

    test('hiveSalePending avança apenas com confirmação compatível', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final without = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
        ),
      );
      expect(without.proposedStateAfter, PdvV1JournalState.hiveSalePending);

      final withConfirm = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          ),
        ),
      );
      expect(
          withConfirm.proposedStateAfter, PdvV1JournalState.hiveSaleCompleted);
      expect(withConfirm.confirmationValidated, isTrue);
    });

    test('saleSyncPending avança apenas com confirmação saleSync compatível',
        () {
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
            stage: PdvV1SimulatedConfirmationStage.saleSync,
          ),
        ),
      );
      expect(outcome.proposedStateAfter, PdvV1JournalState.saleSyncCompleted);
    });

    test('effectsPending exige todos efeitos obrigatórios concluídos', () {
      final record = _journal(PdvV1JournalState.effectsPending);
      final plan = _integrationPlan(record);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: record.prepared,
      );
      final partial = executor.simulate(
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
      expect(partial.proposedStateAfter, PdvV1JournalState.effectsPending);
      expect(partial.isDeferred, isTrue);

      final complete = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            completedEffectsKeys: const ['a', 'b'],
          ),
          context: const PdvV1RecoveryExecutorContext(
            requiredEffectsKeys: ['a', 'b'],
          ),
        ),
      );
      expect(complete.proposedStateAfter, PdvV1JournalState.effectsCompleted);
    });

    test('effectsCompleted exige confirmação operationCompletion', () {
      final record = _journal(PdvV1JournalState.effectsCompleted);
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
            completedEffectsKeys: const ['fx'],
          ),
          context: const PdvV1RecoveryExecutorContext(
            requiredEffectsKeys: ['fx'],
          ),
        ),
      );
      expect(outcome.proposedStateAfter, PdvV1JournalState.operationCompleted);
    });

    test('markerVerificationUnavailable permanece inerte via defer', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final unavailableEvidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: 'op-ex-1',
        requestedSaleId: 'sale-ex-1',
        requestedLojaId: 'loja-ex-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-ex-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
        optionalMarker: const PdvV1RemoteMarkerInput.ausente(),
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: unavailableEvidence,
        ),
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          context: PdvV1RecoveryExecutorContext(evidence: unavailableEvidence),
        ),
      );
      expect(outcome.isDeferred, isTrue);
      expect(outcome.proposedStateAfter, PdvV1JournalState.remoteStockPending);
    });

    test('estado manual é terminal', () {
      final record = _journal(PdvV1JournalState.manualInterventionRequired);
      final plan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.noAction,
        currentState: PdvV1JournalState.manualInterventionRequired,
        targetState: PdvV1JournalState.manualInterventionRequired,
        plannedActions: const [],
        reasonCode: 'terminal_state',
        operationId: 'op-ex-1',
        saleId: 'sale-ex-1',
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        idempotencyKey: 'manual',
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
        ),
      );
      expect(outcome.decision, PdvV1RecoveryDecision.noAction);
      expect(outcome.proposedStateAfter,
          PdvV1JournalState.manualInterventionRequired);
    });

    test('estado operationCompleted é terminal', () {
      final record = _journal(PdvV1JournalState.operationCompleted);
      final plan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.noAction,
        currentState: PdvV1JournalState.operationCompleted,
        targetState: PdvV1JournalState.operationCompleted,
        plannedActions: const [],
        reasonCode: 'terminal_state',
        operationId: 'op-ex-1',
        saleId: 'sale-ex-1',
        journalRevisionAtPlan: record.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
        idempotencyKey: 'done',
      );
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
        ),
      );
      expect(outcome.decision, PdvV1RecoveryDecision.noAction);
      expect(outcome.proposedStateAfter, PdvV1JournalState.operationCompleted);
    });

    test('três execuções iguais retornam JSON idêntico', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(
            status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
          ),
        ),
      );
      final input = PdvV1RecoveryExecutorInput(
        journalOutcome: PdvV1JournalReadOutcome(record: record),
        plan: plan,
        context: PdvV1RecoveryExecutorContext(evidence: _evidence()),
      );
      final j1 = jsonEncode(executor.simulate(input).toJson());
      final j2 = jsonEncode(executor.simulate(input).toJson());
      final j3 = jsonEncode(executor.simulate(input).toJson());
      expect(j1, j2);
      expect(j2, j3);
    });

    test('plano com revisão antiga vai para manual', () {
      final record =
          _journal(PdvV1JournalState.hiveSalePending, journalRevision: 2);
      final stalePlan =
          _integrationPlan(_journal(PdvV1JournalState.hiveSalePending));
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: stalePlan,
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'stale_plan_revision');
    });

    test('confirmação com revisão antiga vai para manual', () {
      final record =
          _journal(PdvV1JournalState.hiveSalePending, journalRevision: 1);
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
            expectedJournalRevision: 0,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'stale_confirmation_revision');
    });

    test('confirmação válida propõe revisão atual + 1 quando há transição', () {
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
          ),
        ),
      );
      expect(outcome.proposedJournalRevision, 1);
      expect(outcome.proposedStateAfter, PdvV1JournalState.hiveSaleCompleted);
    });

    test('nenhum arquivo externo referencia executor ou confirmação tipada',
        () async {
      final tokens = [
        'PdvV1RecoveryExecutorSimulator',
        'PdvV1SimulatedStageConfirmation',
        'PdvV1RecoveryPlanFingerprint',
      ];
      final hits = <String>[];
      final roots = [Directory('lib/screens'), Directory('lib/services')];
      for (final root in roots) {
        if (!await root.exists()) continue;
        await for (final entity in root.list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('pdv_v1_internal')) continue;
          final content = await entity.readAsString();
          for (final token in tokens) {
            if (content.contains(token)) hits.add('${entity.path}:$token');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });
  });
}
