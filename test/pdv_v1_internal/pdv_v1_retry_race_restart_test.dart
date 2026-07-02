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

const _opId = 'op-retry-race-1';
const _boxName = 'pdv_v1_journal_test_box';
const _executor = PdvV1RecoveryExecutorSimulator();
final _coordinator = PdvV1RecoverySimulationCoordinator();
final _orchestrator = PdvV1RecoveryOrchestrator();

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: _opId,
    saleId: 'sale-retry-race-1',
    lojaId: 'loja-retry-race-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-retry-race-1',
    txItemsHash: 'tx-retry-race-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _record(
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

PdvV1SimulatedStageConfirmation _hiveConfirmation(
  PdvV1JournalRecord stored,
  PdvV1RecoveryPlanFingerprint fp,
) {
  return PdvV1SimulatedStageConfirmation(
    planFingerprint: fp,
    expectedJournalRevision: stored.journalRevision,
    operationId: _opId,
    saleId: 'sale-retry-race-1',
    lojaId: 'loja-retry-race-1',
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: 'snap-retry-race-1',
    txItemsHash: 'tx-retry-race-1',
    expectedStateBefore: PdvV1JournalState.hiveSalePending,
    expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
    stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
    status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
  );
}

PdvV1JournalSameStatePatchIssueOutcome _patchIssue(PdvV1JournalRecord stored) {
  final plan = _integrationPlan(stored);
  final fp =
      pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: stored.prepared);
  return _executor.proposeRetryableStageFailurePatch(
    PdvV1RecoveryExecutorSameStatePatchInput(
      journalOutcome: PdvV1JournalReadOutcome(record: stored),
      plan: plan,
      planFingerprint: fp,
      stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
    ),
  );
}

class _RaceHarness {
  late Directory tempDir;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_retry_race_');
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

Future<PdvV1JournalRecord> _read(PdvV1HiveJournalRepository repo) async {
  final outcome = await repo.readByOperationId(_opId);
  expect(outcome, isNotNull);
  return outcome!.record;
}

Future<void> _persistCoordinator(
  PdvV1HiveJournalRepository repo,
  PdvV1JournalRecord current,
  PdvV1SimulatedStageConfirmation confirmation,
) async {
  final store = PdvV1RecoverySimulatedCasStore(current);
  final run = _coordinator.run(
    PdvV1RecoverySimulationInput(
      store: store,
      journalOutcome: PdvV1JournalReadOutcome(record: current),
      confirmation: confirmation,
    ),
  );
  expect(run.casApplyOutcome!.accepted, isTrue);
  final outcome = await repo.persistIfRevisionMatches(
    operationId: current.operationId,
    expectedJournalRevision: current.journalRevision,
    candidateJournalRecord: store.snapshot,
  );
  expect(outcome.accepted, isTrue);
}

void main() {
  final harness = _RaceHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  group('Corridas patch versus confirmação após restart', () {
    test('A patch primeiro deixa confirmação stale em revision 2', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.hiveSalePending, revision: 2);
      await repo.put(stored);

      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: stored.prepared);
      final issue = _patchIssue(stored);
      final confirmation = _hiveConfirmation(stored, fp);

      await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 2,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );

      repo = await harness.reopenRepo();
      var current = await _read(repo);
      expect(current.state, PdvV1JournalState.hiveSalePending);
      expect(current.journalRevision, 3);
      expect(current.attempts, 1);

      final staleRun = _coordinator.run(
        PdvV1RecoverySimulationInput(
          store: PdvV1RecoverySimulatedCasStore(current),
          journalOutcome: PdvV1JournalReadOutcome(record: current),
          confirmation: confirmation,
        ),
      );
      expect(staleRun.casApplyOutcome, isNull);
      expect(staleRun.executionOutcome!.isManualIntervention, isTrue);
      expect(staleRun.reasonCode, 'stale_confirmation_revision');

      final after = await _read(repo);
      expect(after.state, PdvV1JournalState.hiveSalePending);
      expect(after.journalRevision, 3);
      expect(after.attempts, 1);
    });

    test('B confirmação primeiro deixa patch stale em revision 2', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.hiveSalePending, revision: 2);
      await repo.put(stored);

      final plan = _orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
        ),
      );
      final fp =
          pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: stored.prepared);
      final issue = _patchIssue(stored);
      final confirmation = _hiveConfirmation(stored, fp);

      await _persistCoordinator(repo, stored, confirmation);

      repo = await harness.reopenRepo();
      var current = await _read(repo);
      expect(current.state, PdvV1JournalState.hiveSaleCompleted);
      expect(current.journalRevision, 3);
      expect(current.attempts, 0);

      final stale = await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 2,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );
      expect(stale.accepted, isFalse);
      expect(stale.rejectionReasonCode, 'stale_journal_revision');

      final after = await _read(repo);
      expect(after.state, PdvV1JournalState.hiveSaleCompleted);
      expect(after.journalRevision, 3);
      expect(after.attempts, 0);
    });

    test('C dois patches concorrentes — segundo stale após restart', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(
        PdvV1JournalState.saleSyncPending,
        revision: 5,
        attempts: 1,
        ultimoErro: 'hive_sale_upsert_unavailable',
      );
      await repo.put(stored);

      final issueA = _executor.proposeRetryableStageFailurePatch(
        PdvV1RecoveryExecutorSameStatePatchInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
          plan: _integrationPlan(stored),
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: _integrationPlan(stored),
            prep: stored.prepared,
          ),
          stage: PdvV1SimulatedConfirmationStage.saleSync,
        ),
      );
      final issueB = _executor.proposeRetryableStageFailurePatch(
        PdvV1RecoveryExecutorSameStatePatchInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
          plan: _integrationPlan(stored),
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: _integrationPlan(stored),
            prep: stored.prepared,
          ),
          stage: PdvV1SimulatedConfirmationStage.saleSync,
        ),
      );

      await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 5,
        patch: issueA.patch!,
        authorization: issueA.authorization!,
      );

      repo = await harness.reopenRepo();
      final stale = await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 5,
        patch: issueB.patch!,
        authorization: issueB.authorization!,
      );
      expect(stale.rejectionReasonCode, 'stale_journal_revision');

      final after = await _read(repo);
      expect(after.state, PdvV1JournalState.saleSyncPending);
      expect(after.journalRevision, 6);
      expect(after.attempts, 2);
      expect(after.ultimoErroSanitizado, 'sale_sync_unavailable');
    });

    test('D quarto retry em effectsPending revision 9 não altera Box',
        () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(
        PdvV1JournalState.effectsPending,
        revision: 9,
        attempts: 3,
        ultimoErro: 'effects_unavailable',
      );
      await repo.put(stored);
      final beforeJson = (await _read(repo)).toJson();

      final issue = _executor.proposeRetryableStageFailurePatch(
        PdvV1RecoveryExecutorSameStatePatchInput(
          journalOutcome: PdvV1JournalReadOutcome(record: stored),
          plan: _integrationPlan(stored),
          planFingerprint: pdvV1BuildRecoveryPlanFingerprint(
            plan: _integrationPlan(stored),
            prep: stored.prepared,
          ),
          stage: PdvV1SimulatedConfirmationStage.effects,
        ),
      );
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'retry_attempt_limit_reached');

      repo = await harness.reopenRepo();
      final after = await _read(repo);
      expect(after.toJson(), beforeJson);
      expect(after.state, PdvV1JournalState.effectsPending);
      expect(after.journalRevision, 9);
      expect(after.attempts, 3);
    });
  });
}
