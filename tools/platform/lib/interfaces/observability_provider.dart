import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_request.dart';
import '../models/observability/telemetry_snapshot.dart';

/// Public contract for platform observability operations.
abstract interface class ObservabilityProvider {
  Future<TelemetrySnapshotResult> capture(TelemetrySnapshotRequest request);

  Future<void> emit(TelemetryEvent event);

  Future<void> publish(TelemetrySnapshot snapshot);

  Future<TelemetrySnapshot?> load(String snapshotId);

  Future<TelemetrySnapshot?> latest({
    String? projectId,
    String? correlationId,
  });

  Future<List<TelemetrySnapshot>> query(TelemetryQuery query);

  Future<List<TelemetryEvent>> queryEvents(TelemetryEventQuery query);

  Future<void> invalidate(String snapshotId);

  bool get isEnabled;
}
