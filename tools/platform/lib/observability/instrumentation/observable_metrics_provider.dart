import '../../interfaces/metrics_provider.dart';
import '../../models/metrics/metrics_request.dart';
import '../../models/metrics/metrics_snapshot.dart';
import '../../models/observability/telemetry_enums.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [MetricsProvider].
class ObservableMetricsProvider implements MetricsProvider {
  ObservableMetricsProvider({
    required MetricsProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final MetricsProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Set<String> get supportedMetricIds => _delegate.supportedMetricIds;

  @override
  Future<MetricsResult> calculate(MetricsRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.calculate,
      projectId: request.projectId,
      action: () => _delegate.calculate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot.metadata.snapshotId;
        return [id];
      },
    );
  }

  @override
  Future<MetricsSnapshot?> load() {
    return _instrumentation.observe(
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(),
      resultingArtifactIds: (snapshot) {
        final id = snapshot?.metadata.snapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(MetricsSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<void> invalidate() {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(),
    );
  }
}
