import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_journal_record.dart';

/// Resolução explícita de reconciliação de estoque remoto pendente.
enum PdvV1RemoteStockResolution {
  markerAbsentVerified,
  markerAppliedCompatible,
  markerDivergentOrInvalid,
  markerVerificationUnavailable,
}

/// Resultado puro da reconciliação — sem side effects.
class PdvV1RemoteStockReconcileResult {
  const PdvV1RemoteStockReconcileResult({
    required this.nextState,
    this.deferred = false,
    this.reason = '',
  });

  final PdvV1JournalState nextState;
  final bool deferred;
  final String reason;

  Map<String, dynamic> toJson() => {
        'nextState': nextState.name,
        'deferred': deferred,
        'reason': reason,
      };

  @override
  bool operator ==(Object other) {
    return other is PdvV1RemoteStockReconcileResult &&
        other.nextState == nextState &&
        other.deferred == deferred &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(nextState, deferred, reason);
}

/// Máquina de estados pura — fail-closed.
class PdvV1StateMachine {
  const PdvV1StateMachine();

  static const Map<PdvV1JournalState, Set<PdvV1JournalState>> _allowed = {
    PdvV1JournalState.prepared: {
      PdvV1JournalState.remoteStockPending,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.remoteStockPending: {
      PdvV1JournalState.remoteStockApplied,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.remoteStockApplied: {
      PdvV1JournalState.hiveSalePending,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.hiveSalePending: {
      PdvV1JournalState.hiveSaleCompleted,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.hiveSaleCompleted: {
      PdvV1JournalState.saleSyncPending,
      PdvV1JournalState.effectsPending,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.saleSyncPending: {
      PdvV1JournalState.saleSyncCompleted,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.saleSyncCompleted: {
      PdvV1JournalState.effectsPending,
      PdvV1JournalState.effectsCompleted,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.effectsPending: {
      PdvV1JournalState.effectsCompleted,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.effectsCompleted: {
      PdvV1JournalState.operationCompleted,
      PdvV1JournalState.manualInterventionRequired,
    },
    PdvV1JournalState.operationCompleted: {},
    PdvV1JournalState.manualInterventionRequired: {},
  };

  bool canTransition(PdvV1JournalState from, PdvV1JournalState to) {
    if (from == to) return false;
    if (pdvV1JournalStateIsTerminal(from)) return false;
    final next = _allowed[from];
    return next != null && next.contains(to);
  }

  void assertTransition(PdvV1JournalState from, PdvV1JournalState to) {
    if (from == PdvV1JournalState.remoteStockPending &&
        to == PdvV1JournalState.prepared) {
      throw PdvV1InvalidTransitionError(
        from.name,
        to.name,
        detail:
            'Use reconcileRemoteStockPending com markerAbsentVerified explícito.',
      );
    }
    if (!canTransition(from, to)) {
      throw PdvV1InvalidTransitionError(from.name, to.name);
    }
  }

  /// Reconciliação explícita — única via para sair de remoteStockPending.
  PdvV1RemoteStockReconcileResult reconcileRemoteStockPending(
    PdvV1RemoteStockResolution resolution,
  ) {
    switch (resolution) {
      case PdvV1RemoteStockResolution.markerAbsentVerified:
        return const PdvV1RemoteStockReconcileResult(
          nextState: PdvV1JournalState.prepared,
          reason: 'marcador ausente verificado',
        );
      case PdvV1RemoteStockResolution.markerAppliedCompatible:
        return const PdvV1RemoteStockReconcileResult(
          nextState: PdvV1JournalState.remoteStockApplied,
          reason: 'marcador compatível aplicado',
        );
      case PdvV1RemoteStockResolution.markerDivergentOrInvalid:
        return const PdvV1RemoteStockReconcileResult(
          nextState: PdvV1JournalState.manualInterventionRequired,
          reason: 'marcador divergente ou inválido',
        );
      case PdvV1RemoteStockResolution.markerVerificationUnavailable:
        return const PdvV1RemoteStockReconcileResult(
          nextState: PdvV1JournalState.remoteStockPending,
          deferred: true,
          reason: 'verificação remota indisponível',
        );
    }
  }

  PdvV1JournalRecord reconcileRemoteStockPendingRecord(
    PdvV1JournalRecord record,
    PdvV1RemoteStockResolution resolution, {
    required int updatedAtEpochMs,
  }) {
    if (record.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado não pode ser reconciliado automaticamente.',
      );
    }
    if (record.state != PdvV1JournalState.remoteStockPending) {
      throw PdvV1ValidationError(
        'Reconciliação remota exige estado remoteStockPending.',
      );
    }
    final decision = reconcileRemoteStockPending(resolution);
    if (decision.deferred) {
      return record;
    }
    if (decision.nextState != PdvV1JournalState.prepared) {
      assertTransition(record.state, decision.nextState);
    }
    return record.copyWith(
      state: decision.nextState,
      updatedAtEpochMs: updatedAtEpochMs,
      ultimoErroSanitizado: decision.reason,
      attempts: record.attempts + 1,
    );
  }

  PdvV1JournalRecord transitionRecord(
    PdvV1JournalRecord record,
    PdvV1JournalState to, {
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  }) {
    if (record.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado é somente leitura.',
      );
    }
    assertTransition(record.state, to);
    if (record.operationId != record.prepared.operationId) {
      throw PdvV1ValidationError('operationId inconsistente no record.');
    }
    return record.copyWith(
      state: to,
      updatedAtEpochMs: updatedAtEpochMs,
      ultimoErroSanitizado: ultimoErroSanitizado,
      vendaHiveKey: vendaHiveKey ?? record.vendaHiveKey,
      attempts: record.attempts + 1,
    );
  }
}
