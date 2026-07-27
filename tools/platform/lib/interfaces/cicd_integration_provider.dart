import '../models/cicd_integration/cicd_integration_query.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_result.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';

/// Public contract for CI/CD integration collection and publication.
abstract interface class CicdIntegrationProvider {
  Future<CicdIntegrationResult> evaluate(CicdIntegrationRequest request);

  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  );

  Future<void> publish(CicdIntegrationSnapshot snapshot);

  Future<CicdIntegrationSnapshot?> load(String snapshotId);

  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  });

  Future<List<CicdIntegrationSnapshot>> query(CicdIntegrationQuery query);

  Future<void> invalidate(String snapshotId);
}
