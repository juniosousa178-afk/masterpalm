import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_backend_descriptor.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_request.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_result.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_staging_readiness_decision.dart';
import 'persistent_artifact_cloud_capability.dart';

abstract interface class PersistentArtifactCloudBackendBridge {
  Future<PersistentArtifactCloudBackendDescriptor> describe();

  Future<PersistentArtifactCloudStagingReadinessDecision> evaluateEnvironment();

  Future<Set<PersistentArtifactCloudCapability>> evaluateCapabilities();

  Future<PersistentArtifactCloudOperationResult> putObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> getObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> headObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<bool> objectExists(PersistentArtifactCloudOperationRequest request);

  Future<List<PersistentArtifactCloudOperationResult>> listObjects(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> deleteObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> copyObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> beginMultipart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> uploadPart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> completeMultipart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudOperationResult> abortMultipart(
    PersistentArtifactCloudOperationRequest request,
  );
}
