import '../models/release_governance/release_decision_snapshot.dart';
import 'release_governance_canonical_serializer.dart';

/// Builds deterministic release decision snapshot identities.
class ReleaseGovernanceIdentityBuilder {
  const ReleaseGovernanceIdentityBuilder({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  String buildSnapshotId({
    required String projectId,
    required String releaseId,
    required String policyId,
    required int policyVersion,
    required String releaseGovernanceFingerprint,
    required int schemaVersion,
  }) {
    return 'release-governance:$projectId:$releaseId:$policyId:$policyVersion:$releaseGovernanceFingerprint:$schemaVersion';
  }

  String buildSnapshotIdFromSnapshot(ReleaseDecisionSnapshot snapshot) {
    return buildSnapshotId(
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      releaseGovernanceFingerprint: snapshot.fingerprint,
      schemaVersion: snapshot.metadata.schemaVersion,
    );
  }

  String fingerprintForSnapshot(ReleaseDecisionSnapshot snapshot) {
    return _serializer.snapshotFingerprint(snapshot);
  }
}
