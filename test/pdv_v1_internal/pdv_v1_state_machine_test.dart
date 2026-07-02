import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_pipeline_foundation.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_state_machine.dart';

PdvV1JournalRecord _pendingRecord() {
  return PdvV1JournalRecord(
    prepared: PdvV1PreparedSnapshot(
      protocolVersion: pdvV1ProtocolVersion,
      operationId: 'op-p',
      saleId: 'sale-p',
      lojaId: 'loja-p',
      origem: PdvV1InternalOrigin.novaVendaPdvFuture,
      preparedAtEpochMs: 1,
      preparedSnapshot: {'a': 1},
      snapshotHash: 'snap',
      txItemsHash: 'tx',
      isFiado: false,
      hasCombo: false,
      isEdicao: false,
      isCancelamento: false,
    ),
    state: PdvV1JournalState.remoteStockPending,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

void main() {
  const sm = PdvV1StateMachine();
  final pipeline = PdvV1PipelineFoundation();

  group('PdvV1StateMachine', () {
    test('permite prepared → remoteStockPending', () {
      expect(
        sm.canTransition(
          PdvV1JournalState.prepared,
          PdvV1JournalState.remoteStockPending,
        ),
        isTrue,
      );
    });

    test('proíbe transição genérica remoteStockPending → prepared', () {
      expect(
        sm.canTransition(
          PdvV1JournalState.remoteStockPending,
          PdvV1JournalState.prepared,
        ),
        isFalse,
      );
      expect(
        () => sm.assertTransition(
          PdvV1JournalState.remoteStockPending,
          PdvV1JournalState.prepared,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
    });

    test('markerAbsentVerified permite prepared via reconciliação', () {
      final result = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerAbsentVerified,
      );
      expect(result.nextState, PdvV1JournalState.prepared);
      expect(result.deferred, isFalse);
      final record = sm.reconcileRemoteStockPendingRecord(
        _pendingRecord(),
        PdvV1RemoteStockResolution.markerAbsentVerified,
        updatedAtEpochMs: 2,
      );
      expect(record.state, PdvV1JournalState.prepared);
    });

    test('markerAppliedCompatible leva a remoteStockApplied', () {
      final result = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerAppliedCompatible,
      );
      expect(result.nextState, PdvV1JournalState.remoteStockApplied);
      final record = sm.reconcileRemoteStockPendingRecord(
        _pendingRecord(),
        PdvV1RemoteStockResolution.markerAppliedCompatible,
        updatedAtEpochMs: 2,
      );
      expect(record.state, PdvV1JournalState.remoteStockApplied);
    });

    test('markerDivergentOrInvalid leva a manualInterventionRequired', () {
      final result = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerDivergentOrInvalid,
      );
      expect(result.nextState, PdvV1JournalState.manualInterventionRequired);
    });

    test('markerVerificationUnavailable mantém pending deferido', () {
      final result = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerVerificationUnavailable,
      );
      expect(result.nextState, PdvV1JournalState.remoteStockPending);
      expect(result.deferred, isTrue);
      final record = sm.reconcileRemoteStockPendingRecord(
        _pendingRecord(),
        PdvV1RemoteStockResolution.markerVerificationUnavailable,
        updatedAtEpochMs: 2,
      );
      expect(record.state, PdvV1JournalState.remoteStockPending);
    });

    test('reconciliação repetida é idêntica', () {
      final r1 = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerAbsentVerified,
      );
      final r2 = sm.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerAbsentVerified,
      );
      expect(r1, r2);
      expect(r1.toJson(), r2.toJson());
    });

    test('pipeline não ignora reconciliação explícita', () {
      final viaPipeline = pipeline.reconcileRemoteStockPending(
        PdvV1RemoteStockResolution.markerAbsentVerified,
      );
      expect(viaPipeline.nextState, PdvV1JournalState.prepared);
      final blocked = pipeline.preValidate(
        prepared: _pendingRecord().prepared,
        transitionFrom: PdvV1JournalState.remoteStockPending,
        transitionTo: PdvV1JournalState.prepared,
      );
      expect(blocked.transitionValid, isFalse);
    });

    test('proíbe remoteStockApplied → prepared', () {
      expect(
        sm.canTransition(
          PdvV1JournalState.remoteStockApplied,
          PdvV1JournalState.prepared,
        ),
        isFalse,
      );
    });

    test('proíbe pular direto para operationCompleted', () {
      for (final from in PdvV1JournalState.values) {
        if (from == PdvV1JournalState.operationCompleted ||
            from == PdvV1JournalState.manualInterventionRequired ||
            from == PdvV1JournalState.effectsCompleted) {
          continue;
        }
        expect(
          sm.canTransition(from, PdvV1JournalState.operationCompleted),
          isFalse,
          reason: 'de $from',
        );
      }
      expect(
        sm.canTransition(
          PdvV1JournalState.effectsCompleted,
          PdvV1JournalState.operationCompleted,
        ),
        isTrue,
      );
    });

    test('operationCompleted é terminal', () {
      for (final to in PdvV1JournalState.values) {
        expect(
          sm.canTransition(PdvV1JournalState.operationCompleted, to),
          isFalse,
        );
      }
    });

    test('manualInterventionRequired é terminal', () {
      for (final to in PdvV1JournalState.values) {
        expect(
          sm.canTransition(
            PdvV1JournalState.manualInterventionRequired,
            to,
          ),
          isFalse,
        );
      }
    });

    test('assertTransition lança em transição inválida', () {
      expect(
        () => sm.assertTransition(
          PdvV1JournalState.prepared,
          PdvV1JournalState.hiveSaleCompleted,
        ),
        throwsA(isA<PdvV1InvalidTransitionError>()),
      );
    });
  });
}
