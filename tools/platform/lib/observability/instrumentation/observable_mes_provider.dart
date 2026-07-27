import '../../interfaces/mes_provider.dart';
import '../../models/mes/mes_policy.dart';
import '../../models/mes/mes_request.dart';
import '../../models/mes/mes_snapshot.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [MESProvider].
class ObservableMESProvider implements MESProvider {
  ObservableMESProvider({
    required MESProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final MESProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Set<String> get supportedPolicyIds => _delegate.supportedPolicyIds;

  @override
  MESPolicy? getPolicy(String policyId, {int? policyVersion}) =>
      _delegate.getPolicy(policyId, policyVersion: policyVersion);

  @override
  MESPolicy? getCandidatePolicy() => _delegate.getCandidatePolicy();

  @override
  MESPolicy? getActivePolicy() => _delegate.getActivePolicy();

  @override
  Future<MESResult> calculate(MESRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.calculate,
      projectId: request.projectId,
      action: () => _delegate.calculate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.mesSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(MESSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<MESSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null ? const [] : [snapshot.metadata.mesSnapshotId];
      },
    );
  }

  @override
  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        policyVersion: policyVersion,
      ),
      resultingArtifactIds: (snapshot) {
        return snapshot == null ? const [] : [snapshot.metadata.mesSnapshotId];
      },
    );
  }

  @override
  Future<MESEligibility> checkEligibility(MESRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.checkEligibility,
      projectId: request.projectId,
      action: () => _delegate.checkEligibility(request),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.mes,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
