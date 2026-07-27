import '../../models/observability/telemetry_event.dart';
import '../telemetry_event_sink.dart';

/// No-op telemetry sink.
class NoOpTelemetryEventSink implements TelemetryEventSink {
  const NoOpTelemetryEventSink();

  @override
  Future<void> emit(TelemetryEvent event) async {}
}
