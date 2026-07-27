import 'persistent_artifact_physical_operation_models.dart';
import 'persistent_artifact_physical_operation_status.dart';
import 'persistent_artifact_physical_backend_bridge.dart';
import 'persistent_artifact_backend_environment_decision.dart';
import 'persistent_artifact_environment_gate.dart';
import '../persistent_artifact_backend_registry_impl.dart';

class PersistentArtifactPhysicalOperationsService {
  const PersistentArtifactPhysicalOperationsService({
    required PersistentArtifactBackendRegistry registry,
    this.runtimeEnvironment =
        PersistentArtifactRuntimeEnvironment.localReference,
  }) : _registry = registry;

  final PersistentArtifactBackendRegistry _registry;
  final PersistentArtifactRuntimeEnvironment runtimeEnvironment;

  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const WritePhysicalContentResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.writePhysicalContent(request),
    );
  }

  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const ReadPhysicalContentResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.readPhysicalContent(request),
    );
  }

  Future<ContentExistsResult> contentExists(
      ContentExistsRequest request) async {
    return _run(
      backendId: request.backendId,
      unavailable: const ContentExistsResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
        exists: false,
      ),
      action: (bridge) => bridge.contentExists(request),
    );
  }

  Future<ContentMetadataResult> contentMetadata(
    ContentMetadataRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const ContentMetadataResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.contentMetadata(request),
    );
  }

  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: SavePhysicalManifestResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
        manifestId: request.manifest.manifestId,
      ),
      action: (bridge) => bridge.savePhysicalManifest(request),
    );
  }

  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const LoadPhysicalManifestResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.loadPhysicalManifest(request),
    );
  }

  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const LoadPhysicalManifestResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.latestPhysicalManifest(request),
    );
  }

  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const QueryPhysicalManifestsResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.queryPhysicalManifests(request),
    );
  }

  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const PersistentArtifactPhysicalResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.invalidatePhysicalManifest(request),
    );
  }

  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const ResolvePhysicalLocationResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.resolvePhysicalLocation(request),
    );
  }

  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const QuarantineContentResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
        quarantined: false,
      ),
      action: (bridge) => bridge.quarantineContent(request),
    );
  }

  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) async {
    return _run(
      backendId: backendId,
      unavailable: const RecoveryInspectionResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.inspectInterruptedOperations(backendId),
    );
  }

  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) async {
    return _run(
      backendId: backendId,
      unavailable: const RecoveryInspectionResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.inspectOrphanTemporaryObjects(backendId),
    );
  }

  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const PersistentArtifactPhysicalResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.recoverTemporaryObject(request),
    );
  }

  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) async {
    return _run(
      backendId: request.backendId,
      unavailable: const PersistentArtifactPhysicalResult(
        status: PersistentArtifactPhysicalOperationStatus.unavailable,
      ),
      action: (bridge) => bridge.discardTemporaryObject(request),
    );
  }

  Future<T> _run<T extends PersistentArtifactPhysicalResult>({
    required String backendId,
    required T unavailable,
    required Future<T> Function(PersistentArtifactPhysicalBackendBridge bridge)
        action,
  }) async {
    if (!_registry.contains(backendId)) {
      return unavailable;
    }
    final decision = _registry.evaluateEnvironment(
      backendId,
      runtimeEnvironment: runtimeEnvironment,
    );
    if (!decision.allowed) {
      return _blocked<T>(decision, unavailable);
    }
    final bridge = _registry.bridgeOf(backendId);
    if (bridge == null) {
      return _disabled<T>(unavailable);
    }
    try {
      return await action(bridge);
    } catch (_) {
      return _failed<T>(unavailable);
    }
  }

  T _blocked<T extends PersistentArtifactPhysicalResult>(
    PersistentArtifactBackendEnvironmentDecision decision,
    T unavailable,
  ) {
    return _copyWithStatus(
      unavailable,
      PersistentArtifactPhysicalOperationStatus.environmentBlocked,
      metadata: {'reasonCode': decision.reasonCode},
    );
  }

  T _disabled<T extends PersistentArtifactPhysicalResult>(T unavailable) {
    return _copyWithStatus(
      unavailable,
      PersistentArtifactPhysicalOperationStatus.backendDisabled,
    );
  }

  T _failed<T extends PersistentArtifactPhysicalResult>(T unavailable) {
    return _copyWithStatus(
      unavailable,
      PersistentArtifactPhysicalOperationStatus.failed,
    );
  }

  T _copyWithStatus<T extends PersistentArtifactPhysicalResult>(
    T result,
    PersistentArtifactPhysicalOperationStatus status, {
    Map<String, String> metadata = const {},
  }) {
    if (result is WritePhysicalContentResult) {
      return WritePhysicalContentResult(
        status: status,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is ReadPhysicalContentResult) {
      return ReadPhysicalContentResult(
        status: status,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is ContentExistsResult) {
      return ContentExistsResult(
        status: status,
        exists: result.exists,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is ContentMetadataResult) {
      return ContentMetadataResult(
        status: status,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is SavePhysicalManifestResult) {
      return SavePhysicalManifestResult(
        status: status,
        manifestId: result.manifestId,
        idempotent: result.idempotent,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is LoadPhysicalManifestResult) {
      return LoadPhysicalManifestResult(
        status: status,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is QueryPhysicalManifestsResult) {
      return QueryPhysicalManifestsResult(
        status: status,
        manifests: result.manifests,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is ResolvePhysicalLocationResult) {
      return ResolvePhysicalLocationResult(
        status: status,
        locations: result.locations,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is QuarantineContentResult) {
      return QuarantineContentResult(
        status: status,
        quarantined: result.quarantined,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    if (result is RecoveryInspectionResult) {
      return RecoveryInspectionResult(
        status: status,
        references: result.references,
        issues: result.issues,
        metadata: {...result.metadata, ...metadata},
      ) as T;
    }
    return PersistentArtifactPhysicalResult(
      status: status,
      issues: result.issues,
      metadata: {...result.metadata, ...metadata},
    ) as T;
  }
}
