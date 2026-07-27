import '../../interfaces/persistent_artifact_provider.dart';
import '../../models/persistent_artifacts/persistent_artifact_evaluation_request.dart';
import '../../models/persistent_artifacts/persistent_artifact_evaluation_result.dart';
import '../../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../../models/persistent_artifacts/persistent_artifact_operation_models.dart';
import '../../models/persistent_artifacts/persistent_artifact_query.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_request.dart';
import '../../persistent_artifacts/backend/persistent_artifact_physical_operation_models.dart';
import '../../persistent_artifacts/backend/persistent_artifact_physical_correlation.dart';
import '../../persistent_artifacts/cloud/persistent_artifact_cloud_operation_models.dart';
import '../../persistent_artifacts/interfaces/persistent_artifact_content_handle.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

class ObservablePersistentArtifactProvider
    implements PersistentArtifactProvider {
  ObservablePersistentArtifactProvider({
    required PersistentArtifactProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final PersistentArtifactProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<PersistentArtifactEvaluationResult> evaluate(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _instrumentation.observe(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.evaluate,
        projectId: request.projectId,
        action: () => _delegate.evaluate(request),
      );

  @override
  Future<PersistentArtifactEvaluationResult> evaluateAndPublish(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _instrumentation.observe(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.evaluate,
        projectId: request.projectId,
        action: () => _delegate.evaluateAndPublish(request),
      );

  @override
  Future<void> publish(PersistentArtifactInfrastructureSnapshot snapshot) =>
      _instrumentation.observeVoid(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.publish,
        projectId: snapshot.projectId,
        action: () => _delegate.publish(snapshot),
      );

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> load(String snapshotId) =>
      _instrumentation.observe(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.load,
        action: () => _delegate.load(snapshotId),
      );

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> latest({
    required String projectId,
    String? releaseId,
  }) =>
      _instrumentation.observe(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.latest,
        projectId: projectId,
        action: () =>
            _delegate.latest(projectId: projectId, releaseId: releaseId),
      );

  @override
  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
    PersistentArtifactQuery query,
  ) =>
      _instrumentation.observe(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.query,
        projectId: query.projectId,
        action: () => _delegate.query(query),
      );

  @override
  Future<void> invalidate(String snapshotId) => _instrumentation.observeVoid(
        component: TelemetryComponent.persistentArtifacts,
        operation: TelemetryOperation.invalidate,
        action: () => _delegate.invalidate(snapshotId),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateIntegrity(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluateIntegrity(request);

  @override
  Future<PersistentArtifactOperationResult> evaluateRetention(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluateRetention(request);

  @override
  Future<PersistentArtifactOperationResult> evaluateReplication(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluateReplication(request);

  @override
  Future<PersistentArtifactOperationResult> evaluateAvailability(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluateAvailability(request);

  @override
  Future<PersistentArtifactOperationResult> evaluateDeletion(
    PersistentArtifactEvaluationRequest request, {
    bool force = false,
  }) =>
      _delegate.evaluateDeletion(request, force: force);

  @override
  Future<PersistentArtifactOperationResult> buildTombstone(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.buildTombstone(request);

  @override
  Future<PersistentArtifactOperationResult> evaluateLifecycle(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluateLifecycle(request);

  @override
  Future<PersistentArtifactOperationResult> evaluatePublication(
    PersistentArtifactEvaluationRequest request,
  ) =>
      _delegate.evaluatePublication(request);

  @override
  Future<PersistentArtifactContentHandle> writeContent({
    required String contentId,
    required List<int> bytes,
  }) =>
      _delegate.writeContent(contentId: contentId, bytes: bytes);

  @override
  Future<List<int>> readContent(PersistentArtifactContentHandle handle) =>
      _delegate.readContent(handle);

  @override
  Future<void> deleteContent(
    PersistentArtifactContentHandle handle, {
    bool force = false,
  }) =>
      _delegate.deleteContent(handle, force: force);

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> putCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:put:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.putCloudObject(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> getCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:get:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.load,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.getCloudObject(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> headCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:head:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.headCloudObject(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> cloudObjectExists(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:exists:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.cloudObjectExists(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectListResult> listCloudObjects(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:list:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.listCloudObjects(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> deleteCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:delete:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.delete,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.deleteCloudObject(request),
    );
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> copyCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:copy:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.copyCloudObject(request),
    );
  }

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> beginCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:multipart-begin:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.beginCloudMultipart(request),
    );
  }

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> uploadCloudPart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:multipart-upload:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.uploadCloudPart(request),
    );
  }

  @override
  Future<PersistentArtifactCloudMultipartOperationResult>
      completeCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:multipart-complete:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.completeCloudMultipart(request),
    );
  }

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> abortCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final correlation =
        'pa-cloud:multipart-abort:${request.backendId}:${request.requestId}';
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.delete,
      correlationId: correlation,
      projectId: request.backendId,
      action: () => _delegate.abortCloudMultipart(request),
    );
  }

  @override
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.forWrite(request);
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.writePhysicalContent(request),
    );
  }

  @override
  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.forRead(request);
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.load,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.readPhysicalContent(request),
    );
  }

  @override
  Future<ContentExistsResult> contentExists(ContentExistsRequest request) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'contentExists',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.contentExists(request),
    );
  }

  @override
  Future<ContentMetadataResult> contentMetadata(
      ContentMetadataRequest request) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'contentMetadata',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.contentMetadata(request),
    );
  }

  @override
  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'savePhysicalManifest',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.savePhysicalManifest(request),
    );
  }

  @override
  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'loadPhysicalManifest',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.load,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.loadPhysicalManifest(request),
    );
  }

  @override
  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'latestPhysicalManifest',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.latest,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.latestPhysicalManifest(request),
    );
  }

  @override
  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'queryPhysicalManifests',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.queryPhysicalManifests(request),
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'invalidatePhysicalManifest',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.invalidate,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.invalidatePhysicalManifest(request),
    );
  }

  @override
  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'resolvePhysicalLocation',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.resolve,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.resolvePhysicalLocation(request),
    );
  }

  @override
  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'quarantineContent',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.delete,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.quarantineContent(request),
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'inspectInterruptedOperations',
      backendId: backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation.correlationId,
      projectId: backendId,
      action: () => _delegate.inspectInterruptedOperations(backendId),
    );
  }

  @override
  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'inspectOrphanTemporaryObjects',
      backendId: backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.query,
      correlationId: correlation.correlationId,
      projectId: backendId,
      action: () => _delegate.inspectOrphanTemporaryObjects(backendId),
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'recoverTemporaryObject',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.save,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.recoverTemporaryObject(request),
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'discardTemporaryObject',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.delete,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.discardTemporaryObject(request),
    );
  }

  @override
  Future<PersistentArtifactPhysicalResult> unregisterBackend(
    UnregisterBackendRequest request,
  ) {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'unregisterBackend',
      backendId: request.backendId,
    );
    return _instrumentation.observe(
      component: TelemetryComponent.persistentArtifacts,
      operation: TelemetryOperation.invalidate,
      correlationId: correlation.correlationId,
      projectId: request.backendId,
      action: () => _delegate.unregisterBackend(request),
    );
  }
}
