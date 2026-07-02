import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-req-1',
    saleId: 'sale-req-1',
    lojaId: 'loja-req-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-req-1',
    txItemsHash: 'tx-req-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _journal(PdvV1JournalState state, {bool malformed = false}) {
  final record = PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
  if (malformed) {
    return record.copyWith(isMalformedReadOnly: true);
  }
  return record;
}

PdvV1RemoteVerificationEvidence _evidence({
  PdvV1RemoteVerificationStatus status =
      PdvV1RemoteVerificationStatus.markerAbsentVerified,
}) {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: 'op-req-1',
    requestedSaleId: 'sale-req-1',
    requestedLojaId: 'loja-req-1',
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: 'tx-req-1',
    verificationStatus: status,
    optionalMarker: const PdvV1RemoteMarkerInput.ausente(),
    verificationSource: 'synthetic',
    verifiedAtEpochMs: 2,
  );
}

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('PdvV1RemoteVerificationRequirement', () {
    test('prepared exige evidência remota válida', () {
      final record = _journal(PdvV1JournalState.prepared);
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.requiredForRecovery,
      );
      final without = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(without.decision, PdvV1RecoveryDecision.invalidInput);
      expect(without.reasonCode, 'evidence_required');

      final withEvidence = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          evidence: _evidence(),
        ),
      );
      expect(withEvidence.decision, isNot(PdvV1RecoveryDecision.invalidInput));
    });

    test('remoteStockPending exige evidência remota válida', () {
      final record = _journal(PdvV1JournalState.remoteStockPending);
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.requiredForRecovery,
      );
      final without = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(without.reasonCode, 'evidence_required');
    });

    test('remoteStockApplied não exige evidence', () {
      final record = _journal(PdvV1JournalState.remoteStockApplied);
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.notRequiredForCurrentState,
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
          hiveMatches: const [],
        ),
      );
      expect(plan.decision, isNot(PdvV1RecoveryDecision.invalidInput));
      expect(plan.reasonCode, isNot('evidence_required'));
    });

    test('hiveSalePending não exige evidence', () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.notRequiredForCurrentState,
      );
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(plan.decision, PdvV1RecoveryDecision.requireExternalIntegration);
      expect(plan.decision, isNot(PdvV1RecoveryDecision.invalidInput));
    });

    test('saleSyncPending não exige evidence', () {
      final record = _journal(PdvV1JournalState.saleSyncPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(plan.decision, isNot(PdvV1RecoveryDecision.invalidInput));
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.notRequiredForCurrentState,
      );
    });

    test('effectsPending não exige evidence', () {
      final record = _journal(PdvV1JournalState.effectsPending);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(plan.decision, isNot(PdvV1RecoveryDecision.invalidInput));
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.notRequiredForCurrentState,
      );
    });

    test('effectsCompleted não exige evidence', () {
      final record = _journal(PdvV1JournalState.effectsCompleted);
      final plan = orchestrator.plan(
        PdvV1RecoveryOrchestratorInput(
          journalOutcome: PdvV1JournalReadOutcome(record: record),
        ),
      );
      expect(plan.decision, isNot(PdvV1RecoveryDecision.invalidInput));
      expect(
        pdvV1DeriveRemoteVerificationRequirement(record: record),
        PdvV1RemoteVerificationRequirement.notRequiredForCurrentState,
      );
    });

    test('manual e operationCompleted proíbem evidence', () {
      for (final state in [
        PdvV1JournalState.manualInterventionRequired,
        PdvV1JournalState.operationCompleted,
      ]) {
        final record = _journal(state);
        expect(
          pdvV1DeriveRemoteVerificationRequirement(record: record),
          PdvV1RemoteVerificationRequirement.prohibitedForMalformedOrTerminal,
        );
        final plan = orchestrator.plan(
          PdvV1RecoveryOrchestratorInput(
            journalOutcome: PdvV1JournalReadOutcome(record: record),
            evidence: _evidence(),
          ),
        );
        expect(plan.decision, PdvV1RecoveryDecision.manualInterventionRequired);
        expect(plan.reasonCode, pdvV1UnexpectedRemoteEvidenceReasonCode);
      }
    });

    test('notRequiredForCurrentState não é marker ausente nem marker aplicado',
        () {
      final record = _journal(PdvV1JournalState.hiveSalePending);
      expect(
        pdvV1EvidenceForRecoveryFingerprint(
            record: record, evidence: _evidence()),
        isNull,
      );
      final status = pdvV1VerificationStatusForFingerprint(
        currentState: record.state,
      );
      expect(status, pdvV1PostBaixaVerificationStatus);
      expect(status,
          isNot(PdvV1RemoteVerificationStatus.markerAbsentVerified.name));
      expect(status,
          isNot(PdvV1RemoteVerificationStatus.markerAppliedCompatible.name));
      expect(status,
          isNot(PdvV1RemoteVerificationStatus.markerDivergentOrInvalid.name));
      expect(
        status,
        isNot(PdvV1RemoteVerificationStatus.markerVerificationUnavailable.name),
      );
    });

    test('journal malformado proíbe evidence', () {
      final record = _journal(
        PdvV1JournalState.manualInterventionRequired,
        malformed: true,
      );
      expect(
        pdvV1DeriveRemoteVerificationRequirement(
          record: record,
          isMalformedReadOnly: true,
        ),
        PdvV1RemoteVerificationRequirement.prohibitedForMalformedOrTerminal,
      );
      expect(
        pdvV1EvidenceForRecoveryFingerprint(
          record: record,
          isMalformedReadOnly: true,
          evidence: _evidence(),
        ),
        isNull,
      );
    });
  });
}
