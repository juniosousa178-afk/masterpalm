import 'dart:convert';
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

PdvV1PreparedSnapshot _prep({String snapshotHash = 'snap-patch-1'}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-patch-1',
    saleId: 'sale-patch-1',
    lojaId: 'loja-patch-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: snapshotHash,
    txItemsHash: 'tx-patch-1',
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
  int? vendaHiveKey,
  Map<String, dynamic>? subestados,
}) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: revision,
    attempts: attempts,
    vendaHiveKey: vendaHiveKey,
    subestados: subestados,
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

PdvV1RecoveryPlanFingerprint _fp(
    PdvV1JournalRecord record, PdvV1RecoveryPlan plan) {
  return pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: record.prepared);
}

PdvV1JournalSameStatePatchIssueOutcome _propose(
  PdvV1JournalRecord record, {
  required PdvV1SimulatedConfirmationStage stage,
  PdvV1RecoveryPlan? plan,
  PdvV1RemoteVerificationEvidence? evidence,
  PdvV1SimulatedStageConfirmation? confirmation,
  PdvV1SimulatedStageStartRequest? stageStartRequest,
}) {
  final p = plan ?? _plan(record);
  final fp = _fp(record, p);
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

Future<void> _put(
    PdvV1HiveJournalRepository repo, PdvV1JournalRecord record) async {
  await repo.put(record);
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late PdvV1HiveJournalRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdv_v1_patch_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>(_boxName);
    repo = PdvV1HiveJournalRepository(box: box);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(_boxName)) {
      await box.close();
      await Hive.deleteBoxFromDisk(_boxName);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<PdvV1JournalSameStatePatchPersistOutcome> persistPatchFor(
    PdvV1JournalRecord stored,
    PdvV1JournalSameStatePatchIssueOutcome issue,
  ) {
    return repo.persistAuthorizedSameStatePatchIfRevisionMatches(
      operationId: stored.operationId,
      expectedJournalRevision: stored.journalRevision,
      patch: issue.patch!,
      authorization: issue.authorization!,
    );
  }

  group('Patch same-state recordRetryableStageFailure', () {
    test('1 patch Hive válido attempts 0→1 revision +1', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await _put(repo, stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      expect(issue.authorized, isTrue);
      final outcome = await persistPatchFor(stored, issue);
      expect(outcome.accepted, isTrue);
      expect(outcome.storedRevisionAfter, 1);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.attempts, 1);
      expect(read.record.ultimoErroSanitizado, 'hive_sale_upsert_unavailable');
      expect(read.record.state, PdvV1JournalState.hiveSalePending);
    });

    test('2 patch Sale Sync válido attempts 1→2', () async {
      final stored =
          _record(PdvV1JournalState.saleSyncPending, revision: 2, attempts: 1);
      await repo.put(stored);
      final issue =
          _propose(stored, stage: PdvV1SimulatedConfirmationStage.saleSync);
      final outcome = await persistPatchFor(stored, issue);
      expect(outcome.storedRevisionAfter, 3);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.attempts, 2);
      expect(read.record.ultimoErroSanitizado, 'sale_sync_unavailable');
    });

    test('3 patch Effects válido attempts 2→3', () async {
      final stored =
          _record(PdvV1JournalState.effectsPending, revision: 4, attempts: 2);
      await repo.put(stored);
      final issue =
          _propose(stored, stage: PdvV1SimulatedConfirmationStage.effects);
      final outcome = await persistPatchFor(stored, issue);
      expect(outcome.storedRevisionAfter, 5);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.attempts, 3);
      expect(read.record.ultimoErroSanitizado, 'effects_unavailable');
    });

    test('4 patch acima de attempts 3 rejeitado', () async {
      final stored =
          _record(PdvV1JournalState.effectsPending, revision: 5, attempts: 3);
      await repo.put(stored);
      final issue =
          _propose(stored, stage: PdvV1SimulatedConfirmationStage.effects);
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'retry_attempt_limit_reached');
    });

    test('5 remoteStockPending patch rejeitado', () async {
      final stored = _record(PdvV1JournalState.remoteStockPending);
      await _put(repo, stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'patch_state_mismatch');
    });

    test('6 markerVerificationUnavailable inerte', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
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
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          plan: deferPlan);
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'marker_verification_unavailable');
    });

    test('7 evidence inesperada pós-baixa inerte', () async {
      final stored = _record(PdvV1JournalState.remoteStockApplied, revision: 1);
      final evidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: stored.operationId,
        requestedSaleId: stored.saleId,
        requestedLojaId: stored.lojaId,
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-patch-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      final issue = _propose(
        stored,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        evidence: evidence,
      );
      expect(issue.authorized, isFalse);
      expect(
          issue.rejectionReasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);
    });

    test('8 plano stale não emite patch', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final stalePlan = _plan(stored).copyWithJournalRevisionAtPlan(99);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          plan: stalePlan);
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'stale_plan_revision');
    });

    test('9 confirmação stale não emite patch', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final fp = _fp(stored, _plan(stored));
      final issue = _propose(
        stored,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        confirmation: PdvV1SimulatedStageConfirmation(
          planFingerprint: fp,
          expectedJournalRevision: 99,
          operationId: stored.operationId,
          saleId: stored.saleId,
          lojaId: stored.lojaId,
          origem: pdvV1OrigemProtocolValue,
          protocolVersion: pdvV1ProtocolVersion,
          snapshotHash: 'snap-patch-1',
          txItemsHash: 'tx-patch-1',
          expectedStateBefore: PdvV1JournalState.hiveSalePending,
          expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
          status: PdvV1SimulatedConfirmationStatus.unavailable,
        ),
      );
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'stale_confirmation_revision');
    });

    test('10 stage request stale não emite patch', () async {
      final stored = _record(PdvV1JournalState.hiveSaleCompleted, revision: 3);
      final fp = _fp(stored, _plan(stored));
      final issue = _propose(
        stored,
        stage: PdvV1SimulatedConfirmationStage.saleSync,
        stageStartRequest: PdvV1SimulatedStageStartRequest(
          planFingerprint: fp,
          operationId: stored.operationId,
          saleId: stored.saleId,
          lojaId: stored.lojaId,
          origem: pdvV1OrigemProtocolValue,
          protocolVersion: pdvV1ProtocolVersion,
          snapshotHash: 'snap-patch-1',
          txItemsHash: 'tx-patch-1',
          expectedJournalRevision: 0,
          expectedStateBefore: PdvV1JournalState.hiveSaleCompleted,
          expectedTargetState: PdvV1JournalState.saleSyncPending,
          stageToStart: PdvV1SimulatedConfirmationStage.saleSync,
          requestKind: PdvV1SimulatedStageStartRequestKind.pendingStageEntry,
          semanticPlanValidated: true,
          identityValidated: true,
        ),
      );
      expect(issue.authorized, isFalse);
      expect(issue.rejectionReasonCode, 'stale_stage_start_revision');
    });

    test('11 patch stage divergente rejeitado na persistência', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      final badAuth = PdvV1JournalSameStatePatchAuthorization(
        patchKind: issue.authorization!.patchKind,
        planFingerprint: issue.authorization!.planFingerprint,
        operationId: issue.authorization!.operationId,
        saleId: issue.authorization!.saleId,
        lojaId: issue.authorization!.lojaId,
        origem: issue.authorization!.origem,
        protocolVersion: issue.authorization!.protocolVersion,
        snapshotHash: issue.authorization!.snapshotHash,
        txItemsHash: issue.authorization!.txItemsHash,
        expectedJournalRevision: issue.authorization!.expectedJournalRevision,
        expectedState: issue.authorization!.expectedState,
        expectedAttempts: issue.authorization!.expectedAttempts,
        stage: PdvV1SimulatedConfirmationStage.saleSync,
        failureCode: issue.authorization!.failureCode,
      );
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: issue.patch!,
        authorization: badAuth,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejectionReasonCode, 'patch_stage_mismatch');
    });

    test('12 patch failureCode divergente rejeitado', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      final badPatch = PdvV1JournalSameStatePatch(
        patchKind: issue.patch!.patchKind,
        expectedState: issue.patch!.expectedState,
        expectedAttempts: issue.patch!.expectedAttempts,
        stageName: issue.patch!.stageName,
        failureCode: PdvV1RetryableStageFailureCode.saleSyncUnavailable,
      );
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: badPatch,
        authorization: issue.authorization!,
      );
      expect(outcome.rejectionReasonCode, 'patch_failure_code_mismatch');
    });

    test('13 expectedAttempts divergente rejeitado', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      final badPatch = PdvV1JournalSameStatePatch(
        patchKind: issue.patch!.patchKind,
        expectedState: issue.patch!.expectedState,
        expectedAttempts: 99,
        stageName: issue.patch!.stageName,
        failureCode: issue.patch!.failureCode,
      );
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: badPatch,
        authorization: issue.authorization!,
      );
      expect(outcome.rejectionReasonCode, 'patch_attempts_mismatch');
    });

    test('14 revision divergente stale', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: 99,
        patch: issue.patch!,
        authorization: issue.authorization!,
      );
      expect(outcome.rejectionReasonCode, 'stale_journal_revision');
    });

    test('15 saleId/hash divergente rejeitado', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      final badAuth = PdvV1JournalSameStatePatchAuthorization(
        patchKind: issue.authorization!.patchKind,
        planFingerprint: issue.authorization!.planFingerprint,
        operationId: issue.authorization!.operationId,
        saleId: 'outro-sale',
        lojaId: issue.authorization!.lojaId,
        origem: issue.authorization!.origem,
        protocolVersion: issue.authorization!.protocolVersion,
        snapshotHash: issue.authorization!.snapshotHash,
        txItemsHash: issue.authorization!.txItemsHash,
        expectedJournalRevision: issue.authorization!.expectedJournalRevision,
        expectedState: issue.authorization!.expectedState,
        expectedAttempts: issue.authorization!.expectedAttempts,
        stage: issue.authorization!.stage,
        failureCode: issue.authorization!.failureCode,
      );
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: issue.patch!,
        authorization: badAuth,
      );
      expect(outcome.rejectionReasonCode, 'identity_mismatch');
    });

    test('16 subestados preservados após patch válido', () async {
      final stored = _record(
        PdvV1JournalState.hiveSalePending,
        subestados: const {'stage': 'hive'},
      );
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      await persistPatchFor(stored, issue);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.subestados, const {'stage': 'hive'});
    });

    test('17 vendaHiveKey preservada após patch válido', () async {
      final stored =
          _record(PdvV1JournalState.hiveSalePending, vendaHiveKey: 42);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      await persistPatchFor(stored, issue);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.vendaHiveKey, 42);
    });

    test('18 updatedAtEpochMs preservado após patch válido', () async {
      final stored = _record(PdvV1JournalState.hiveSalePending);
      await repo.put(stored);
      final issue = _propose(stored,
          stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
      await persistPatchFor(stored, issue);
      final read = await repo.readByOperationId(stored.operationId);
      expect(read!.record.updatedAtEpochMs, 1);
    });

    test('19 patch em operationCompleted rejeitado', () async {
      final stored = _record(PdvV1JournalState.operationCompleted,
          revision: 8, attempts: 1);
      await repo.put(stored);
      final issue =
          _propose(stored, stage: PdvV1SimulatedConfirmationStage.effects);
      expect(issue.authorized, isFalse);
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: stored.operationId,
        expectedJournalRevision: stored.journalRevision,
        patch: PdvV1JournalSameStatePatch(
          patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
          expectedState: stored.state,
          expectedAttempts: 2,
          stageName: 'effects',
          failureCode: PdvV1RetryableStageFailureCode.effectsUnavailable,
        ),
        authorization: PdvV1JournalSameStatePatchAuthorization(
          patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
          planFingerprint: _fp(stored, _plan(stored)),
          operationId: stored.operationId,
          saleId: stored.saleId,
          lojaId: stored.lojaId,
          origem: stored.prepared.origemProtocol,
          protocolVersion: stored.prepared.protocolVersion,
          snapshotHash: stored.prepared.snapshotHash,
          txItemsHash: stored.prepared.txItemsHash,
          expectedJournalRevision: stored.journalRevision,
          expectedState: stored.state,
          expectedAttempts: 2,
          stage: PdvV1SimulatedConfirmationStage.effects,
          failureCode: PdvV1RetryableStageFailureCode.effectsUnavailable,
        ),
      );
      expect(outcome.rejectionReasonCode, 'terminal_state_patch_denied');
    });

    test('20 patch em journal malformado preserva payload', () async {
      final raw = {
        'state': 'hiveSalePending',
        'createdAtEpochMs': 1,
        'updatedAtEpochMs': 1,
        'prepared': _prep().toJson(),
      };
      await box.put('op-patch-1', raw);
      final stored = _record(PdvV1JournalState.hiveSalePending);
      final plan = _plan(stored);
      final fp = _fp(stored, plan);
      final patch = PdvV1JournalSameStatePatch(
        patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
        expectedState: PdvV1JournalState.hiveSalePending,
        expectedAttempts: 1,
        stageName: 'hiveSaleUpsert',
        failureCode: PdvV1RetryableStageFailureCode.hiveSaleUpsertUnavailable,
      );
      final authorization = PdvV1JournalSameStatePatchAuthorization(
        patchKind: PdvV1JournalSameStatePatchKind.recordRetryableStageFailure,
        planFingerprint: fp,
        operationId: stored.operationId,
        saleId: stored.saleId,
        lojaId: stored.lojaId,
        origem: stored.prepared.origemProtocol,
        protocolVersion: stored.prepared.protocolVersion,
        snapshotHash: stored.prepared.snapshotHash,
        txItemsHash: stored.prepared.txItemsHash,
        expectedJournalRevision: 0,
        expectedState: PdvV1JournalState.hiveSalePending,
        expectedAttempts: 1,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        failureCode: PdvV1RetryableStageFailureCode.hiveSaleUpsertUnavailable,
      );
      final outcome =
          await repo.persistAuthorizedSameStatePatchIfRevisionMatches(
        operationId: 'op-patch-1',
        expectedJournalRevision: 0,
        patch: patch,
        authorization: authorization,
      );
      expect(outcome.rejectionReasonCode, 'journal_malformed_patch_denied');
      expect(box.get('op-patch-1'), raw);
    });

    test('24 três execuções idênticas retornam JSON idêntico', () async {
      final runs = <String>[];
      for (var i = 0; i < 3; i++) {
        final dir = await Directory.systemTemp.createTemp('pdv_v1_patch_det_');
        Hive.init(dir.path);
        final localBox = await Hive.openBox<dynamic>(_boxName);
        final localRepo = PdvV1HiveJournalRepository(box: localBox);
        final stored = _record(PdvV1JournalState.hiveSalePending);
        await localRepo.put(stored);
        final issue = _propose(stored,
            stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert);
        final outcome =
            await localRepo.persistAuthorizedSameStatePatchIfRevisionMatches(
          operationId: stored.operationId,
          expectedJournalRevision: stored.journalRevision,
          patch: issue.patch!,
          authorization: issue.authorization!,
        );
        runs.add(jsonEncode(outcome.toJson()));
        await localBox.close();
        await Hive.deleteBoxFromDisk(_boxName);
        await dir.delete(recursive: true);
      }
      expect(runs[0], runs[1]);
      expect(runs[1], runs[2]);
    });
  });
}

extension on PdvV1RecoveryPlan {
  PdvV1RecoveryPlan copyWithJournalRevisionAtPlan(int revision) {
    return PdvV1RecoveryPlan(
      decision: decision,
      currentState: currentState,
      targetState: targetState,
      plannedActions: plannedActions,
      reasonCode: reasonCode,
      operationId: operationId,
      saleId: saleId,
      journalRevisionAtPlan: revision,
      journalIdentity: journalIdentity,
      requiresExternalIntegration: requiresExternalIntegration,
      idempotencyKey: idempotencyKey,
    );
  }
}
