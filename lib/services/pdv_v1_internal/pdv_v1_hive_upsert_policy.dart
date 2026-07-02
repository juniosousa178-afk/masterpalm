import 'pdv_v1_internal_models.dart';

/// Decisão pura de upsert Hive por saleId — sem Box real.
enum PdvV1HiveUpsertDecision {
  insertOnce,
  reuseExisting,
  manualInterventionRequired,
}

class PdvV1HiveUpsertPolicyResult {
  const PdvV1HiveUpsertPolicyResult({
    required this.decision,
    this.hiveKey,
    this.reason = '',
  });

  final PdvV1HiveUpsertDecision decision;
  final int? hiveKey;
  final String reason;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        if (hiveKey != null) 'hiveKey': hiveKey,
        'reason': reason,
      };
}

bool pdvV1HiveKeyIsValid(int? hiveKey) {
  if (hiveKey == null) return false;
  return hiveKey >= 0;
}

bool pdvV1HiveMatchIsValid({
  required PdvV1HiveSaleMatch match,
  required String journalSaleId,
  required String journalSnapshotHash,
}) {
  if (!pdvV1HiveKeyIsValid(match.hiveKey)) return false;
  if (match.saleId.trim().isEmpty) return false;
  if (match.snapshotHash.trim().isEmpty) return false;
  if (match.saleId != journalSaleId) return false;
  if (match.snapshotHash != journalSnapshotHash) return false;
  return true;
}

List<Map<String, dynamic>> pdvV1CanonicalHiveMatchesJson(
  List<PdvV1HiveSaleMatch> matches,
) {
  final sorted = List<PdvV1HiveSaleMatch>.from(matches)
    ..sort((a, b) {
      final ka = (a.hiveKey ?? -1).compareTo(b.hiveKey ?? -1);
      if (ka != 0) return ka;
      final s = a.saleId.compareTo(b.saleId);
      if (s != 0) return s;
      return a.snapshotHash.compareTo(b.snapshotHash);
    });
  return sorted.map((m) => m.toJson()).toList(growable: false);
}

/// Política pura — não executa put/add em Hive.
class PdvV1HiveUpsertPolicy {
  const PdvV1HiveUpsertPolicy();

  PdvV1HiveUpsertPolicyResult decide({
    required String saleId,
    required String snapshotHash,
    required List<PdvV1HiveSaleMatch> found,
  }) {
    if (saleId.trim().isEmpty || snapshotHash.trim().isEmpty) {
      return const PdvV1HiveUpsertPolicyResult(
        decision: PdvV1HiveUpsertDecision.manualInterventionRequired,
        reason: 'saleId ou snapshotHash vazio',
      );
    }

    if (found.isNotEmpty) {
      for (final m in found) {
        if (!pdvV1HiveMatchIsValid(
          match: m,
          journalSaleId: saleId,
          journalSnapshotHash: snapshotHash,
        )) {
          return const PdvV1HiveUpsertPolicyResult(
            decision: PdvV1HiveUpsertDecision.manualInterventionRequired,
            reason: 'match_hive_invalido',
          );
        }
      }
    }

    if (found.isEmpty) {
      return const PdvV1HiveUpsertPolicyResult(
        decision: PdvV1HiveUpsertDecision.insertOnce,
      );
    }

    if (found.length > 1) {
      return const PdvV1HiveUpsertPolicyResult(
        decision: PdvV1HiveUpsertDecision.manualInterventionRequired,
        reason: 'múltiplas vendas com mesmo saleId',
      );
    }

    final match = found.first;
    if (match.snapshotHash == snapshotHash && match.saleId == saleId) {
      return PdvV1HiveUpsertPolicyResult(
        decision: PdvV1HiveUpsertDecision.reuseExisting,
        hiveKey: match.hiveKey,
      );
    }

    return const PdvV1HiveUpsertPolicyResult(
      decision: PdvV1HiveUpsertDecision.manualInterventionRequired,
      reason: 'hash divergente para mesmo saleId',
    );
  }
}
