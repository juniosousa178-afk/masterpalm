import '../../models/observability/telemetry_event.dart';
import '../telemetry_canonical_serializer.dart';
import '../telemetry_exceptions.dart';
import '../telemetry_event_sink.dart';

/// In-memory telemetry event sink with idempotent emit.
class InMemoryTelemetryEventSink implements TelemetryEventSink {
  InMemoryTelemetryEventSink({TelemetryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const TelemetryCanonicalSerializer();

  final TelemetryCanonicalSerializer _serializer;
  final Map<String, TelemetryEvent> _events = {};

  List<TelemetryEvent> get events => _events.values.toList();

  @override
  Future<void> emit(TelemetryEvent event) async {
    final existing = _events[event.eventId];
    if (existing != null) {
      final same = _serializer.canonicalizeEvent(existing) ==
          _serializer.canonicalizeEvent(event);
      if (!same) {
        throw TelemetryConflictException(event.eventId);
      }
      return;
    }
    _events[event.eventId] = event;
  }

  void clear() => _events.clear();
}
