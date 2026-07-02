import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

const _requiredEffects = ['product_cache_refresh', 'catalog_projection'];

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-dur-1',
    saleId: 'sale-dur-1',
    lojaId: 'loja-dur-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-dur-1',
    txItemsHash: 'tx-dur-1',
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
    requestedOperationId: 'op-dur-1',
    requestedSaleId: 'sale-dur-1',
    requestedLojaId: 'loja-dur-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-dur-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-dur-1',
      operationId: 'op-dur-1',
      saleId: 'sale-dur-1',
      baixaAplicada: true,
      txItemsHash: 'tx-dur-1',
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
    operationId: 'op-dur-1',
    saleId: 'sale-dur-1',
    lojaId: 'loja-dur-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-dur-1',
    txItemsHash: 'tx-dur-1',
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
    operationId: 'op-dur-1',
    saleId: 'sale-dur-1',
    lojaId: 'loja-dur-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-dur-1',
    txItemsHash: 'tx-dur-1',
    expectedJournalRevision: revision,
    expectedStateBefore: stateBefore,
    expectedTargetState: target,
    stageToStart: stage,
    requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
    semanticPlanValidated: true,
    identityValidated: true,
  );
}

void _assertFullIdentity(
    PdvV1JournalRecord record, PdvV1JournalState state, int revision) {
  expect(record.operationId, 'op-dur-1');
  expect(record.prepared.saleId, 'sale-dur-1');
  expect(record.prepared.lojaId, 'loja-dur-1');
  expect(record.prepared.origem, PdvV1InternalOrigin.novaVendaPdvFuture);
  expect(record.prepared.protocolVersion, pdvV1ProtocolVersion);
  expect(record.prepared.snapshotHash, 'snap-dur-1');
  expect(record.prepared.txItemsHash, 'tx-dur-1');
  expect(record.prepared.preparedSnapshot, const {'k': 1});
  expect(record.state, state);
  expect(record.journalRevision, revision);
  expect(record.attempts, 0);
  expect(record.isMalformedReadOnly, isFalse);
}

class _DurabilityHarness {
  late Directory tempDir;
  late String boxName;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_durability_');
    Hive.init(tempDir.path);
    boxName = 'pdv_v1_journal_test_box';
    box = await Hive.openBox<dynamic>(boxName);
  }

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(boxName);
    return PdvV1HiveJournalRepository(box: box);
  }

  Future<void> tearDown() async {
    if (Hive.isBoxOpen(boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<PdvV1JournalRecord> _readRecord(PdvV1HiveJournalRepository repo) async {
  final outcome = await repo.readByOperationId('op-dur-1');
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
  expect(outcome.accepted, isTrue);
  expect(outcome.persistedOnlyToInjectedBox, isTrue);
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
  expect(run.casApplyOutcome!.accepted, isTrue);
  await _persistStep(repo, store.snapshot, current.journalRevision);
  return store.snapshot;
}

Future<Map<String, dynamic>> _runDurableChain(
  _DurabilityHarness harness,
  PdvV1RecoverySimulationCoordinator coordinator,
  PdvV1RecoveryOrchestrator orchestrator,
) async {
  var repo = PdvV1HiveJournalRepository(box: harness.box);
  final initial = _journal(PdvV1JournalState.remoteStockPending);
  await _persistStep(repo, initial, 0);

  repo = await harness.reopenRepo();
  var current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.remoteStockPending, 0);

  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
    evidence: _evidence(),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.remoteStockApplied, 1);

  current = await _runCoordinatorPersist(
    coordinator: coordinator,
    repo: repo,
    current: current,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.hiveSalePending, 2);

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
      revision: 2,
      stateBefore: PdvV1JournalState.hiveSalePending,
      target: PdvV1JournalState.hiveSaleCompleted,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.hiveSaleCompleted, 3);

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
      revision: 3,
      stateBefore: PdvV1JournalState.hiveSaleCompleted,
      target: PdvV1JournalState.saleSyncPending,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.saleSyncPending, 4);

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
      revision: 4,
      stateBefore: PdvV1JournalState.saleSyncPending,
      target: PdvV1JournalState.saleSyncCompleted,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.saleSyncCompleted, 5);

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
      revision: 5,
      stateBefore: PdvV1JournalState.saleSyncCompleted,
      target: PdvV1JournalState.effectsPending,
    ),
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.effectsPending, 6);

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
      revision: 6,
      stateBefore: PdvV1JournalState.effectsPending,
      target: PdvV1JournalState.effectsCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.effectsCompleted, 7);

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
      revision: 7,
      stateBefore: PdvV1JournalState.effectsCompleted,
      target: PdvV1JournalState.operationCompleted,
      requiredEffectsKeys: _requiredEffects,
      completedEffectsKeys: _requiredEffects,
    ),
    requiredEffectsKeys: _requiredEffects,
  );
  repo = await harness.reopenRepo();
  current = await _readRecord(repo);
  _assertFullIdentity(current, PdvV1JournalState.operationCompleted, 8);

  return current.toJson();
}

void main() {
  final harness = _DurabilityHarness();
  final coordinator = PdvV1RecoverySimulationCoordinator();
  final orchestrator = PdvV1RecoveryOrchestrator();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('Cadeia durável com restart após cada etapa', () {
    test('cadeia completa revision 0 até 8 sobrevive oito restarts', () async {
      final finalJson =
          await _runDurableChain(harness, coordinator, orchestrator);
      expect(finalJson['state'], 'operationCompleted');
      expect(finalJson['journalRevision'], 8);
      expect(finalJson['prepared']['snapshotHash'], 'snap-dur-1');
      expect(finalJson['prepared']['txItemsHash'], 'tx-dur-1');
    });

    test('preparedSnapshot permanece imutável após reload', () async {
      await _runDurableChain(harness, coordinator, orchestrator);
      final repo = await harness.reopenRepo();
      final first = await _readRecord(repo);
      final repo2 = await harness.reopenRepo();
      final second = await _readRecord(repo2);
      expect(first.prepared.preparedSnapshot, second.prepared.preparedSnapshot);
      expect(first.prepared.toJson(), second.prepared.toJson());
    });

    test('três execuções idênticas produzem mesmo JSON', () async {
      final runs = <String>[];
      for (var i = 0; i < 3; i++) {
        await harness.tearDown();
        await harness.setUp();
        final json = await _runDurableChain(harness, coordinator, orchestrator);
        runs.add(jsonEncode(json));
      }
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });

    test('reabertura repetida retorna leitura equivalente', () async {
      await _runDurableChain(harness, coordinator, orchestrator);
      final repo1 = await harness.reopenRepo();
      final a = await repo1.readByOperationId('op-dur-1');
      final repo2 = await harness.reopenRepo();
      final b = await repo2.readByOperationId('op-dur-1');
      expect(a!.record.toJson(), b!.record.toJson());
    });
  });
}
