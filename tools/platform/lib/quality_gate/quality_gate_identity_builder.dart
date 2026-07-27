import '../models/quality_gate/quality_gate_snapshot.dart';
import 'quality_gate_canonical_serializer.dart';

/// Builds deterministic quality gate snapshot identities.
class QualityGateIdentityBuilder {
  const QualityGateIdentityBuilder({
    QualityGateCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateCanonicalSerializer _serializer;

  String buildSnapshotId({
    required String projectId,
    required String policyId,
    required int policyVersion,
    required String qualityGateFingerprint,
    required int schemaVersion,
  }) {
    return 'quality-gate:$projectId:$policyId:$policyVersion:$qualityGateFingerprint:$schemaVersion';
  }

  String buildSnapshotIdFromSnapshot(QualityGateSnapshot snapshot) {
    return buildSnapshotId(
      projectId: snapshot.metadata.projectId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      qualityGateFingerprint: snapshot.metadata.qualityGateFingerprint,
      schemaVersion: snapshot.metadata.schemaVersion,
    );
  }

  String fingerprintForSnapshot(QualityGateSnapshot snapshot) {
    return _serializer.snapshotFingerprint(snapshot);
  }
}
