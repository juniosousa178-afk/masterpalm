import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/observability_engine.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_canonical_serializer.dart';
import 'package:masterpalm_platform/observability/telemetry_event_id_factory.dart';

/// Deterministic fixtures for observability tests.
class ObservabilityFixtures {
  const ObservabilityFixtures._();

  static const projectId = 'masterpalm-test';
  static const createdAt = '2026-01-02T12:00:00.000Z';
  static const referenceTime = '2026-01-02T12:00:00.000Z';
  static const correlationId = 'corr-op-1';
  static const operationId = 'op-metrics-calculate-1';

  static TelemetryEvent startedEvent({
    String startedAt = createdAt,
    String eventId = 'event-started',
    String correlationId = ObservabilityFixtures.correlationId,
    String operationId = ObservabilityFixtures.operationId,
  }) {
    return buildEvent(
      eventId: eventId,
      eventType: TelemetryEventType.operationStarted,
      status: TelemetryEventStatus.started,
      startedAt: startedAt,
      completedAt: null,
      duration: null,
      errors: const [],
      correlationId: correlationId,
      operationId: operationId,
    );
  }

  static TelemetryEvent completedEvent({
    String startedAt = createdAt,
    String completedAt = '2026-01-02T12:00:01.000Z',
    String eventId = 'event-completed',
    String correlationId = ObservabilityFixtures.correlationId,
    String operationId = ObservabilityFixtures.operationId,
    String fingerprint = 'fp-completed',
  }) {
    return buildEvent(
      eventId: eventId,
      eventType: TelemetryEventType.operationCompleted,
      status: TelemetryEventStatus.completed,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: const TelemetryDuration(durationMicroseconds: 1000),
      errors: const [],
      correlationId: correlationId,
      operationId: operationId,
      fingerprint: fingerprint,
    );
  }

  static TelemetryEvent buildEvent({
    required String eventId,
    required TelemetryEventType eventType,
    required TelemetryEventStatus status,
    required String startedAt,
    required String? completedAt,
    required TelemetryDuration? duration,
    required List<TelemetryError> errors,
    required String correlationId,
    required String operationId,
    String fingerprint = 'fp',
  }) {
    final base = TelemetryEvent(
      eventId: 'pending',
      eventType: eventType,
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.calculate,
      status: status,
      severity: TelemetrySeverity.info,
      correlation: TelemetryCorrelation(
        correlationId: correlationId,
        operationId: operationId,
        projectId: projectId,
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      errors: errors,
      metadata: TelemetryEventMetadata(
        eventSchemaVersion: TelemetryEventMetadata.currentSchemaVersion,
        eventFingerprint: fingerprint,
      ),
    );
    const serializer = TelemetryCanonicalSerializer();
    const idFactory = TelemetryEventIdFactory();
    final fp = serializer.eventFingerprint(base);
    final resolvedId = idFactory.create(
      component: TelemetryComponent.metrics.wireName,
      operation: TelemetryOperation.calculate.wireName,
      operationId: operationId,
      eventType: eventType.wireName,
      event: base,
    );
    return TelemetryEvent(
      eventId: eventId == 'pending' ? resolvedId : eventId,
      eventType: eventType,
      component: TelemetryComponent.metrics,
      operation: TelemetryOperation.calculate,
      status: status,
      severity: status == TelemetryEventStatus.failed
          ? TelemetrySeverity.error
          : TelemetrySeverity.info,
      correlation: TelemetryCorrelation(
        correlationId: correlationId,
        operationId: operationId,
        projectId: projectId,
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      errors: errors,
      metadata: TelemetryEventMetadata(
        eventSchemaVersion: TelemetryEventMetadata.currentSchemaVersion,
        eventFingerprint: fp,
      ),
    );
  }

  static Future<ObservabilityCollector> collectorWithSuccessOperation() async {
    final collector = ObservabilityCollector(
      sink: InMemoryTelemetryEventSink(),
    );
    await collector.emit(startedEvent());
    await collector.emit(completedEvent());
    return collector;
  }

  static Future<ObservabilityCollector>
      collectorWithIncompleteOperation() async {
    final collector = ObservabilityCollector(
      sink: InMemoryTelemetryEventSink(),
    );
    await collector.emit(
      startedEvent(
        correlationId: 'corr-incomplete',
        operationId: 'op-incomplete',
        eventId: 'started-incomplete',
      ),
    );
    return collector;
  }

  static Future<TelemetrySnapshot> buildSnapshot() async {
    final collector = await collectorWithSuccessOperation();
    final engine = ObservabilityEngine(collector: collector);
    final result = await engine.capture(
      TelemetrySnapshotRequest(
        createdAt: createdAt,
        referenceTime: referenceTime,
        correlationId: correlationId,
        projectId: projectId,
      ),
    );
    return result.snapshot!;
  }
}

extension TelemetryEventTestHelpers on TelemetryEvent {
  TelemetryEvent copyWithFailed() {
    return ObservabilityFixtures.buildEvent(
      eventId: eventId,
      eventType: TelemetryEventType.operationFailed,
      status: TelemetryEventStatus.failed,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      errors: const [],
      correlationId: correlation.correlationId,
      operationId: correlation.operationId,
      fingerprint: metadata.eventFingerprint,
    );
  }
}
