import '../../backend/persistent_artifact_physical_backend_bridge.dart';
import '../../backend/persistent_artifact_physical_operation_models.dart';
import '../../backend/persistent_artifact_physical_operation_status.dart';
import '../../backend/persistent_artifact_physical_status_mapper.dart';
import '../../../models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import '../../../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../../../models/persistent_artifacts/persistent_artifact_fingerprint.dart';
import 'secure_filesystem_content_store.dart';
import 'secure_filesystem_manifest_store.dart';
import 'secure_filesystem_quarantine_provider.dart';
import 'secure_filesystem_recovery_inspector.dart';

class SecureFilesystemPhysicalBackendBridge
    implements PersistentArtifactPhysicalBackendBridge {
  const SecureFilesystemPhysicalBackendBridge({
    required this.backendId,
    required this.contentStore,
    required this.manifestStore,
    required this.locationResolver,
    required this.quarantineProvider,
    required this.recoveryInspector,
  });

  final String backendId;
  final SecureFilesystemContentStore contentStore;
  final SecureFilesystemManifestStore manifestStore;
  final dynamic locationResolver;
  final SecureFilesystemQuarantineProvider quarantineProvider;
  final SecureFilesystemRecoveryInspector recoveryInspector;

  @override
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) async {
    final result = await contentStore.writeWithResult(
      descriptor: request.toDescriptor(),
      bytes: request.bytes,
    );
    final status = PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
      result.outcome,
    );
    final handle = status == PersistentArtifactPhysicalOperationStatus.succeeded
        ? await contentStore.writeContent(
            descriptor: request.toDescriptor(),
            bytes: request.bytes,
          )
        : null;
    return WritePhysicalContentResult(
      status: result.idempotent
          ? PersistentArtifactPhysicalOperationStatus.idempotent
          : status,
      handle: handle,
      digest: result.digest,
      sizeBytes: result.sizeBytes,
      idempotent: result.idempotent,
    );
  }

  @override
  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) async {
    final result = await contentStore.readWithResult(request.handle);
    return ReadPhysicalContentResult(
      status: PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
        result.outcome,
      ),
      bytes: result.bytes,
      digest: result.digest,
    );
  }

  @override
  Future<ContentExistsResult> contentExists(
      ContentExistsRequest request) async {
    final result = await contentStore.exists(request.handle);
    return ContentExistsResult(
      status: PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
        result.outcome,
      ),
      exists: result.exists,
    );
  }

  @override
  Future<ContentMetadataResult> contentMetadata(
    ContentMetadataRequest request,
  ) async {
    final read = await readPhysicalContent(
      ReadPhysicalContentRequest(
        backendId: request.backendId,
        handle: request.handle,
      ),
    );
    return ContentMetadataResult(
      status: read.status,
      digest: read.digest,
      sizeBytes: read.bytes?.length,
    );
  }

  @override
  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) async {
    final result = await manifestStore.saveManifestWithResult(request.manifest);
    return SavePhysicalManifestResult(
      status: result.idempotent
          ? PersistentArtifactPhysicalOperationStatus.idempotent
          : PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
              result.outcome,
            ),
      manifestId: result.manifestId,
      idempotent: result.idempotent,
    );
  }

  @override
  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) async {
    final result =
        await manifestStore.loadManifestWithResult(request.manifestId);
    return LoadPhysicalManifestResult(
      status: PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
        result.outcome,
      ),
      manifest: result.manifest,
    );
  }

  @override
  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) async {
    final manifest = await manifestStore.latest(
      artifactId: request.artifactId,
      namespace: request.namespace,
    );
    return LoadPhysicalManifestResult(
      status: manifest == null
          ? PersistentArtifactPhysicalOperationStatus.notFound
          : PersistentArtifactPhysicalOperationStatus.succeeded,
      manifest: manifest,
    );
  }

  @override
  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) async {
    final manifests = await manifestStore.query(request.query);
    return QueryPhysicalManifestsResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      manifests: manifests,
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) async {
    await manifestStore.invalidate(request.manifestId);
    return const PersistentArtifactPhysicalResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
    );
  }

  @override
  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) async {
    final locations = await locationResolver.resolveLocations(
      subject: request.subject,
      useLatest: request.useLatest,
    );
    return ResolvePhysicalLocationResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      locations: locations,
    );
  }

  @override
  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) async {
    final result =
        await quarantineProvider.deleteWithResult(handle: request.handle);
    return QuarantineContentResult(
      status: PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
        result.outcome,
      ),
      quarantined: result.quarantined,
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) async {
    final refs = await recoveryInspector.inspectInterruptedOperations();
    return RecoveryInspectionResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      references:
          refs.map((it) => RecoveryObjectReference(referenceId: it)).toList(),
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) async {
    final refs = await recoveryInspector.listOrphanTemporaryObjects();
    return RecoveryInspectionResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      references:
          refs.map((it) => RecoveryObjectReference(referenceId: it)).toList(),
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) async {
    final recovered =
        await recoveryInspector.recoverTemporaryObject(request.reference);
    return PersistentArtifactPhysicalResult(
      status: recovered
          ? PersistentArtifactPhysicalOperationStatus.succeeded
          : PersistentArtifactPhysicalOperationStatus.notFound,
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) async {
    final discarded =
        await recoveryInspector.discardTemporaryObject(request.reference);
    return PersistentArtifactPhysicalResult(
      status: discarded
          ? PersistentArtifactPhysicalOperationStatus.succeeded
          : PersistentArtifactPhysicalOperationStatus.notFound,
    );
  }
}

extension on WritePhysicalContentRequest {
  PersistentArtifactContentDescriptor toDescriptor() {
    return PersistentArtifactContentDescriptor(
      contentId: contentId,
      mediaType: 'application/octet-stream',
      format: PersistentArtifactFormat.binary,
      encoding: PersistentArtifactEncoding.none,
      compression: PersistentArtifactCompression.none,
      contentFingerprint: PersistentArtifactFingerprint.fromComparableJson(
        {'contentId': contentId},
      ),
      metadata: namespace == null ? const {} : {'namespace': namespace!},
    );
  }
}
