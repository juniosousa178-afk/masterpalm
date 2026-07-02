import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_plan_semantics.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();
  const executor = PdvV1RecoveryExecutorSimulator();
  const semantics = PdvV1RecoveryPlanSemanticsValidator();
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('Fronteira journal malformado', () {
    PdvV1JournalReadOutcome malformedOutcome() {
      return PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {
          'accessToken': 'SECRET_TOKEN_VALUE',
          'password': 'p',
          'prepared': {
            'operationId': 'op-mal-bound',
            'saleId': 'sale-mal-bound',
            'lojaId': 'loja-mal-bound',
          },
        },
        storageKey: 'op-mal-bound',
      );
    }

    test('plano malformado não contém payload nem candidatos', () {
      final outcome = malformedOutcome();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final encoded = plan.toJson().toString();
      expect(encoded.contains('SECRET_TOKEN_VALUE'), isFalse);
      expect(encoded.contains('rawPayload'), isFalse);
      expect(encoded.contains('operationIdCandidate'), isFalse);
      expect(encoded.contains('sale-mal-bound'), isFalse);
      expect(plan.operationId, isEmpty);
      expect(plan.saleId, isEmpty);
      expect(plan.journalIdentity['identityAcceptedForRecovery'], isFalse);
      expect(semantics.validate(plan).valid, isTrue);
    });

    test('fingerprint malformado não contém candidatos nem payload', () {
      final outcome = malformedOutcome();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: outcome.record.prepared,
      );
      final encoded = fp.toJson().toString();
      expect(encoded.contains('op-mal-bound'), isFalse);
      expect(encoded.contains('sale-mal-bound'), isFalse);
      expect(encoded.contains('rawPayload'), isFalse);
      expect(fp.operationId, isEmpty);
      expect(fp.saleId, isEmpty);
      expect(fp.verificationStatus, 'malformed_boundary');
    });

    test('confirmação posterior para journal malformado é rejeitada', () {
      final outcome = malformedOutcome();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: outcome.record.prepared,
      );
      final confirmation = PdvV1SimulatedStageConfirmation(
        planFingerprint: fp,
        expectedJournalRevision: 0,
        operationId: '',
        saleId: '',
        lojaId: '',
        origem: '',
        protocolVersion: 0,
        snapshotHash: '',
        txItemsHash: '',
        expectedStateBefore: PdvV1JournalState.manualInterventionRequired,
        expectedTargetState: PdvV1JournalState.manualInterventionRequired,
        stage: PdvV1SimulatedConfirmationStage.hiveSaleUpsert,
        status: PdvV1SimulatedConfirmationStatus.confirmedCompatible,
      );
      final run = coordinator.run(
        PdvV1RecoverySimulationInput(
          journalOutcome: outcome,
          confirmation: confirmation,
        ),
      );
      expect(run.executionOutcome, isNull);
      expect(run.casApplyOutcome, isNull);
      expect(run.manualInterventionRequired, isTrue);
      expect(run.reasonCode, pdvV1MalformedRecoveryReasonCode);
    });

    test('CAS não altera estado de journal malformado', () {
      final outcome = malformedOutcome();
      final store = PdvV1RecoverySimulatedCasStore(outcome.record);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: outcome.record.prepared,
      );
      final execution = executor.simulate(
        PdvV1RecoveryExecutorInput(
          journalOutcome: outcome,
          plan: plan,
        ),
      );
      final before = store.snapshot.toJson();
      final cas = store.applySimulatedOutcome(
        expectedJournalRevision: 0,
        plan: plan,
        planFingerprint: fp,
        proposedExecutionOutcome: execution,
        semanticPlanValidated: true,
      );
      expect(cas.accepted, isFalse);
      expect(cas.rejectionReasonCode, 'journal_malformed');
      expect(store.snapshot.toJson(), before);
    });

    test('reasonCode do plano malformado é genérico sem payload', () {
      final outcome = malformedOutcome();
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      expect(plan.reasonCode, pdvV1MalformedRecoveryReasonCode);
      expect(plan.reasonCode.contains('SECRET'), isFalse);
    });
  });
}
