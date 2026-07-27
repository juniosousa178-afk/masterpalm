import '../../models/release_governance/release_decision_snapshot.dart';
import '../../models/release_governance/release_governance_query.dart';

/// Persistence contract for release decision snapshots.
abstract class ReleaseGovernanceStore {
  Future<void> save(ReleaseDecisionSnapshot snapshot);

  Future<ReleaseDecisionSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<ReleaseDecisionSnapshot>> query(ReleaseGovernanceQuery query);

  Future<void> invalidate(String snapshotId);

  Future<void> clear();

  Future<int> count();
}
