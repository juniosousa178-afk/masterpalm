import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_request.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../observability/observability_collector.dart';
import '../observability/observability_engine.dart';
import '../observability/stores/observability_store.dart';
import '../observability/telemetry_canonical_serializer.dart';
import '../observability/telemetry_suppression_scope.dart';
import '../interfaces/observability_provider.dart';

/// Platform implementation of [ObservabilityProvider].
class PlatformObservabilityProvider implements ObservabilityProvider {
  PlatformObservabilityProvider({
    required ObservabilityEngine engine,
    required ObservabilityCollector collector,
    required ObservabilityStore store,
    required ObservabilityMode mode,
    TelemetryCanonicalSerializer? serializer,
  })  : _engine = engine,
        _collector = collector,
        _store = store,
        _mode = mode,
        _serializer = serializer ?? const TelemetryCanonicalSerializer();

  final ObservabilityEngine _engine;
  final ObservabilityCollector _collector;
  final ObservabilityStore _store;
  final ObservabilityMode _mode;
  final TelemetryCanonicalSerializer _serializer;

  @override
  bool get isEnabled => _mode != ObservabilityMode.disabled;

  @override
  Future<TelemetrySnapshotResult> capture(
    TelemetrySnapshotRequest request,
  ) async {
    if (!isEnabled) {
      return const TelemetrySnapshotResult(
        status: TelemetrySnapshotStatus.unavailable,
      );
    }
    return TelemetrySuppressionScope.runSuppressedAsync(
      () => _engine.capture(request),
    );
  }

  @override
  Future<void> emit(TelemetryEvent event) async {
    if (!isEnabled) return;
    await TelemetrySuppressionScope.runSuppressedAsync(
      () => _collector.emit(event),
    );
  }

  @override
  Future<void> publish(TelemetrySnapshot snapshot) async {
    if (!isEnabled) return;
    await TelemetrySuppressionScope.runSuppressedAsync(() async {
      final existing =
          await _store.loadSnapshot(snapshot.metadata.telemetrySnapshotId);
      if (existing != null) {
        final same = _serializer.canonicalizeSnapshot(existing) ==
            _serializer.canonicalizeSnapshot(snapshot);
        if (same) return;
      }
      await _store.saveSnapshot(snapshot);
    });
  }

  @override
  Future<TelemetrySnapshot?> load(String snapshotId) {
    if (!isEnabled) return Future.value();
    return TelemetrySuppressionScope.runSuppressedAsync(
      () => _store.loadSnapshot(snapshotId),
    );
  }

  @override
  Future<TelemetrySnapshot?> latest({
    String? projectId,
    String? correlationId,
  }) {
    if (!isEnabled) return Future.value();
    return TelemetrySuppressionScope.runSuppressedAsync(
      () => _store.latestSnapshot(
        projectId: projectId,
        correlationId: correlationId,
      ),
    );
  }

  @override
  Future<List<TelemetrySnapshot>> query(TelemetryQuery query) {
    if (!isEnabled) return Future.value(const []);
    return TelemetrySuppressionScope.runSuppressedAsync(
      () => _store.querySnapshots(query),
    );
  }

  @override
  Future<List<TelemetryEvent>> queryEvents(TelemetryEventQuery query) {
    if (!isEnabled) return Future.value(const []);
    return TelemetrySuppressionScope.runSuppressedAsync(
      () => Future.value(_collector.queryEvents(query)),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!isEnabled) return;
    await TelemetrySuppressionScope.runSuppressedAsync(
      () => _store.deleteSnapshot(snapshotId),
    );
  }
}
