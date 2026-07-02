import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_plan_semantics.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

const _requiredEffects = ['product_cache_refresh', 'catalog_projection'];

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-chain-1',
    saleId: 'sale-chain-1',
    lojaId: 'loja-chain-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-chain-1',
    txItemsHash: 'tx-chain-1',
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
    requestedOperationId: 'op-chain-1',
    requestedSaleId: 'sale-chain-1',
    requestedLojaId: 'loja-chain-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-chain-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-chain-1',
      operationId: 'op-chain-1',
      saleId: 'sale-chain-1',
      baixaAplicada: true,
      txItemsHash: 'tx-chain-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

PdvV1SimulatedStageConfirmation _confirmation({
  required PdvV1RecoveryPlanFingerprint fp,
  required PdvV1SimulatedConfirmationStage stage,
  required int revision,
  required PdvV1JournalState stateBefore,
  required PdvV1JournalState target,
  List<String> requiredEffectsKeys = const [],
  List<String> completedEffectsKeys = const [],
}) {
  return PdvV1SimulatedStageConfirmation(
    planFingerprint: fp,
    expectedJournalRevision: revision,
    operationId: 'op-chain-1',
    saleId: 'sale-chain-1',
    lojaId: 'loja-chain-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-chain-1',
    txItemsHash: 'tx-chain-1',
    expectedStateBefore: stateBefore,
    expectedTargetState: target,
    stage: stage,
    status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
    requiredEffectsKeys: requiredEffectsKeys,
    completedEffectsKeys: completedEffectsKeys,
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
    operationId: 'op-chain-1',
    saleId: 'sale-chain-1',
    lojaId: 'loja-chain-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-chain-1',
    txItemsHash: 'tx-chain-1',
    expectedJournalRevision: revision,
    expectedStateBefore: stateBefore,
    expectedTargetState: target,
    stageToStart: stage,
    requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
    semanticPlanValidated: true,
    identityValidated: true,
  );
}

PdvV1RecoverySimulationRunOutcome _runStep({
  required PdvV1RecoverySimulationCoordinator coordinator,
  required PdvV1RecoverySimulatedCasStore store,
  PdvV1RemoteVerificationEvidence? evidence,
  PdvV1SimulatedStageConfirmation? confirmation,
  PdvV1SimulatedStageStartRequest? stageStartRequest,
  List<String> requiredEffectsKeys = const [],
}) {
  return coordinator.run(
    PdvV1RecoverySimulationInput(
      store: store,
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
      evidence: evidence,
      confirmation: confirmation,
      stageStartRequest: stageStartRequest,
      requiredEffectsKeys: requiredEffectsKeys,
    ),
  );
}

Map<String, dynamic> _runFullChain(
    PdvV1RecoverySimulationCoordinator coordinator) {
  final store = PdvV1RecoverySimulatedCasStore(
    _journal(PdvV1JournalState.remoteStockPending),
  );
  final orchestrator = PdvV1RecoveryOrchestrator();
  final steps = <Map<String, dynamic>>[];

  void record(PdvV1RecoverySimulationRunOutcome run) {
    steps.add(run.toJson());
  }

  record(_runStep(
    coordinator: coordinator,
    store: store,
    evidence: _evidence(),
  ));
  expect(store.snapshot.state, PdvV1JournalState.remoteStockApplied);
  expect(store.snapshot.journalRevision, 1);

  record(_runStep(coordinator: coordinator, store: store));
  expect(store.snapshot.state, PdvV1JournalState.hiveSalePending);
  expect(store.snapshot.journalRevision, 2);

  final plan3 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp3 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan3,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    confirmation: _confirmation(
      fp: fp3,
      stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      revision: 2,
      stateBefore: PdvV1JournalState.hiveSalePending,
      target: PdvV1JournalState.hiveSaleCompleted,
    ),
  ));
  expect(store.snapshot.state, PdvV1JournalState.hiveSaleCompleted);
  expect(store.snapshot.journalRevision, 3);

  final plan4 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp4 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan4,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    stageStartRequest: _stageStart(
      fp: fp4,
      stage: PdvV1SimulatedConfirmationStage.saleSync,
      revision: 3,
      stateBefore: PdvV1JournalState.hiveSaleCompleted,
      target: PdvV1JournalState.saleSyncPending,
    ),
  ));
  expect(store.snapshot.state, PdvV1JournalState.saleSyncPending);
  expect(store.snapshot.journalRevision, 4);

  final plan5 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp5 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan5,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    confirmation: _confirmation(
      fp: fp5,
      stage: PdvV1SimulatedConfirmationStage.saleSync,
      revision: 4,
      stateBefore: PdvV1JournalState.saleSyncPending,
      target: PdvV1JournalState.saleSyncCompleted,
    ),
  ));
  expect(store.snapshot.state, PdvV1JournalState.saleSyncCompleted);
  expect(store.snapshot.journalRevision, 5);

  final plan6 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp6 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan6,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    stageStartRequest: _stageStart(
      fp: fp6,
      stage: PdvV1SimulatedConfirmationStage.effects,
      revision: 5,
      stateBefore: PdvV1JournalState.saleSyncCompleted,
      target: PdvV1JournalState.effectsPending,
    ),
  ));
  expect(store.snapshot.state, PdvV1JournalState.effectsPending);
  expect(store.snapshot.journalRevision, 6);

  final plan7 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp7 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan7,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    confirmation: _confirmation(
      fp: fp7,
      stage: PdvV1SimulatedConfirmationStage.effects,
      revision: 6,
      stateBefore: PdvV1JournalState.effectsPending,
      target: PdvV1JournalState.effectsCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  ));
  expect(store.snapshot.state, PdvV1JournalState.effectsCompleted);
  expect(store.snapshot.journalRevision, 7);

  final plan8 = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: store.snapshot),
    ),
  );
  final fp8 = pdvV1BuildRecoveryPlanFingerprint(
    plan: plan8,
    prep: store.snapshot.prepared,
  );
  record(_runStep(
    coordinator: coordinator,
    store: store,
    confirmation: _confirmation(
      fp: fp8,
      stage: PdvV1SimulatedConfirmationStage.operationCompletion,
      revision: 7,
      stateBefore: PdvV1JournalState.effectsCompleted,
      target: PdvV1JournalState.operationCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  ));
  expect(store.snapshot.state, PdvV1JournalState.operationCompleted);
  expect(store.snapshot.journalRevision, 8);

  return {
    'finalJournal': store.snapshot.toJson(),
    'steps': steps,
    'externalIntegrationNeverExecuted': true,
  };
}

void main() {
  final coordinator = PdvV1RecoverySimulationCoordinator();
  const executor = PdvV1RecoveryExecutorSimulator();
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('Cadeia multi-step simulada', () {
    test('cadeia completa revision 0 até 8', () {
      final result = _runFullChain(coordinator);
      expect(result['finalJournal']['state'], 'operationCompleted');
      expect(result['finalJournal']['journalRevision'], 8);
      final steps = result['steps'] as List;
      expect(steps.length, 8);
    });

    test('cada revision incrementada exatamente uma vez', () {
      final store = PdvV1RecoverySimulatedCasStore(
        _journal(PdvV1JournalState.remoteStockPending),
      );
      _runStep(coordinator: coordinator, store: store, evidence: _evidence());
      expect(store.snapshot.journalRevision, 1);
      _runStep(coordinator: coordinator, store: store);
      expect(store.snapshot.journalRevision, 2);
    });

    test('três cadeias idênticas produzem JSON idêntico', () {
      final runs = List.generate(3, (_) {
        return jsonEncode(_runFullChain(coordinator));
      });
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });

    test('confirmação Hive em saleSyncPending gera manual', () {
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
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            revision: 0,
            stateBefore: PdvV1JournalState.saleSyncPending,
            target: PdvV1JournalState.hiveSaleCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'hive_confirmation_on_sale_sync_pending');
    });

    test('confirmação saleSync em hiveSalePending gera manual', () {
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
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            revision: 0,
            stateBefore: PdvV1JournalState.hiveSalePending,
            target: PdvV1JournalState.saleSyncCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.reasonCode, 'sale_sync_confirmation_on_hive_pending');
    });

    test('effects incompletos mantém effectsPending sem incremento', () {
      final record = _journal(PdvV1JournalState.effectsPending, revision: 6);
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
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.effects,
            revision: 6,
            stateBefore: PdvV1JournalState.effectsPending,
            target: PdvV1JournalState.effectsCompleted,
            requiredEffectsKeys: _requiredEffects,
            completedEffectsKeys: const ['product_cache_refresh'],
          ),
          requiredEffectsKeys: _requiredEffects,
        ),
      );
      expect(run.deferred, isTrue);
      expect(store.snapshot.state, PdvV1JournalState.effectsPending);
      expect(store.snapshot.journalRevision, 6);
    });

    test('operation completion precoce gera manual', () {
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
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.operationCompletion,
            revision: 0,
            stateBefore: PdvV1JournalState.effectsCompleted,
            target: PdvV1JournalState.operationCompleted,
          ),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
    });

    test('confirmação stale não altera store', () {
      final record = _journal(PdvV1JournalState.hiveSalePending, revision: 2);
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
          confirmation: _confirmation(
            fp: fp,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            revision: 0,
            stateBefore: PdvV1JournalState.hiveSalePending,
            target: PdvV1JournalState.hiveSaleCompleted,
          ),
        ),
      );
      expect(store.snapshot.toJson(), before);
    });

    test('plano semântico inválido bloqueado antes do CAS', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final blockingCoordinator = PdvV1RecoverySimulationCoordinator(
        semanticsValidator: const _BlockingSemanticsValidator(),
      );
      final before = store.snapshot.toJson();
      final run = blockingCoordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      expect(run.semanticValidation.valid, isFalse);
      expect(run.casApplyOutcome, isNull);
      expect(store.snapshot.toJson(), before);
    });

    test('journal malformado isolado', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {
          'token': 'SECRET',
          'prepared': {'operationId': 'op-mal-chain'},
        },
        storageKey: 'op-mal-chain',
      );
      final store = PdvV1RecoverySimulatedCasStore(outcome.record);
      final before = store.snapshot.toJson();
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: outcome,
        ),
      );
      expect(run.manualInterventionRequired, isTrue);
      expect(run.executionOutcome, isNull);
      expect(store.snapshot.toJson(), before);
    });
  });
}

class _BlockingSemanticsValidator extends PdvV1RecoveryPlanSemanticsValidator {
  const _BlockingSemanticsValidator();

  @override
  PdvV1RecoveryPlanSemanticsValidationResult validate(PdvV1RecoveryPlan plan) {
    return const PdvV1RecoveryPlanSemanticsValidationResult(
      valid: false,
      reasonCode: 'semantic_blocked_for_test',
    );
  }
}
