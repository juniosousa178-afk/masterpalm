import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

const _opId = 'op-retry-ms-1';
const _boxName = 'pdv_v1_journal_test_box';
const _requiredEffects = ['product_cache_refresh', 'catalog_projection'];
const _executor = PdvV1RecoveryExecutorSimulator();

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: _opId,
    saleId: 'sale-retry-ms-1',
    lojaId: 'loja-retry-ms-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-retry-ms-1',
    txItemsHash: 'tx-retry-ms-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _journal(
  PdvV1JournalState state, {
  int revision = 0,
  int attempts = 0,
  String ultimoErro = '',
}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
    attempts: attempts,
    ultimoErroSanitizado: ultimoErro,
  );
}

PdvV1RemoteVerificationEvidence _evidence() {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: _opId,
    requestedSaleId: 'sale-retry-ms-1',
    requestedLojaId: 'loja-retry-ms-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-retry-ms-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-retry-ms-1',
      operationId: _opId,
      saleId: 'sale-retry-ms-1',
      baixaAplicada: true,
      txItemsHash: 'tx-retry-ms-1',
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
    operationId: record.operationId,
    saleId: record.saleId,
    journalRevisionAtPlan: record.journalRevision,
    journalIdentity: pdvV1BuildJournalIdentityFromRecord(record),
    requiresExternalIntegration: true,
    idempotencyKey: 'integration-${record.state.name}',
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
    operationId: _opId,
    saleId: 'sale-retry-ms-1',
    lojaId: 'loja-retry-ms-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-retry-ms-1',
    txItemsHash: 'tx-retry-ms-1',
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
    operationId: _opId,
    saleId: 'sale-retry-ms-1',
    lojaId: 'loja-retry-ms-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-retry-ms-1',
    txItemsHash: 'tx-retry-ms-1',
    expectedJournalRevision: revision,
    expectedStateBefore: stateBefore,
    expectedTargetState: target,
    stageToStart: stage,
    requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
    semanticPlanValidated: true,
    identityValidated: true,
  );
}

void _assertRecordIdentity(
  PdvV1JournalRecord record, {
  required PdvV1JournalState state,
  required int revision,
  required int attempts,
  required String ultimoErro,
}) {
  expect(record.operationId, _opId);
  expect(record.prepared.saleId, 'sale-retry-ms-1');
  expect(record.prepared.lojaId, 'loja-retry-ms-1');
  expect(record.prepared.origem, PdvV1InternalOrigin.novaVendaPdvFuture);
  expect(record.prepared.protocolVersion, pdvV1ProtocolVersion);
  expect(record.prepared.snapshotHash, 'snap-retry-ms-1');
  expect(record.prepared.txItemsHash, 'tx-retry-ms-1');
  expect(record.prepared.preparedSnapshot, const {'k': 1});
  expect(record.state, state);
  expect(record.journalRevision, revision);
  expect(record.attempts, attempts);
  expect(record.ultimoErroSanitizado, ultimoErro);
  expect(record.isMalformedReadOnly, isFalse);
  expect(record.subestados, isEmpty);
}

class _RetryHarness {
  late Directory tempDir;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_retry_multistep_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(_boxName);
    return PdvV1HiveJournalRepository(box: box);
  }

  Future<void> tearDown() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(_boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
      expect(await tempDir.exists(), isFalse);
    }
  }
}

Future<PdvV1JournalRecord> _readRecord(PdvV1HiveJournalRepository repo) async {
  final outcome = await repo.readByOperationId(_opId);
  expect(outcome, isNotNull);
  expect(outcome!.isMalformedReadOnly, isFalse);
  return outcome.record;
}

Future<void> _persistStep(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord candidate,
  int expectedRevision,
) async {
  final outcome = await repo.persistIfRevisionMatches(
    operationId: candidate.operationId,
    expectedJournalRevision: expectedRevision,
    candidateJournalRecord: candidate,
  );
  expect(outcome.accepted, isTrue, reason: outcome.rejectionReasonCode);
  expect(outcome.persistedOnlyToInjectedBox, isTrue);
}

Future<PdvV1JournalRecord> _persistPatchStep(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord current,
  PdvV1SimulatedConfirmationStage stage,
) async {
  final plan = _integrationPlan(current);
  final fp =
      pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  final issue = _executor.proposeRetryableStageFailurePatch(
    PdvV1RecoveryExecutorSameStatePatchInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
      plan: plan,
      planFingerprint: fp,
      stage: stage,
    ),
  );
  expect(issue.authorized, isTrue, reason: issue.rejectionReasonCode);
  final outcome = await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
    operationId: current.operationId,
    expectedJournalRevision: current.journalRevision,
    patch: issue.patch!,
    authorization: issue.authorization!,
  );
  expect(outcome.accepted, isTrue, reason: outcome.rejectionReasonCode);
  return _readRecord(repo);
}

Future<PdvV1JournalRecord> _runCoordinatorPersist({
  required PdvV1RecoverySimulationCoordinator coordinator,
  required PdvV1HiveJournalRepository repo,
  required PdvV1JournalRecord current,
  PdvV1RemoteVerificationEvidence? evidence,
  PdvV1SimulatedStageConfirmation? confirmation,
  PdvV1SimulatedStageStartRequest? stageStartRequest,
  List<String> requiredEffectsKeys = const [],
}) async {
  final store = PdvV1RecoverySimulatedCasStore(current);
  final run = coordinator.run(
    PdvV1RecoverySimulationInput(
      store: store,
      journalOutcome: PdvV1JournalReadOutcome(record: current),
      evidence: evidence,
      confirmation: confirmation,
      stageStartRequest: stageStartRequest,
      requiredEffectsKeys: requiredEffectsKeys,
    ),
  );
  expect(run.casApplyOutcome, isNotNull);
  expect(run.casApplyOutcome!.accepted, isTrue,
      reason: run.casApplyOutcome!.rejectionReasonCode);
  await _persistStep(repo, store.snapshot, current.journalRevision);
  return store.snapshot;
}

Future<Map<String, dynamic>> _runRetryChain(
  _RetryHarness harness,
  PdvV1RecoverySimulationCoordinator coordinator,
  PdvV1RecoveryOrchestrator orchestrator,
) async {
  var repo = PdvV1HiveJournalRepository(box: harness.box);
  await _persistStep(repo, _journal(PdvV1JournalState.remoteStockPending), 0);

  repo = await harness.reopenRepo();
  var current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.remoteStockPending,
    revision: 0,
    attempts: 0,
    ultimoErro: '',
  );

  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    evidence: _evidence(),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.remoteStockApplied,
    revision: 1,
    attempts: 0,
    ultimoErro: '',
  );

  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.hiveSalePending,
    revision: 2,
    attempts: 0,
    ultimoErro: '',
  );

  current = await _persistPatchStep(
    repo,
    current,
    PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.hiveSalePending,
    revision: 3,
    attempts: 1,
    ultimoErro: 'hive_sale_upsert_unavailable',
  );

  var plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  var fp =
      pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    confirmation: _confirmation(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
      revision: 3,
      stateBefore: PdvV1JournalState.hiveSalePending,
      target: PdvV1JournalState.hiveSaleCompleted,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.hiveSaleCompleted,
    revision: 4,
    attempts: 1,
    ultimoErro: 'hive_sale_upsert_unavailable',
  );

  plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    stageStartRequest: _stageStart(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.saleSync,
      revision: 4,
      stateBefore: PdvV1JournalState.hiveSaleCompleted,
      target: PdvV1JournalState.saleSyncPending,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.saleSyncPending,
    revision: 5,
    attempts: 1,
    ultimoErro: 'hive_sale_upsert_unavailable',
  );

  current = await _persistPatchStep(
    repo,
    current,
    PdvV1SimulatedConfirmationStage.saleSync,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.saleSyncPending,
    revision: 6,
    attempts: 2,
    ultimoErro: 'sale_sync_unavailable',
  );

  plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    confirmation: _confirmation(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.saleSync,
      revision: 6,
      stateBefore: PdvV1JournalState.saleSyncPending,
      target: PdvV1JournalState.saleSyncCompleted,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.saleSyncCompleted,
    revision: 7,
    attempts: 2,
    ultimoErro: 'sale_sync_unavailable',
  );

  plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    stageStartRequest: _stageStart(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.effects,
      revision: 7,
      stateBefore: PdvV1JournalState.saleSyncCompleted,
      target: PdvV1JournalState.effectsPending,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.effectsPending,
    revision: 8,
    attempts: 2,
    ultimoErro: 'sale_sync_unavailable',
  );

  current = await _persistPatchStep(
    repo,
    current,
    PdvV1SimulatedConfirmationStage.effects,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.effectsPending,
    revision: 9,
    attempts: 3,
    ultimoErro: 'effects_unavailable',
  );

  final fourth = _executor.proposeRetryableStageFailurePatch(
    PdvV1RecoveryExecutorSameStatePatchInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
      plan: _integrationPlan(current),
      planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
        plan: _integrationPlan(current),
        prep: current.prepared,
      ),
      stage: PdvV1SimulatedConfirmationStage.effects,
    ),
  );
  expect(fourth.authorized, isFalse);
  expect(fourth.rejectionReasonCode, 'retry_attempt_limit_reached');
  final afterFourth = await _readRecord(repo);
  expect(afterFourth.toJson(), current.toJson());

  plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    confirmation: _confirmation(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.effects,
      revision: 9,
      stateBefore: PdvV1JournalState.effectsPending,
      target: PdvV1JournalState.effectsCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.effectsCompleted,
    revision: 10,
    attempts: 3,
    ultimoErro: 'effects_unavailable',
  );

  plan = orchestrator.plan(
    PdvV1RecoveryOrchestratorInput(
      journalOutcome: PdvV1JournalReadOutcome(record: current),
    ),
  );
  fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: current.prepared);
  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    confirmation: _confirmation(
      fp: fp,
      stage: PdvV1SimulatedConfirmationStage.operationCompletion,
      revision: 10,
      stateBefore: PdvV1JournalState.effectsCompleted,
      target: PdvV1JournalState.operationCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertRecordIdentity(
    current,
    state: PdvV1JournalState.operationCompleted,
    revision: 11,
    attempts: 3,
    ultimoErro: 'effects_unavailable',
  );

  return current.toJson();
}

void main() {
  final harness = _RetryHarness();
  final coordinator = PdvV1RecoverySimulationCoordinator();
  final orchestrator = PdvV1RecoveryOrchestrator();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('Retry multi-etapa durável R0→R11', () {
    test('cadeia completa com restart após cada persistência', () async {
      final finalJson =
          await _runRetryChain(harness, coordinator, orchestrator);
      expect(finalJson['state'], 'operationCompleted');
      expect(finalJson['journalRevision'], 11);
      expect(finalJson['attempts'], 3);
      expect(finalJson['ultimoErroSanitizado'], 'effects_unavailable');
    });

    test('três execuções idênticas produzem JSON idêntico', () async {
      final runs = <String>[];
      for (var i = 0; i < 3; i++) {
        await harness.tearDown();
        await harness.setUp();
        runs.add(jsonEncode(
            await _runRetryChain(harness, coordinator, orchestrator)));
      }
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });

    test('preparedSnapshot permanece imutável após reload', () async {
      await _runRetryChain(harness, coordinator, orchestrator);
      final repo1 = await harness.reopenRepo();
      final first = await _readRecord(repo1);
      final repo2 = await harness.reopenRepo();
      final second = await _readRecord(repo2);
      expect(first.prepared.preparedSnapshot, second.prepared.preparedSnapshot);
      expect(first.prepared.toJson(), second.prepared.toJson());
    });
  });
}
