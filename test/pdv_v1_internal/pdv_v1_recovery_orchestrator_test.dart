import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';

PdvV1PreparedSnapshot _prep({
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-orch-1',
    saleId: 'sale-orch-1',
    lojaId: 'loja-orch-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-orch-1',
    txItemsHash: 'tx-orch-1',
    isFiado: isFiado,
    hasCombo: hasCombo,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

PdvV1JournalRecord _journal(PdvV1JournalState state,
    {PdvV1PreparedSnapshot? prep}) {
  return PdvV1JournalRecord(
    prepared: prep ?? _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

PdvV1RemoteVerificationEvidence _evidence({
  PdvV1RemoteVerificationStatus status =
      PdvV1RemoteVerificationStatus.markerAbsentVerified,
  PdvV1RemoteMarkerInput marker = const PdvV1RemoteMarkerInput.ausente(),
}) {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: 'op-orch-1',
    requestedSaleId: 'sale-orch-1',
    requestedLojaId: 'loja-orch-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-orch-1',
    verificationStatus: status,
    optionalMarker: marker,
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('PdvV1RecoveryOrchestrator', () {
    test('journal ausente + marcador isolado gera manual', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          evidence: _evidence(
            status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
            marker: const PdvV1RemoteMarkerInput(
              presente: true,
              protocolVersion: pdvV1ProtocolVersion,
              origem: pdvV1OrigemProtocolValue,
              lojaId: 'loja-orch-1',
              operationId: 'op-orch-1',
              saleId: 'sale-orch-1',
              baixaAplicada: true,
              txItemsHash: 'tx-orch-1',
            ),
          ),
          context: const PdvV1RecoveryContext(
            markerPresentWithoutJournal: true,
          ),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
      expect(plan.isManualIntervention, isTrue);
    });

    test('journal malformado preserva manual e não planeja escrita', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {'state': 'invalid'},
        storageKey: 'bad-orch',
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
      expect(
        plan.plannedActions,
        contains(PdvV1RecoveryPlannedAction.preserveMalformedEvidence),
      );
      expect(
        plan.plannedActions,
        isNot(contains(PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture)),
      );
    });

    test('pending + indisponível permanece pending e é deferred', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockPending),
          ),
          evidence: _evidence(
            status: PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
          ),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.deferUntilVerification);
      expect(plan.isDeferred, isTrue);
      expect(plan.targetState, PdvV1JournalState.remoteStockPending);
      expect(
        plan.plannedActions,
        isNot(contains(
            PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture)),
      );
    });

    test('pending + ausência compatível retorna plano de rebaixa futura', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockPending),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.replanRemoteStockTransaction);
      expect(plan.targetState, PdvV1JournalState.prepared);
      expect(
        plan.plannedActions,
        contains(PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture),
      );
    });

    test('pending + marker aplicado compatível avança para remoteStockApplied',
        () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockPending),
          ),
          evidence: _evidence(
            status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
            marker: const PdvV1RemoteMarkerInput(
              presente: true,
              protocolVersion: pdvV1ProtocolVersion,
              origem: pdvV1OrigemProtocolValue,
              lojaId: 'loja-orch-1',
              operationId: 'op-orch-1',
              saleId: 'sale-orch-1',
              baixaAplicada: true,
              txItemsHash: 'tx-orch-1',
            ),
          ),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.continueWithHiveUpsert);
      expect(plan.targetState, PdvV1JournalState.remoteStockApplied);
    });

    test('remoteStockApplied + sem Hive gera planHiveInsertOnceFuture', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockApplied),
          ),
          hiveMatches: const [],
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.insertHiveSaleOnce);
      expect(plan.targetState, PdvV1JournalState.hiveSalePending);
      expect(
        plan.plannedActions,
        contains(PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture),
      );
    });

    test('remoteStockApplied + Hive compatível gera planReuseHiveSaleFuture',
        () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockApplied),
          ),
          hiveMatches: const [
            PdvV1HiveSaleMatch(
              hiveKey: 7,
              saleId: 'sale-orch-1',
              snapshotHash: 'snap-orch-1',
            ),
          ],
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.reuseExistingHiveSale);
      expect(plan.targetState, PdvV1JournalState.hiveSaleCompleted);
    });

    test('Hive duplicado gera manual', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockApplied),
          ),
          hiveMatches: const [
            PdvV1HiveSaleMatch(
              hiveKey: 1,
              saleId: 'sale-orch-1',
              snapshotHash: 'snap-orch-1',
            ),
            PdvV1HiveSaleMatch(
              hiveKey: 2,
              saleId: 'sale-orch-1',
              snapshotHash: 'snap-orch-1',
            ),
          ],
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('hash divergente gera manual', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockApplied),
          ),
          hiveMatches: const [
            PdvV1HiveSaleMatch(
              hiveKey: 1,
              saleId: 'sale-orch-1',
              snapshotHash: 'OUTRO',
            ),
          ],
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('fiado falha fechada', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(
              PdvV1JournalState.prepared,
              prep: _prep(isFiado: true),
            ),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
      expect(plan.reasonCode, 'scope_not_supported_7ab');
    });

    test('combo falha fechada', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(
              PdvV1JournalState.prepared,
              prep: _prep(hasCombo: true),
            ),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('edição falha fechada', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(
              PdvV1JournalState.prepared,
              prep: _prep(isEdicao: true),
            ),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('cancelamento falha fechada', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(
              PdvV1JournalState.prepared,
              prep: _prep(isCancelamento: true),
            ),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('operationCompleted com evidence inesperada gera manual', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.operationCompleted),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
      expect(plan.reasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);
    });

    test('operationCompleted sem evidence permanece noAction', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.operationCompleted),
          ),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.noAction);
    });

    test('manualInterventionRequired com evidence inesperada gera manual', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.manualInterventionRequired),
          ),
          evidence: _evidence(),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
      expect(plan.reasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);
    });

    test('manualInterventionRequired sem evidence permanece noAction', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.manualInterventionRequired),
          ),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.noAction);
    });

    test('três execuções iguais retornam JSON idêntico', () {
      final input = PdvV1RecoveryOrchestratorInput(
        journalOutcome: PdvV1JournalReadOutcome(
          record: _journal(PdvV1JournalState.remoteStockPending),
        ),
        evidence: _evidence(
          status: PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
        ),
      );
      final j1 = orchestrator.plan(input).toJson();
      final j2 = orchestrator.plan(input).toJson();
      final j3 = orchestrator.plan(input).toJson();
      expect(j1, j2);
      expect(j2, j3);
    });

    test('plannedActions é imutável', () {
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(
            record: _journal(PdvV1JournalState.remoteStockApplied),
          ),
        ),
      );
      expect(
        () => plan.plannedActions
            .add(PdvV1RecoveryPlannedAction.verifyMarkerAgain),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
