import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-unexp-1',
    saleId: 'sale-unexp-1',
    lojaId: 'loja-unexp-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-unexp-1',
    txItemsHash: 'tx-unexp-1',
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
    requestedOperationId: 'op-unexp-1',
    requestedSaleId: 'sale-unexp-1',
    requestedLojaId: 'loja-unexp-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-unexp-1',
    verificationStatus: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
    optionalMarker: const PdvV1RemoteMarkerInput(
      presente: true,
      protocolVersion: pdvV1ProtocolVersion,
      origem: pdvV1OrigemProtocolValue,
      lojaId: 'loja-unexp-1',
      operationId: 'op-unexp-1',
      saleId: 'sale-unexp-1',
      baixaAplicada: true,
      txItemsHash: 'tx-unexp-1',
    ),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();
  const executor = PdvV1RecoveryExecutorSimulator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('Evidence remota inesperada pós-baixa', () {
    for (final state in [
      PdvV1JournalState.remoteStockApplied,
      PdvV1JournalState.hiveSalePending,
      PdvV1JournalState.saleSyncPending,
      PdvV1JournalState.effectsPending,
    ]) {
      test('evidence não nula em $state gera manual sem alterar CAS', () {
        final record = _journal(state);
        final store = PdvV1RecoverySimulatedCasStore(record);
        final before = store.snapshot.toJson();
        final plan = orchestrator.plan(
          PdvV1RecoveryOrchestratorInput(
            journalOutcome: PdvV1JournalReadOutcome(record: record),
            evidence: _evidence(),
          ),
        );
        expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
        expect(plan.reasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);

        final run = coordinator.run(
          PdvV1RecoverySimulationInput(
            store: store,
            journalOutcome: PdvV1JournalReadOutcome(record: record),
            evidence: _evidence(),
          ),
        );
        expect(run.manualInterventionRequired, isTrue);
        expect(run.executionOutcome?.transitionAuthorization, isNull);
        expect(store.snapshot.toJson(), before);
      });
    }

    test('evidence não nula em terminal gera manual sem alterar CAS', () {
      final record =
          _journal(PdvV1JournalState.operationCompleted, revision: 3);
      final store = PdvV1RecoverySimulatedCasStore(record);
      final before = store.snapshot.toJson();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      expect(plan.reasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);
      final outcome = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          plan: plan,
          context: PdvV1RecoveryExecutorContext(evidence: _evidence()),
        ),
      );
      expect(outcome.isManualIntervention, isTrue);
      expect(outcome.transitionAuthorization, isNull);
      coordinator.run(
        PdvV1RecoverySimulationInput(
          store: store,
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      expect(store.snapshot.toJson(), before);
      expect(store.snapshot.journalRevision, 3);
    });

    test('evidence nula pós-baixa é aceita', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.requireExternalIntegration);
      expect(plan.reasonCode, isNot(pdvV1UnexpectedRemoteEvidenceReasonCode));
    });
  });
}
