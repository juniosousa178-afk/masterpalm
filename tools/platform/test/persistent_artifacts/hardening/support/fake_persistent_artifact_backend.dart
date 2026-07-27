import 'package:masterpalm_platform/masterpalm_platform.dart';

class FakePersistentArtifactBackend
    implements PersistentArtifactPhysicalBackendBridge {
  int writes = 0;
  int reads = 0;
  int existsChecks = 0;
  int metadataChecks = 0;
  int saveManifestCalls = 0;
  int loadManifestCalls = 0;
  int latestManifestCalls = 0;
  int queryManifestCalls = 0;
  int invalidateManifestCalls = 0;
  int locationCalls = 0;
  int quarantineCalls = 0;
  int inspectInterruptedCalls = 0;
  int inspectOrphansCalls = 0;
  int recoverCalls = 0;
  int discardCalls = 0;
  bool fail = false;

  @override
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) async {
    writes++;
    if (fail) throw StateError('write-failed');
    return const WritePhysicalContentResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      digest: 'abc',
      sizeBytes: 3,
    );
  }

  @override
  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) async {
    reads++;
    if (fail) throw StateError('read-failed');
    return const ReadPhysicalContentResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      bytes: [1, 2, 3],
      digest: 'abc',
    );
  }

  @override
  Future<ContentExistsResult> contentExists(
      ContentExistsRequest request) async {
    existsChecks++;
    return const ContentExistsResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      exists: true,
    );
  }

  @override
  Future<ContentMetadataResult> contentMetadata(
    ContentMetadataRequest request,
  ) async {
    metadataChecks++;
    return const ContentMetadataResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      digest: 'abc',
      sizeBytes: 3,
    );
  }

  @override
  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) async {
    saveManifestCalls++;
    return SavePhysicalManifestResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      manifestId: request.manifest.manifestId,
    );
  }

  @override
  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) async {
    loadManifestCalls++;
    return const LoadPhysicalManifestResult(
      status: PersistentArtifactPhysicalOperationStatus.notFound,
    );
  }

  @override
  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) async {
    latestManifestCalls++;
    return const LoadPhysicalManifestResult(
      status: PersistentArtifactPhysicalOperationStatus.notFound,
    );
  }

  @override
  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) async {
    queryManifestCalls++;
    return const QueryPhysicalManifestsResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) async {
    invalidateManifestCalls++;
    return const PersistentArtifactPhysicalResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) async {
    locationCalls++;
    return const ResolvePhysicalLocationResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      locations: ['fake://location'],
    );
  }

  @override
  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) async {
    quarantineCalls++;
    return const QuarantineContentResult(
      status: PersistentArtifactPhysicalOperationStatus.quarantined,
      quarantined: true,
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) async {
    inspectInterruptedCalls++;
    return const RecoveryInspectionResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) async {
    inspectOrphansCalls++;
    return const RecoveryInspectionResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) async {
    recoverCalls++;
    return const PersistentArtifactPhysicalResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) async {
    discardCalls++;
    return const PersistentArtifactPhysicalResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }
}
