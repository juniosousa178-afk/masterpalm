import 'persistent_artifact_physical_operation_models.dart';

abstract interface class PersistentArtifactPhysicalOperationsProvider {
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  );

  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  );

  Future<ContentExistsResult> contentExists(ContentExistsRequest request);

  Future<ContentMetadataResult> contentMetadata(ContentMetadataRequest request);

  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  );

  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  );

  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  );

  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  );

  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  );

  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  );

  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  );

  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  );

  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  );

  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  );

  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  );

  Future<PersistentArtifactPhysicalResult> unregisterBackend(
    UnregisterBackendRequest request,
  );
}
