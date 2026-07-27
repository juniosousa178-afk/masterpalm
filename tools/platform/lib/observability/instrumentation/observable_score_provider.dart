import '../../interfaces/score_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/score/score_policy.dart';
import '../../models/score/score_request.dart';
import '../../models/score/score_snapshot.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [ScoreProvider].
class ObservableScoreProvider implements ScoreProvider {
  ObservableScoreProvider({
    required ScoreProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final ScoreProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Set<String> get supportedPolicyIds => _delegate.supportedPolicyIds;

  @override
  ScorePolicy? getPolicy(String policyId) => _delegate.getPolicy(policyId);

  @override
  Future<ScoreResult> calculate(ScoreRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.score,
      operation: TelemetryOperation.calculate,
      projectId: request.projectId,
      action: () => _delegate.calculate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot.metadata.scoreSnapshotId;
        return [id];
      },
    );
  }

  @override
  Future<void> publish(EngineeringScoreSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.score,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<EngineeringScoreSnapshot?> load({required String snapshotId}) {
    return _instrumentation.observe(
      component: TelemetryComponent.score,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId: snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.scoreSnapshotId];
      },
    );
  }

  @override
  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.score,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(projectId: projectId, policyId: policyId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.scoreSnapshotId];
      },
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.score,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
