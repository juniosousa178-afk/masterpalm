import '../../interfaces/cicd_integration_provider.dart';
import '../../models/cicd_integration/cicd_integration_query.dart';
import '../../models/cicd_integration/cicd_integration_request.dart';
import '../../models/cicd_integration/cicd_integration_result.dart';
import '../../models/cicd_integration/cicd_integration_snapshot.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [CicdIntegrationProvider].
class ObservableCicdIntegrationProvider implements CicdIntegrationProvider {
  ObservableCicdIntegrationProvider({
    required CicdIntegrationProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final CicdIntegrationProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<CicdIntegrationResult> evaluate(CicdIntegrationRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.cicdIntegrationSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.cicdIntegrationSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.cicdIntegrationSnapshotId];
      },
    );
  }

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        releaseId: releaseId,
        pipelineIntegrationPolicyId: pipelineIntegrationPolicyId,
      ),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.cicdIntegrationSnapshotId];
      },
    );
  }

  @override
  Future<List<CicdIntegrationSnapshot>> query(CicdIntegrationQuery query) {
    return _instrumentation.observe(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.cicdIntegration,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
