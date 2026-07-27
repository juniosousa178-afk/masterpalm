import '../../models/cicd_integration/cicd_integration_query.dart';
import '../../models/cicd_integration/cicd_integration_snapshot.dart';

/// Persistence contract for CI/CD integration snapshots.
abstract class CicdIntegrationStore {
  Future<void> save(CicdIntegrationSnapshot snapshot);

  Future<CicdIntegrationSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  });

  Future<List<CicdIntegrationSnapshot>> query(CicdIntegrationQuery query);

  Future<void> invalidate(String snapshotId);

  Future<void> clear();

  Future<int> count();
}
