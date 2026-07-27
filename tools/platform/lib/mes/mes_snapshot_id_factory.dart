import '../models/mes/mes_snapshot.dart';

/// Deterministic MES snapshot ID factory.
class MESSnapshotIdFactory {
  const MESSnapshotIdFactory();

  String create({
    required String projectId,
    required String policyId,
    required int policyVersion,
    required String mesFingerprint,
  }) {
    return 'mes:$projectId:$policyId:$policyVersion:$mesFingerprint:${MESMetadata.currentSchemaVersion}';
  }
}
