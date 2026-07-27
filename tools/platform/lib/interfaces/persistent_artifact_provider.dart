import '../models/persistent_artifacts/persistent_artifact_evaluation_request.dart';
import '../models/persistent_artifacts/persistent_artifact_evaluation_result.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../models/persistent_artifacts/persistent_artifact_operation_models.dart';
import '../models/persistent_artifacts/persistent_artifact_query.dart';
import '../persistent_artifacts/backend/persistent_artifact_physical_operations_provider.dart';
import '../persistent_artifacts/cloud/persistent_artifact_cloud_operations_provider.dart';
import '../persistent_artifacts/interfaces/persistent_artifact_content_handle.dart';

abstract interface class PersistentArtifactProvider
    implements
        PersistentArtifactPhysicalOperationsProvider,
        PersistentArtifactCloudOperationsProvider {
  Future<PersistentArtifactEvaluationResult> evaluate(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactEvaluationResult> evaluateAndPublish(
    PersistentArtifactEvaluationRequest request,
  );

  Future<void> publish(PersistentArtifactInfrastructureSnapshot snapshot);

  Future<PersistentArtifactInfrastructureSnapshot?> load(String snapshotId);

  Future<PersistentArtifactInfrastructureSnapshot?> latest({
    required String projectId,
    String? releaseId,
  });

  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
    PersistentArtifactQuery query,
  );

  Future<void> invalidate(String snapshotId);

  Future<PersistentArtifactOperationResult> evaluateIntegrity(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluateRetention(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluateReplication(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluateAvailability(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluateDeletion(
    PersistentArtifactEvaluationRequest request, {
    bool force = false,
  });

  Future<PersistentArtifactOperationResult> buildTombstone(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluateLifecycle(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactOperationResult> evaluatePublication(
    PersistentArtifactEvaluationRequest request,
  );

  Future<PersistentArtifactContentHandle> writeContent({
    required String contentId,
    required List<int> bytes,
  });

  Future<List<int>> readContent(PersistentArtifactContentHandle handle);

  Future<void> deleteContent(PersistentArtifactContentHandle handle,
      {bool force = false});
}
