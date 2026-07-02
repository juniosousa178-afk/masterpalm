import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';

const _boxName = 'pdv_v1_journal_test_box';
const _executor = PdvV1RecoveryExecutorSimulator();

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-patch-rst-1',
    saleId: 'sale-patch-rst-1',
    lojaId: 'loja-patch-rst-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-patch-rst-1',
    txItemsHash: 'tx-patch-rst-1',
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
}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
    attempts: attempts,
  );
}

PdvV1RecoveryPlan _plan(PdvV1JournalRecord record) {
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

class _RestartHarness {
  late Directory tempDir;
  late Box<dynamic> box;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_patch_restart_');
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
    }
  }
}

void main() {
  final harness = _RestartHarness();

  setUp(() async => harness.setUp());
  tearDown(() async => harness.tearDown());

  PdvV1JournalSameStatePatchIssueOutcome issueForStored(
      PdvV1JournalRecord stored) {
    final plan = _plan(stored);
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

  group('Patch same-state após restart', () {
    test('21 patch válido persiste após fechar/reabrir Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = issueForStored(stored);
      await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );

      repo = await harness.reopenRepo();
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.attempts, 1);
      expect(read.record.ultimoErroSanitizado, 'hive_sale_upsert_unavailable');
      expect(read.record.state, PdvV1JournalState.hiveSalePending);
      expect(read.record.journalRevision, 1);
    });

    test('22 patch stale após outro patch válido não altera Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final first = issueForStored(stored);
      await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        patch: first.patch!,
        authorization: first.authorization!,
      );

      repo = await harness.reopenRepo();
      final afterFirst = await repo.readByOperationId(stored.operationId);
      final staleIssue = issueForStored(afterFirst!.record);
      final stale = await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        patch: staleIssue.patch!,
        authorization: staleIssue.authorization!,
      );
      expect(stale.rejectionReasonCode, 'stale_journal_revision');

      final afterStale = await repo.readByOperationId(stored.operationId);
      expect(afterStale!.record.journalRevision, 1);
      expect(afterStale.record.attempts, 1);
    });

    test('23 repetir mesma autorização após restart não altera Box', () async {
      var repo = PdvV1HiveJournalRepository(box: harness.box);
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = issueForStored(stored);
      await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );

      repo = await harness.reopenRepo();
      final before = await repo.readByOperationId(stored.operationId);
      final repeat =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 0,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );
      expect(repeat.accepted, isFalse);
      expect(repeat.rejectionReasonCode, 'stale_journal_revision');
      final after = await repo.readByOperationId(stored.operationId);
      expect(after!.record.toJson(), before!.record.toJson());
    });
  });
}
