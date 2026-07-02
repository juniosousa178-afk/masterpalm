import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-fp-1',
    saleId: 'sale-fp-1',
    lojaId: 'loja-fp-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-fp-1',
    txItemsHash: 'tx-fp-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1RecoveryPlan _plan({
  List<PdvV1RecoveryPlannedAction> actions = const [
    PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
    PdvV1RecoveryPlannedAction.awaitExternalIntegration,
  ],
  int journalRevisionAtPlan = 0,
}) {
  final prep = _prep();
  return PdvV1RecoveryPlan(
    decision: PdvV1RecoveryDecision.insertHiveSaleOnce,
    currentState: PdvV1JournalState.remoteStockApplied,
    targetState: PdvV1JournalState.hiveSalePending,
    plannedActions: actions,
    reasonCode: 'hive_insert_once',
    operationId: 'op-fp-1',
    saleId: 'sale-fp-1',
    journalRevisionAtPlan: journalRevisionAtPlan,
    journalIdentity: pdvV1BuildJournalIdentity(prep),
    idempotencyKey: 'key-fp',
  );
}

void main() {
  group('PdvV1RecoveryPlanFingerprint', () {
    test('mesmo plano produz fingerprint idêntico', () {
      final prep = _prep();
      final plan = _plan();
      final fp1 = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: prep);
      final fp2 = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: prep);
      expect(fp1.toJson(), fp2.toJson());
      expect(fp1.toCanonicalDiagnosticKey(), fp2.toCanonicalDiagnosticKey());
    });

    test('ordem semântica de actions é preservada; Hive matches canônicos', () {
      final prep = _prep();
      final plan = _plan(
        actions: const [
          PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ],
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: prep,
        hiveMatches: const [
          PdvV1HiveSaleMatch(
            hiveKey: 2,
            saleId: 'sale-fp-1',
            snapshotHash: 'snap-fp-1',
          ),
          PdvV1HiveSaleMatch(
            hiveKey: 1,
            saleId: 'sale-fp-1',
            snapshotHash: 'snap-fp-1',
          ),
        ],
      );
      expect(
        fp.plannedActions.map((a) => a.name).toList(),
        ['planHiveInsertOnceFuture', 'awaitExternalIntegration'],
      );
      expect(fp.hiveMatchesCanonical.first['hiveKey'], 1);
      expect(fp.hiveMatchesCanonical.last['hiveKey'], 2);
    });

    test('plano [A,B] e [B,A] têm fingerprints diferentes', () {
      final prep = _prep();
      final planAb = _plan(
        actions: const [
          PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ],
      );
      final planBa = _plan(
        actions: const [
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
        ],
      );
      final fpAb = pdvV1BuildRecoveryPlanFingerprint(plan: planAb, prep: prep);
      final fpBa = pdvV1BuildRecoveryPlanFingerprint(plan: planBa, prep: prep);
      expect(fpAb.toCanonicalDiagnosticKey(),
          isNot(fpBa.toCanonicalDiagnosticKey()));
    });

    test('duplicata de ação é rejeitada', () {
      expect(
        () => _plan(
          actions: const [
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          ],
        ),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('lista plannedActions exposta é imutável', () {
      final plan = _plan();
      expect(
        () => plan.plannedActions.add(
          PdvV1RecoveryPlannedAction.verifyMarkerAgain,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('fingerprint não é aceito isoladamente com saleId divergente', () {
      final prep = _prep();
      final plan = _plan();
      final fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: prep);
      final confirmation = PdvV1SimulatedStageConfirmation(
        planFingerprint: fp,
        expectedJournalRevision: 0,
        operationId: 'op-fp-1',
        saleId: 'OUTRO-SALE',
        lojaId: 'loja-fp-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-fp-1',
        txItemsHash: 'tx-fp-1',
        expectedStateBefore: PdvV1JournalState.hiveSalePending,
        expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
      );
      expect(fp.identityMatchesConfirmation(confirmation), isFalse);
    });

    test('confirmação com txItemsHash divergente não casa com fingerprint', () {
      final prep = _prep();
      final plan = _plan();
      final fp = pdvV1BuildRecoveryPlanFingerprint(plan: plan, prep: prep);
      final confirmation = PdvV1SimulatedStageConfirmation(
        planFingerprint: fp,
        expectedJournalRevision: 0,
        operationId: 'op-fp-1',
        saleId: 'sale-fp-1',
        lojaId: 'loja-fp-1',
        origem: pdvV1OrigemProtocolValue,
        protocolVersion: pdvV1ProtocolVersion,
        snapshotHash: 'snap-fp-1',
        txItemsHash: 'tx-DIVERGENTE',
        expectedStateBefore: PdvV1JournalState.hiveSalePending,
        expectedTargetState: PdvV1JournalState.hiveSaleCompleted,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
      );
      expect(fp.identityMatchesConfirmation(confirmation), isFalse);
    });
  });
}
