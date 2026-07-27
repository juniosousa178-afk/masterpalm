import '../../models/observability/telemetry_event.dart';
import '../../models/observability/telemetry_request.dart';
import '../../models/observability/telemetry_snapshot.dart';

/// Contract for in-memory observability persistence.
abstract interface class ObservabilityStore {
  Future<void> saveSnapshot(TelemetrySnapshot snapshot);

  Future<TelemetrySnapshot?> loadSnapshot(String snapshotId);

  Future<bool> snapshotExists(String snapshotId);

  Future<TelemetrySnapshot?> latestSnapshot({
    String? projectId,
    String? correlationId,
  });

  Future<List<TelemetrySnapshot>> querySnapshots(TelemetryQuery query);

  Future<void> deleteSnapshot(String snapshotId);

  Future<void> saveEvent(TelemetryEvent event);

  Future<TelemetryEvent?> loadEvent(String eventId);

  Future<bool> eventExists(String eventId);

  Future<List<TelemetryEvent>> queryEvents(TelemetryEventQuery query);
}
