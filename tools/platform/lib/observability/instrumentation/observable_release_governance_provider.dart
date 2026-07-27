import '../../interfaces/release_governance_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/release_governance/release_decision_snapshot.dart';
import '../../models/release_governance/release_governance_query.dart';
import '../../models/release_governance/release_governance_request.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [ReleaseGovernanceProvider].
class ObservableReleaseGovernanceProvider implements ReleaseGovernanceProvider {
  ObservableReleaseGovernanceProvider({
    required ReleaseGovernanceProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final ReleaseGovernanceProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<ReleaseGovernanceResult> evaluate(ReleaseGovernanceRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.snapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<ReleaseGovernanceResult> evaluateAndPublish(
    ReleaseGovernanceRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.snapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(ReleaseDecisionSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<ReleaseDecisionSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null ? const [] : [snapshot.metadata.snapshotId];
      },
    );
  }

  @override
  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        releaseId: releaseId,
        policyId: policyId,
      ),
      resultingArtifactIds: (snapshot) {
        return snapshot == null ? const [] : [snapshot.metadata.snapshotId];
      },
    );
  }

  @override
  Future<List<ReleaseDecisionSnapshot>> query(
    ReleaseGovernanceQuery query,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseGovernance,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
