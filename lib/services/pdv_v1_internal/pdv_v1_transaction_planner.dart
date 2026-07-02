import 'pdv_v1_internal_models.dart';

/// Decisão pura do planner de transação remota (sem Firebase/Hive).
enum PdvV1TransactionPlannerDecision {
  applyNewMarkerAndStock,
  alreadyAppliedSkipStock,
  manualInterventionRequired,
  invalidInput,
}

class PdvV1TransactionPlannerResult {
  const PdvV1TransactionPlannerResult({
    required this.decision,
    this.reason = '',
  });

  final PdvV1TransactionPlannerDecision decision;
  final String reason;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        'reason': reason,
      };

  @override
  bool operator ==(Object other) {
    return other is PdvV1TransactionPlannerResult &&
        other.decision == decision &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(decision, reason);
}

/// Planner determinístico — mesmas entradas → mesma saída.
class PdvV1TransactionPlanner {
  const PdvV1TransactionPlanner();

  PdvV1TransactionPlannerResult plan({
    required PdvV1PreparedSnapshot prepared,
    required PdvV1RemoteMarkerInput marker,
    required List<PdvV1TxItemFrozen> txItems,
    required String txItemsHash,
    required String snapshotHash,
    required String lojaId,
  }) {
    try {
      prepared.validateForFoundation7AA();
    } catch (e) {
      return PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.invalidInput,
        reason: e.toString(),
      );
    }

    if (txItemsHash.trim().isEmpty || snapshotHash.trim().isEmpty) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.invalidInput,
        reason: 'hash vazio',
      );
    }
    if (prepared.txItemsHash != txItemsHash ||
        prepared.snapshotHash != snapshotHash) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.invalidInput,
        reason: 'hash divergente do preparedSnapshot',
      );
    }
    if (prepared.lojaId != lojaId) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.invalidInput,
        reason: 'lojaId divergente',
      );
    }
    if (txItems.isEmpty) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.invalidInput,
        reason: 'txItems vazio',
      );
    }

    if (!marker.presente) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.applyNewMarkerAndStock,
      );
    }

    final compatible = marker.validoV1 &&
        marker.lojaId == prepared.lojaId &&
        marker.operationId == prepared.operationId &&
        marker.saleId == prepared.saleId &&
        marker.baixaAplicada &&
        marker.txItemsHash == prepared.txItemsHash;

    if (compatible) {
      return const PdvV1TransactionPlannerResult(
        decision: PdvV1TransactionPlannerDecision.alreadyAppliedSkipStock,
      );
    }

    return const PdvV1TransactionPlannerResult(
      decision: PdvV1TransactionPlannerDecision.manualInterventionRequired,
      reason: 'marcador existente incompatível',
    );
  }
}
