import '../../interfaces/dashboard_provider.dart';
import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_request.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [DashboardProvider].
class ObservableDashboardProvider implements DashboardProvider {
  ObservableDashboardProvider({
    required DashboardProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final DashboardProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Set<DashboardSectionType> get supportedSections =>
      _delegate.supportedSections;

  @override
  Future<DashboardResult> build(DashboardRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.build,
      projectId: request.projectId,
      action: () => _delegate.build(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.dashboardSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(DashboardSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<DashboardSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.dashboardSnapshotId];
      },
    );
  }

  @override
  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(projectId: projectId, branch: branch),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.dashboardSnapshotId];
      },
    );
  }

  @override
  Future<List<DashboardSnapshot>> query(DashboardQuery query) {
    return _instrumentation.observe(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.dashboard,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
