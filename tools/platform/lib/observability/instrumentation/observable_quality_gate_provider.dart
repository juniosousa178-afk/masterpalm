import '../../interfaces/quality_gate_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/quality_gate/quality_gate_query.dart';
import '../../models/quality_gate/quality_gate_request.dart';
import '../../models/quality_gate/quality_gate_snapshot.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [QualityGateProvider].
class ObservableQualityGateProvider implements QualityGateProvider {
  ObservableQualityGateProvider({
    required QualityGateProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final QualityGateProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<QualityGateResult> evaluate(QualityGateRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.qualityGateSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<QualityGateResult> evaluateAndPublish(QualityGateRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.qualityGateSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(QualityGateSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.qualityGateSnapshotId];
      },
    );
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(projectId: projectId, policyId: policyId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.qualityGateSnapshotId];
      },
    );
  }

  @override
  Future<List<QualityGateSnapshot>> query(QualityGateQuery query) {
    return _instrumentation.observe(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.qualityGate,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
