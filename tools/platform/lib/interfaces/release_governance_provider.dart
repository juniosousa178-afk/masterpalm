import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_query.dart';
import '../models/release_governance/release_governance_request.dart';

/// Public contract for release governance evaluation and publication.
abstract interface class ReleaseGovernanceProvider {
  Future<ReleaseGovernanceResult> evaluate(ReleaseGovernanceRequest request);

  Future<ReleaseGovernanceResult> evaluateAndPublish(
    ReleaseGovernanceRequest request,
  );

  Future<void> publish(ReleaseDecisionSnapshot snapshot);

  Future<ReleaseDecisionSnapshot?> load(String snapshotId);

  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<ReleaseDecisionSnapshot>> query(ReleaseGovernanceQuery query);

  Future<void> invalidate(String snapshotId);
}
