import '../../interfaces/history_provider.dart';
import '../../models/history/history_diff.dart';
import '../../models/history/history_request.dart';
import '../../models/history/history_snapshot.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [HistoryProvider].
class ObservableHistoryProvider implements HistoryProvider {
  ObservableHistoryProvider({
    required HistoryProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final HistoryProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<HistoryResult> capture(HistoryRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.capture,
      projectId: request.projectId,
      action: () => _delegate.capture(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot.metadata.historySnapshotId;
        return [id];
      },
    );
  }

  @override
  Future<void> publish(HistorySnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<HistorySnapshot?> loadById(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.load,
      action: () => _delegate.loadById(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.historySnapshotId];
      },
    );
  }

  @override
  Future<List<HistorySnapshot>> list(HistoryQuery query) {
    return _instrumentation.observe(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.list(query),
    );
  }

  @override
  Future<HistorySnapshot?> latest({required String projectId}) {
    return _instrumentation.observe(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(projectId: projectId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.historySnapshotId];
      },
    );
  }

  @override
  Future<HistoryDiff> compare({
    required String fromSnapshotId,
    required String toSnapshotId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.compare,
      action: () => _delegate.compare(
        fromSnapshotId: fromSnapshotId,
        toSnapshotId: toSnapshotId,
      ),
    );
  }

  @override
  Future<void> remove(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.history,
      operation: TelemetryOperation.delete,
      action: () => _delegate.remove(snapshotId),
    );
  }
}
