import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_request.dart';
import 'persistent_artifact_cloud_operation_models.dart';

abstract interface class PersistentArtifactCloudOperationsProvider {
  Future<PersistentArtifactCloudObjectMetadataResult> putCloudObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectMetadataResult> getCloudObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectMetadataResult> headCloudObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectMetadataResult> cloudObjectExists(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectListResult> listCloudObjects(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectMetadataResult> deleteCloudObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudObjectMetadataResult> copyCloudObject(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudMultipartOperationResult> beginCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudMultipartOperationResult> uploadCloudPart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudMultipartOperationResult>
      completeCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  );

  Future<PersistentArtifactCloudMultipartOperationResult> abortCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  );
}
