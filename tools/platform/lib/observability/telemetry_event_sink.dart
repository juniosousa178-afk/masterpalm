import '../models/observability/telemetry_event.dart';

/// Contract for emitting telemetry events.
abstract interface class TelemetryEventSink {
  Future<void> emit(TelemetryEvent event);
}
