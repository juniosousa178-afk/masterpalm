import '../models/observability/telemetry_attributes.dart';
import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';
import 'clocks/platform_clock.dart';
import 'observability_collector.dart';
import 'telemetry_canonical_serializer.dart';
import 'telemetry_error_sanitizer.dart';
import 'telemetry_event_id_factory.dart';
import 'telemetry_timer.dart';

/// Lifecycle scope for a single instrumented operation.
class TelemetryOperationScope {
  TelemetryOperationScope({
    required this.collector,
    required this.clock,
    required this.timerFactory,
    required this.errorSanitizer,
    required this.idFactory,
    required this.serializer,
    required this.component,
    required this.operation,
    required this.correlation,
    required this.startedAt,
    this.parentEventId,
    this.severity = TelemetrySeverity.info,
    this.attributes = const [],
    this.sourceReferences = const [],
  })  : _timer = timerFactory.create(
          startMicroseconds: clock.nowMicrosecondsSinceEpoch(),
        ),
        _operationId = correlation.operationId;

  final ObservabilityCollector collector;
  final PlatformClock clock;
  final TelemetryTimerFactory timerFactory;
  final TelemetryErrorSanitizer errorSanitizer;
  final TelemetryEventIdFactory idFactory;
  final TelemetryCanonicalSerializer serializer;
  final TelemetryComponent component;
  final TelemetryOperation operation;
  final TelemetryCorrelation correlation;
  final String startedAt;
  final String? parentEventId;
  final TelemetrySeverity severity;
  final List<TelemetryAttribute> attributes;
  final List<TelemetrySourceReference> sourceReferences;

  final MonotonicTelemetryTimer _timer;
  final String _operationId;
  bool _finished = false;
  String? _startEventId;

  Future<void> start() async {
    final event = _buildEvent(
      eventType: TelemetryEventType.operationStarted,
      status: TelemetryEventStatus.started,
      completedAt: null,
      duration: null,
      errors: const [],
    );
    _startEventId = event.eventId;
    await collector.emit(event);
  }

  Future<void> complete({
    List<String> resultingArtifactIds = const [],
    List<TelemetryAttribute> attributes = const [],
    List<TelemetrySourceReference> sourceReferences = const [],
  }) async {
    if (_finished) {
      throw StateError('Operation scope already finished');
    }
    _finished = true;
    final completedAt = clock.nowUtcIso();
    _timer.stop(clock.nowMicrosecondsSinceEpoch());
    final duration = TelemetryDuration(
      durationMicroseconds: _timer.elapsedMicroseconds(),
    );
    final corr = TelemetryCorrelation(
      correlationId: correlation.correlationId,
      operationId: correlation.operationId,
      causationId: _startEventId,
      parentEventId: parentEventId,
      requestId: correlation.requestId,
      projectId: correlation.projectId,
      branch: correlation.branch,
      gitRef: correlation.gitRef,
      sourceArtifactIds: correlation.sourceArtifactIds,
      resultingArtifactIds: resultingArtifactIds,
    );
    await collector.emit(
      _buildEvent(
        eventType: TelemetryEventType.operationCompleted,
        status: TelemetryEventStatus.completed,
        completedAt: completedAt,
        duration: duration,
        errors: const [],
        correlation: corr,
        attributes: [...this.attributes, ...attributes],
        sourceReferences: [...this.sourceReferences, ...sourceReferences],
      ),
    );
  }

  Future<void> fail(
    Object error,
    StackTrace stackTrace, {
    List<TelemetryAttribute> attributes = const [],
  }) async {
    if (_finished) {
      throw StateError('Operation scope already finished');
    }
    _finished = true;
    final completedAt = clock.nowUtcIso();
    _timer.stop(clock.nowMicrosecondsSinceEpoch());
    final duration = TelemetryDuration(
      durationMicroseconds: _timer.elapsedMicroseconds(),
    );
    final sanitizedError = errorSanitizer.sanitize(
      error: error,
      component: component,
      operation: operation,
      stackTrace: stackTrace,
    );
    await collector.emit(
      _buildEvent(
        eventType: TelemetryEventType.operationFailed,
        status: TelemetryEventStatus.failed,
        completedAt: completedAt,
        duration: duration,
        errors: [sanitizedError],
        severity: TelemetrySeverity.error,
        attributes: [...this.attributes, ...attributes],
      ),
    );
  }

  TelemetryEvent _buildEvent({
    required TelemetryEventType eventType,
    required TelemetryEventStatus status,
    required String? completedAt,
    required TelemetryDuration? duration,
    required List<TelemetryError> errors,
    TelemetryCorrelation? correlation,
    List<TelemetryAttribute>? attributes,
    List<TelemetrySourceReference>? sourceReferences,
    TelemetrySeverity? severity,
  }) {
    final base = TelemetryEvent(
      eventId: 'pending',
      eventType: eventType,
      component: component,
      operation: operation,
      status: status,
      severity: severity ?? this.severity,
      correlation: correlation ?? this.correlation,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      attributes: attributes ?? this.attributes,
      warnings: const [],
      errors: errors,
      metadata: const TelemetryEventMetadata(
        eventSchemaVersion: TelemetryEventMetadata.currentSchemaVersion,
        eventFingerprint: 'pending',
      ),
    );
    final fingerprint = serializer.eventFingerprint(base);
    final eventId = idFactory.create(
      component: component.wireName,
      operation: operation.wireName,
      operationId: _operationId,
      eventType: eventType.wireName,
      event: base,
    );
    return TelemetryEvent(
      eventId: eventId,
      eventType: eventType,
      component: component,
      operation: operation,
      status: status,
      severity: severity ?? this.severity,
      correlation: correlation ?? this.correlation,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      attributes: attributes ?? this.attributes,
      warnings: const [],
      errors: errors,
      metadata: TelemetryEventMetadata(
        eventSchemaVersion: TelemetryEventMetadata.currentSchemaVersion,
        eventFingerprint: fingerprint,
      ),
    );
  }
}
