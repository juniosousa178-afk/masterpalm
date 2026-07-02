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

const _opId = 'op-retry-bnd-1';
const _boxName = 'pdv_v1_journal_test_box';
const _executor = PdvV1RecoveryExecutorSimulator();
final _coordinator = PdvV1RecoverySimulationCoordinator();
final _orchestrator = PdvV1RecoveryOrchestrator();

PdvV1PreparedSnapshot _prep({
  PdvV1InternalOrigin origem = PdvV1InternalOrigin.novaVendaPdvFuture,
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: _opId,
    saleId: 'sale-retry-bnd-1',
    lojaId: 'loja-retry-bnd-1',
    origem: origem,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-retry-bnd-1',
    txItemsHash: 'tx-retry-bnd-1',
    isFiado: isFiado,
    hasCombo: hasCombo,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

PdvV1JournalRecord _record(
  PdvV1JournalState state, {
  int revision = 0,
  int attempts = 0,
  PdvV1PreparedSnapshot? prepared,
}) {
  return PdvV1JournalRecord(
    prepared: prepared ?? _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
    attempts: attempts,
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

PdvV1JournalSameStatePatchIssueOutcome _propose(
  PdvV1JournalRecord record, {
  required PdvV1SimulatedConfirmationStage stage,
  PdvV1RecoveryPlan? plan,
  PdvV1RemoteVerificationEvidence? evidence,
  PdvV1SimulatedStageConfirmation? confirmation,
  PdvV1SimulatedStageStartRequest? stageStartRequest,
}) {
  final p = plan ?? _integrationPlan(record);
  final fp = pdvV1BuildRecoveryPlanFingerprint(plan: p, prep: record.prepared);
  return _executor.proposeRetryableStageFailurePatch(
    PdvV1RecoveryExecutorSameStatePatchInput(
      journalOutcome: PdvV1JournalReadOutcome(record: record),
      plan: p,
      planFingerprint: fp,
      stage: stage,
      evidence: evidence,
      confirmation: confirmation,
      stageStartRequest: stageStartRequest,
    ),
  );
}

class _BoundaryHarness {
  late Directory tempDir;
  late Box<dynamic> box;
  late PdvV1HiveJournalRepository repo;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_retry_boundary_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(_boxName);
    repo = PdvV1HiveJournalRepository(box: box);
  }

  Future<PdvV1HiveJournalRepository> reopenRepo() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
    }
    box = await Hive.openBox<dynamic>(_boxName);
    repo = PdvV1HiveJournalRepository(box: box);
    return repo;
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

Future<void> _assertBoxUnchanged(
  PdvV1HiveJournalRepository repo,
  Map<String, dynamic> beforeJson,
) async {
  final read = await repo.readByOperationId(_opId);
  expect(read!.record.toJson(), beforeJson);
}

Future<Map<String, dynamic>> _putAndSnapshot(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord stored,
) async {
  await repo.put(stored);
  return (await repo.readByOperationId(stored.operationId))!.record.toJson();
}

void main() {
  final harness = _BoundaryHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('Gatilhos inertes — sem patch nem persistência', () {
    Future<void> assertInert(
      Map<String, dynamic> beforeJson,
      PdvV1JournalSameStatePatchIssueOutcome issue,
    ) async {
      expect(issue.authorized, isFalse);
      expect(issue.authorization, isNull);
      expect(issue.patch, isNull);
      await _assertBoxUnchanged(harness.repo, beforeJson);
    }

    test('markerVerificationUnavailable', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final deferPlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.deferUntilVerification,
        currentState: stored.state,
        targetState: stored.state,
        plannedActions: const [],
        reasonCode: 'marker_verification_unavailable',
        operationId: stored.operationId,
        saleId: stored.saleId,
        journalRevisionAtPlan: stored.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(stored),
        idempotencyKey: 'defer',
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            plan: deferPlan),
      );
    });

    test('evidence ausente em remoteStockPending', () async {
      final stored = _record(PdvV1JournalState.remoteStockPending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      await assertInert(
        beforeJson,
        _propose(stored, stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert),
      );
    });

    test('evidence inesperada em hiveSalePending', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending, revision: 2);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final evidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: _opId,
        requestedSaleId: 'sale-retry-bnd-1',
        requestedLojaId: 'loja-retry-bnd-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-retry-bnd-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      await assertInert(
        beforeJson,
        _propose(
          stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          evidence: evidence,
        ),
      );
    });

    test('evidence inesperada em saleSyncPending', () async {
      final stored = _record(PdvV1JournalState.saleSyncPending, revision: 4);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final evidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: _opId,
        requestedSaleId: 'sale-retry-bnd-1',
        requestedLojaId: 'loja-retry-bnd-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-retry-bnd-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            evidence: evidence),
      );
    });

    test('evidence inesperada em effectsPending', () async {
      final stored = _record(PdvV1JournalState.effectsPending, revision: 6);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final evidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: _opId,
        requestedSaleId: 'sale-retry-bnd-1',
        requestedLojaId: 'loja-retry-bnd-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-retry-bnd-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.effects, evidence: evidence),
      );
    });

    test('stale_plan_revision', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final basePlan = _integrationPlan(stored);
      final stalePlan = PdvV1RecoveryPlan(
        decision: basePlan.decision,
        currentState: basePlan.currentState,
        targetState: basePlan.targetState,
        plannedActions: basePlan.plannedActions,
        reasonCode: basePlan.reasonCode,
        operationId: basePlan.operationId,
        saleId: basePlan.saleId,
        journalRevisionAtPlan: 99,
        journalIdentity: basePlan.journalIdentity,
        requiresExternalIntegration: basePlan.requiresExternalIntegration,
        idempotencyKey: basePlan.idempotencyKey,
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            plan: stalePlan),
      );
    });

    test('stale_confirmation_revision', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: _integrationPlan(stored),
        prep: stored.prepared,
      );
      await assertInert(
        beforeJson,
        _propose(
          stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          confirmation: PdvV1SimulatedStageConfirmation(
            planFingerprint: fp,
            expectedJournalRevision: 99,
            operationId: _opId,
            saleId: 'sale-retry-bnd-1',
            lojaId: 'loja-retry-bnd-1',
            origem: pdvV1OrigemProtocolValue,
            protocolVersion: pdvV1ProtocolVersion,
            snapshotHash: 'snap-retry-bnd-1',
            txItemsHash: 'tx-retry-bnd-1',
            expectedStateBefore: PdvV1JournalState.hiveSalePending,
            expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            status: PdvV1SimulatedConfirmationStatus.unavailable,
          ),
        ),
      );
    });

    test('stale_stage_start_revision', () async {
      final stored = _record(PdvV1JournalState.hiveSaleCompleted, revision: 3);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: _integrationPlan(stored),
        prep: stored.prepared,
      );
      await assertInert(
        beforeJson,
        _propose(
          stored,
          stage: PdvV1SimulatedConfirmationStage.saleSync,
          stageStartRequest: PdvV1SimulatedStageStartRequest(
            planFingerprint: fp,
            operationId: _opId,
            saleId: 'sale-retry-bnd-1',
            lojaId: 'loja-retry-bnd-1',
            origem: pdvV1OrigemProtocolValue,
            protocolVersion: pdvV1ProtocolVersion,
            snapshotHash: 'snap-retry-bnd-1',
            txItemsHash: 'tx-retry-bnd-1',
            expectedJournalRevision: 0,
            expectedStateBefore: PdvV1JournalState.hiveSaleCompleted,
            expectedTargetState: PdvV1JournalState.saleSyncPending,
            stageToStart: PdvV1SimulatedConfirmationStage.saleSync,
            requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
            semanticPlanValidated: true,
            identityValidated: true,
          ),
        ),
      );
    });

    test('confirmação stage errado', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: _integrationPlan(stored),
        prep: stored.prepared,
      );
      await assertInert(
        beforeJson,
        _propose(
          stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          confirmation: PdvV1SimulatedStageConfirmation(
            planFingerprint: fp,
            expectedJournalRevision: stored.journalRevision,
            operationId: _opId,
            saleId: 'sale-retry-bnd-1',
            lojaId: 'loja-retry-bnd-1',
            origem: pdvV1OrigemProtocolValue,
            protocolVersion: pdvV1ProtocolVersion,
            snapshotHash: 'snap-retry-bnd-1',
            txItemsHash: 'tx-retry-bnd-1',
            expectedStateBefore: PdvV1JournalState.hiveSalePending,
            expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
            stage: PdvV1SimulatedConfirmationStage.saleSync,
            status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
          ),
        ),
      );
    });

    test('stage request stage errado', () async {
      final stored = _record(PdvV1JournalState.hiveSaleCompleted, revision: 3);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: _integrationPlan(stored),
        prep: stored.prepared,
      );
      await assertInert(
        beforeJson,
        _propose(
          stored,
          stage: PdvV1SimulatedConfirmationStage.saleSync,
          stageStartRequest: PdvV1SimulatedStageStartRequest(
            planFingerprint: fp,
            operationId: _opId,
            saleId: 'sale-retry-bnd-1',
            lojaId: 'loja-retry-bnd-1',
            origem: pdvV1OrigemProtocolValue,
            protocolVersion: pdvV1ProtocolVersion,
            snapshotHash: 'snap-retry-bnd-1',
            txItemsHash: 'tx-retry-bnd-1',
            expectedJournalRevision: stored.journalRevision,
            expectedStateBefore: PdvV1JournalState.hiveSaleCompleted,
            expectedTargetState: PdvV1JournalState.saleSyncPending,
            stageToStart: PdvV1SimulatedConfirmationStage.effects,
            requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
            semanticPlanValidated: true,
            identityValidated: true,
          ),
        ),
      );
    });

    test('plano semanticamente inválido', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final invalidPlan = PdvV1RecoveryPlan(
        decision: PdvV1RecoveryDecision.invalidInput,
        currentState: stored.state,
        targetState: stored.state,
        plannedActions: const [],
        reasonCode: 'invalid_plan',
        operationId: stored.operationId,
        saleId: stored.saleId,
        journalRevisionAtPlan: stored.journalRevision,
        journalIdentity: pdvV1BuildJournalIdentityFromRecord(stored),
        idempotencyKey: 'invalid',
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            plan: invalidPlan),
      );
    });

    test('journal terminal', () async {
      final stored = _record(PdvV1JournalState.operationCompleted, revision: 8);
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      await assertInert(
        beforeJson,
        _propose(stored, stage: PdvV1SimulatedConfirmationStage.effects),
      );
    });

    test('origem legado', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        prepared: _prep(origem: PdvV1InternalOrigin.orderReviewLegacy),
      );
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert, plan: plan),
      );
    });

    test('isFiado', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        prepared: _prep(isFiado: true),
      );
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert, plan: plan),
      );
    });

    test('hasCombo', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        prepared: _prep(hasCombo: true),
      );
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert, plan: plan),
      );
    });

    test('isEdicao', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        prepared: _prep(isEdicao: true),
      );
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert, plan: plan),
      );
    });

    test('isCancelamento', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        prepared: _prep(isCancelamento: true),
      );
      final beforeJson = await _putAndSnapshot(harness.repo, stored);
      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      await assertInert(
        beforeJson,
        _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert, plan: plan),
      );
    });
  });

  group('Journal malformado e retry', () {
    test('payload bruto preservado — patch, confirmação e plano inertes',
        () async {
      final raw = {
        'state': 'hiveSalePending',
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': _prep().toJson(),
      };
      await harness.box.put(_opId, raw);

      await harness.box.close();
      harness.box = await Hive.openBox<dynamic>(_boxName);
      harness.repo = PdvV1HiveJournalRepository(box: harness.box);

      final read = await harness.repo.readByOperationId(_opId);
      expect(read!.isMalformedReadOnly, isTrue);
      expect(harness.box.get(_opId), raw);

      final malformedPlan = _integrationPlan(read.record);
      final issue = _executor.proposeRetryableStageFailurePatch(
        PdvV1RecoveryExecutorSameStatePatchInput(
          journalOutcome: read,
          plan: malformedPlan,
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: malformedPlan,
            prep: read.record.prepared,
          ),
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        ),
      );
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'journal_malformed_patch_denied');

      final persist =
          await harness.repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: _opId,
        expectedJournalRevision: 0,
        patch: const PdvV1JournalSameStatePatch(
          patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
          expectedState: PdvV1JournalState.hiveSalePending,
          expectedAttempts: 1,
          stageName: 'hiveSaleUpsert',
          failureCode: PdvV1RetryableStageFailureCode.hiveSaleUpsertUnavailable,
        ),
        authorization: PdvV1JournalSameStatePatchAuthorization(
          patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: _integrationPlan(read.record),
            prep: read.record.prepared,
          ),
          operationId: _opId,
          saleId: 'sale-retry-bnd-1',
          lojaId: 'loja-retry-bnd-1',
          origem: pdvV1OrigemProtocolValue,
          protocolVersion: pdvV1ProtocolVersion,
          snapshotHash: 'snap-retry-bnd-1',
          txItemsHash: 'tx-retry-bnd-1',
          expectedJournalRevision: 0,
          expectedState: PdvV1JournalState.hiveSalePending,
          expectedAttempts: 1,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          failureCode: PdvV1RetryableStageFailureCode.hiveSaleUpsertUnavailable,
        ),
      );
      expect(persist.rejectionReasonCode, 'journal_malformed_patch_denied');

      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: read),
      );
      expect(plan.isManualIntervention, isTrue);

      final store = PdvV1RecoverySimulatedCasStore(read.record);
      final run = _coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: read,
          confirmation: PdvV1SimulatedStageConfirmation(
            planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
              plan: plan,
              prep: read.record.prepared,
            ),
            expectedJournalRevision: 0,
            operationId: _opId,
            saleId: 'sale-retry-bnd-1',
            lojaId: 'loja-retry-bnd-1',
            origem: pdvV1OrigemProtocolValue,
            protocolVersion: pdvV1ProtocolVersion,
            snapshotHash: 'snap-retry-bnd-1',
            txItemsHash: 'tx-retry-bnd-1',
            expectedStateBefore: PdvV1JournalState.hiveSalePending,
            expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
            status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
          ),
        ),
      );
      expect(run.casApplyOutcome, isNull);
      expect(run.manualInterventionRequired, isTrue);
      expect(run.reasonCode, pdvV1MalformedRecoveryReasonCode);

      harness.repo = await harness.reopenRepo();
      expect(harness.box.get(_opId), raw);
    });
  });
}
