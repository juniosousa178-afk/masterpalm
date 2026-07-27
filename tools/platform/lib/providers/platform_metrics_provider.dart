import '../interfaces/metrics_provider.dart';
import '../models/metrics/metrics_request.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../metrics/metrics_engine.dart';

/// In-memory snapshot store for [MetricsProvider].
class InMemoryMetricsSnapshotStore {
  MetricsSnapshot? _snapshot;

  MetricsSnapshot? load() => _snapshot;

  void publish(MetricsSnapshot snapshot) {
    _snapshot = snapshot;
  }

  void invalidate() {
    _snapshot = null;
  }
}

/// Platform implementation of [MetricsProvider].
class PlatformMetricsProvider implements MetricsProvider {
  PlatformMetricsProvider({
    required MetricsEngine engine,
    InMemoryMetricsSnapshotStore? store,
  })  : _engine = engine,
        _store = store ?? InMemoryMetricsSnapshotStore();

  final MetricsEngine _engine;
  final InMemoryMetricsSnapshotStore _store;

  @override
  Set<String> get supportedMetricIds => _engine.supportedMetricIds;

  @override
  Future<MetricsResult> calculate(MetricsRequest request) async {
    final result = await _engine.calculate(request);
    if (result.status != MetricsResultStatus.failure) {
      await publish(result.snapshot);
    }
    return result;
  }

  @override
  Future<MetricsSnapshot?> load() async => _store.load();

  @override
  Future<void> publish(MetricsSnapshot snapshot) async {
    _store.publish(snapshot);
  }

  @override
  Future<void> invalidate() async {
    _store.invalidate();
  }
}
