import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_request.dart';
import 'telemetry_data_sanitizer.dart';
import 'telemetry_event_sink.dart';
import 'telemetry_exceptions.dart';
import 'telemetry_suppression_scope.dart';
import 'clocks/platform_clock.dart';
import 'telemetry_canonical_serializer.dart';
import 'telemetry_event_validator.dart';

/// Receives, validates, sanitizes and stores telemetry events.
class ObservabilityCollector {
  ObservabilityCollector({
    required TelemetryEventSink sink,
    PlatformClock? clock,
    TelemetryDataSanitizer? sanitizer,
    TelemetryEventValidator? validator,
    TelemetryCanonicalSerializer? serializer,
  })  : _sink = sink,
        _sanitizer = sanitizer ?? const TelemetryDataSanitizer(),
        _validator = validator ?? const TelemetryEventValidator(),
        _serializer = serializer ?? const TelemetryCanonicalSerializer();

  final TelemetryEventSink _sink;
  final TelemetryDataSanitizer _sanitizer;
  final TelemetryEventValidator _validator;
  final TelemetryCanonicalSerializer _serializer;
  final List<TelemetryEvent> _events = [];
  final List<String> _sinkFailures = [];

  List<TelemetryEvent> get events => List.unmodifiable(_events);
  List<String> get sinkFailures => List.unmodifiable(_sinkFailures);

  Future<void> emit(TelemetryEvent event) async {
    if (TelemetrySuppressionScope.isSuppressed) return;

    final sanitizedAttrs = _sanitizer.sanitizeAll(event.attributes);
    final sanitized = TelemetryEvent(
      eventId: event.eventId,
      eventType: event.eventType,
      component: event.component,
      operation: event.operation,
      status: event.status,
      severity: event.severity,
      correlation: event.correlation,
      startedAt: event.startedAt,
      completedAt: event.completedAt,
      duration: event.duration,
      sourceReferences: event.sourceReferences,
      attributes: sanitizedAttrs,
      warnings: event.warnings,
      errors: event.errors,
      metadata: event.metadata,
    );

    final validation = _validator.validate(sanitized);
    if (!validation.isValid) {
      throw TelemetryValidationException(validation.errors.join('; '));
    }

    try {
      await _sink.emit(sanitized);
    } on TelemetryConflictException {
      rethrow;
    } catch (e) {
      _sinkFailures.add(e.toString());
    }

    final existingIdx =
        _events.indexWhere((e) => e.eventId == sanitized.eventId);
    if (existingIdx >= 0) {
      final existing = _events[existingIdx];
      if (_serializer.canonicalizeEvent(existing) !=
          _serializer.canonicalizeEvent(sanitized)) {
        throw TelemetryConflictException(sanitized.eventId);
      }
      return;
    }
    _events.add(sanitized);
  }

  List<TelemetryEvent> queryEvents(TelemetryEventQuery query) {
    var results = _events.where((event) {
      if (query.correlationId != null &&
          event.correlation.correlationId != query.correlationId) {
        return false;
      }
      if (query.operationId != null &&
          event.correlation.operationId != query.operationId) {
        return false;
      }
      if (query.component != null && event.component != query.component) {
        return false;
      }
      if (query.projectId != null &&
          event.correlation.projectId != query.projectId) {
        return false;
      }
      if (query.from != null && event.startedAt.compareTo(query.from!) < 0) {
        return false;
      }
      if (query.to != null && event.startedAt.compareTo(query.to!) > 0) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final cmp = a.startedAt.compareTo(b.startedAt);
        if (cmp != 0) return cmp;
        return a.eventId.compareTo(b.eventId);
      });

    if (query.limit != null && results.length > query.limit!) {
      results = results.sublist(0, query.limit!);
    }
    return results;
  }

  void clear() => _events.clear();
}
