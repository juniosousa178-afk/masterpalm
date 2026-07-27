import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/observability/clocks/fixed_platform_clock.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/observability_engine.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/sinks/no_op_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_canonical_serializer.dart';
import 'package:masterpalm_platform/observability/telemetry_data_sanitizer.dart';
import 'package:masterpalm_platform/observability/telemetry_event_validator.dart';
import 'package:masterpalm_platform/observability/telemetry_exceptions.dart';
import 'package:masterpalm_platform/observability/telemetry_operation_scope.dart';
import 'package:masterpalm_platform/observability/telemetry_platform_bootstrap.dart';
import 'package:masterpalm_platform/observability/telemetry_registry.dart';
import 'package:masterpalm_platform/observability/telemetry_suppression_scope.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:masterpalm_platform/observability/telemetry_error_sanitizer.dart';
import 'package:masterpalm_platform/observability/telemetry_event_id_factory.dart';
import 'package:masterpalm_platform/observability/stores/in_memory_observability_store.dart';
import 'package:masterpalm_platform/metrics/metrics_platform_bootstrap.dart';
import 'package:masterpalm_platform/history/history_platform_bootstrap.dart';
import 'package:masterpalm_platform/score/score_platform_bootstrap.dart';
import 'package:masterpalm_platform/mes/mes_platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/dashboard_platform_bootstrap.dart';
import 'package:masterpalm_platform/report/report_platform_bootstrap.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/observability_report_source.dart';
import 'package:masterpalm_platform/observability/telemetry_history_mapper.dart';
import 'package:test/test.dart';

import 'observability_fixtures.dart';

void main() {
  const createdAt = ObservabilityFixtures.createdAt;
  const referenceTime = ObservabilityFixtures.referenceTime;
  const projectId = ObservabilityFixtures.projectId;

  group('Telemetry models', () {
    test('TelemetryEvent round-trip JSON', () {
      final event = ObservabilityFixtures.completedEvent();
      final roundTrip = TelemetryEvent.fromJson(event.toJson());
      expect(roundTrip.eventId, event.eventId);
      expect(roundTrip.eventType, event.eventType);
    });

    test('TelemetrySnapshot round-trip JSON', () async {
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      final roundTrip = TelemetrySnapshot.fromJson(snapshot.toJson());
      expect(
        roundTrip.metadata.telemetrySnapshotId,
        snapshot.metadata.telemetrySnapshotId,
      );
    });

    test('string attribute round-trip', () {
      const attr = TelemetryStringAttribute(
        key: 'project',
        stringValue: projectId,
      );
      final parsed = TelemetryAttribute.fromJson(attr.toJson());
      expect(parsed, isA<TelemetryStringAttribute>());
    });
  });

  group('TelemetryEventValidator', () {
    const validator = TelemetryEventValidator();

    test('accepts valid completed event', () {
      final result = validator.validate(ObservabilityFixtures.completedEvent());
      expect(result.isValid, isTrue);
    });

    test('rejects failed without error', () {
      final event = ObservabilityFixtures.completedEvent().copyWithFailed();
      final result = validator.validate(event);
      expect(result.isValid, isFalse);
    });

    test('rejects completedAt before startedAt', () {
      final event = ObservabilityFixtures.completedEvent(
        completedAt: '2026-01-01T00:00:00.000Z',
        startedAt: '2026-01-02T00:00:00.000Z',
      );
      final result = validator.validate(event);
      expect(result.isValid, isFalse);
    });

    test('rejects empty correlationId', () {
      final base = ObservabilityFixtures.completedEvent();
      final event = TelemetryEvent(
        eventId: base.eventId,
        eventType: base.eventType,
        component: base.component,
        operation: base.operation,
        status: base.status,
        severity: base.severity,
        correlation: TelemetryCorrelation(
          correlationId: '',
          operationId: base.correlation.operationId,
        ),
        startedAt: base.startedAt,
        completedAt: base.completedAt,
        duration: base.duration,
        metadata: base.metadata,
      );
      expect(validator.validate(event).isValid, isFalse);
    });
  });

  group('TelemetryDataSanitizer', () {
    const sanitizer = TelemetryDataSanitizer();

    test('redacts sensitive path attribute', () {
      final attrs = sanitizer.sanitizeAll([
        TelemetryStringAttribute(
          key: 'path',
          stringValue: r'C:\Users\secret\file.dart',
          classification: TelemetryAttributeClassification.sensitive,
        ),
      ]);
      expect(attrs.first.redactionStatus, TelemetryRedactionStatus.redacted);
    });

    test('rejects prohibited secret attribute', () {
      expect(
        () => sanitizer.sanitizeAll([
          const TelemetryStringAttribute(
            key: 'password',
            stringValue: 'secret',
            classification: TelemetryAttributeClassification.prohibited,
          ),
        ]),
        throwsA(isA<TelemetryDataPolicyException>()),
      );
    });
  });

  group('TelemetryEventSink', () {
    test('NoOp sink accepts events', () async {
      const sink = NoOpTelemetryEventSink();
      await sink.emit(ObservabilityFixtures.completedEvent());
    });

    test('InMemory sink idempotent', () async {
      final sink = InMemoryTelemetryEventSink();
      final event = ObservabilityFixtures.completedEvent();
      await sink.emit(event);
      await sink.emit(event);
      expect(sink.events.length, 1);
    });

    test('InMemory sink conflict', () async {
      final sink = InMemoryTelemetryEventSink();
      await sink.emit(ObservabilityFixtures.completedEvent());
      final conflict = ObservabilityFixtures.completedEvent(
        eventId: ObservabilityFixtures.completedEvent().eventId,
        fingerprint: 'different',
      );
      expect(() => sink.emit(conflict),
          throwsA(isA<TelemetryConflictException>()));
    });
  });

  group('ObservabilityCollector', () {
    late ObservabilityCollector collector;

    setUp(() {
      collector = ObservabilityCollector(
        sink: InMemoryTelemetryEventSink(),
      );
    });

    test('emit and query by correlation', () async {
      await collector.emit(ObservabilityFixtures.startedEvent());
      await collector.emit(ObservabilityFixtures.completedEvent());
      final events = collector.queryEvents(
        const TelemetryEventQuery(correlationId: 'corr-op-1'),
      );
      expect(events.length, 2);
    });

    test('deterministic ordering', () async {
      await collector.emit(ObservabilityFixtures.completedEvent(
        startedAt: '2026-01-02T12:00:01.000Z',
        eventId: 'event-b',
      ));
      await collector.emit(ObservabilityFixtures.startedEvent(
        startedAt: '2026-01-02T12:00:00.000Z',
        eventId: 'event-a',
      ));
      final ids = collector
          .queryEvents(const TelemetryEventQuery())
          .map((e) => e.eventId)
          .toList();
      expect(ids.first, 'event-a');
    });
  });

  group('TelemetryOperationScope', () {
    test('complete lifecycle', () async {
      final clock = FixedPlatformClock(
        fixedIso: createdAt,
        fixedMicroseconds: 1000,
      );
      final collector = ObservabilityCollector(
        sink: InMemoryTelemetryEventSink(),
      );
      final scope = TelemetryOperationScope(
        collector: collector,
        clock: clock,
        timerFactory: const DefaultTelemetryTimerFactory(),
        errorSanitizer: const TelemetryErrorSanitizer(),
        idFactory: const TelemetryEventIdFactory(),
        serializer: const TelemetryCanonicalSerializer(),
        component: TelemetryComponent.metrics,
        operation: TelemetryOperation.calculate,
        correlation: const TelemetryCorrelation(
          correlationId: 'corr-scope',
          operationId: 'op-scope',
          projectId: projectId,
        ),
        startedAt: createdAt,
      );
      await scope.start();
      await scope.complete(resultingArtifactIds: const ['metrics-1']);
      expect(collector.events.length, 2);
      expect(collector.events.last.eventType,
          TelemetryEventType.operationCompleted);
    });

    test('fail preserves error model', () async {
      final clock = FixedPlatformClock(
        fixedIso: createdAt,
        fixedMicroseconds: 1000,
      );
      final collector = ObservabilityCollector(
        sink: InMemoryTelemetryEventSink(),
      );
      final scope = TelemetryOperationScope(
        collector: collector,
        clock: clock,
        timerFactory: const DefaultTelemetryTimerFactory(),
        errorSanitizer: const TelemetryErrorSanitizer(),
        idFactory: const TelemetryEventIdFactory(),
        serializer: const TelemetryCanonicalSerializer(),
        component: TelemetryComponent.metrics,
        operation: TelemetryOperation.calculate,
        correlation: const TelemetryCorrelation(
          correlationId: 'corr-fail',
          operationId: 'op-fail',
        ),
        startedAt: createdAt,
      );
      await scope.start();
      await scope.fail(StateError('boom'), StackTrace.current);
      expect(collector.events.last.errors, isNotEmpty);
      expect(collector.events.last.errors.first.redacted, isTrue);
    });

    test('double complete rejected', () async {
      final clock = FixedPlatformClock(
        fixedIso: createdAt,
        fixedMicroseconds: 1000,
      );
      final collector = ObservabilityCollector(
        sink: InMemoryTelemetryEventSink(),
      );
      final scope = TelemetryOperationScope(
        collector: collector,
        clock: clock,
        timerFactory: const DefaultTelemetryTimerFactory(),
        errorSanitizer: const TelemetryErrorSanitizer(),
        idFactory: const TelemetryEventIdFactory(),
        serializer: const TelemetryCanonicalSerializer(),
        component: TelemetryComponent.metrics,
        operation: TelemetryOperation.calculate,
        correlation: const TelemetryCorrelation(
          correlationId: 'corr-double',
          operationId: 'op-double',
        ),
        startedAt: createdAt,
      );
      await scope.start();
      await scope.complete();
      expect(() => scope.complete(), throwsStateError);
    });
  });

  group('ObservabilityEngine', () {
    test('snapshot success with complete operation', () async {
      final collector =
          await ObservabilityFixtures.collectorWithSuccessOperation();
      final engine = ObservabilityEngine(collector: collector);
      final result = await engine.capture(
        TelemetrySnapshotRequest(
          createdAt: createdAt,
          referenceTime: referenceTime,
          correlationId: 'corr-op-1',
          projectId: projectId,
        ),
      );
      expect(result.status, TelemetrySnapshotStatus.success);
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.summary.successCount, 1);
    });

    test('snapshot unavailable without events', () async {
      final engine = ObservabilityEngine(
        collector: ObservabilityCollector(sink: const NoOpTelemetryEventSink()),
      );
      final result = await engine.capture(
        TelemetrySnapshotRequest(
          createdAt: createdAt,
          referenceTime: referenceTime,
          correlationId: 'missing',
          projectId: projectId,
        ),
      );
      expect(result.status, TelemetrySnapshotStatus.unavailable);
    });

    test('snapshot partial with incomplete operation', () async {
      final collector =
          await ObservabilityFixtures.collectorWithIncompleteOperation();
      final engine = ObservabilityEngine(collector: collector);
      final result = await engine.capture(
        TelemetrySnapshotRequest(
          createdAt: createdAt,
          referenceTime: referenceTime,
          correlationId: 'corr-incomplete',
          projectId: projectId,
        ),
      );
      expect(result.status, TelemetrySnapshotStatus.partial);
      expect(result.snapshot!.coverage.incompleteOperationCount, 1);
    });

    test('deterministic snapshot ID across event order', () async {
      final engine = ObservabilityEngine(
        collector: await ObservabilityFixtures.collectorWithSuccessOperation(),
      );
      final request = TelemetrySnapshotRequest(
        createdAt: createdAt,
        referenceTime: referenceTime,
        correlationId: 'corr-op-1',
        projectId: projectId,
      );
      final a = await engine.capture(request);
      final b = await engine.capture(
        TelemetrySnapshotRequest(
          createdAt: '2026-01-03T00:00:00.000Z',
          referenceTime: referenceTime,
          correlationId: 'corr-op-1',
          projectId: projectId,
        ),
      );
      expect(
        a.snapshot!.metadata.telemetrySnapshotId,
        b.snapshot!.metadata.telemetrySnapshotId,
      );
    });

    test('rejects inverted timeRange', () async {
      final engine = ObservabilityEngine(
        collector: ObservabilityCollector(sink: const NoOpTelemetryEventSink()),
      );
      final result = await engine.capture(
        TelemetrySnapshotRequest(
          createdAt: createdAt,
          referenceTime: referenceTime,
          projectId: projectId,
          timeRange: const TelemetryTimeRange(
            from: '2026-02-01',
            to: '2026-01-01',
          ),
        ),
      );
      expect(result.status, TelemetrySnapshotStatus.failure);
    });
  });

  group('ObservabilityStore', () {
    test('save and load snapshot', () async {
      final store = InMemoryObservabilityStore();
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      await store.saveSnapshot(snapshot);
      final loaded = await store.loadSnapshot(
        snapshot.metadata.telemetrySnapshotId,
      );
      expect(loaded, isNotNull);
    });

    test('conflict on divergent payload', () async {
      final store = InMemoryObservabilityStore();
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      await store.saveSnapshot(snapshot);
      final conflict = TelemetrySnapshot.fromJson(snapshot.toJson());
      final meta = TelemetrySnapshotMetadata(
        telemetrySnapshotId: snapshot.metadata.telemetrySnapshotId,
        telemetrySchemaVersion: snapshot.metadata.telemetrySchemaVersion,
        telemetryCalculationVersion:
            snapshot.metadata.telemetryCalculationVersion,
        telemetryCanonicalizationVersion:
            snapshot.metadata.telemetryCanonicalizationVersion,
        createdAt: snapshot.metadata.createdAt,
        scopeFingerprint: snapshot.metadata.scopeFingerprint,
        telemetryFingerprint: 'different',
        status: snapshot.metadata.status,
        compatibility: snapshot.metadata.compatibility,
        eventCount: snapshot.metadata.eventCount,
        warningCount: snapshot.metadata.warningCount,
        errorCount: snapshot.metadata.errorCount,
      );
      final divergent = TelemetrySnapshot(
        metadata: meta,
        events: snapshot.events,
        summary: snapshot.summary,
        componentSummaries: snapshot.componentSummaries,
        operationSummaries: snapshot.operationSummaries,
        failureSummary: snapshot.failureSummary,
        durationSummary: snapshot.durationSummary,
        coverage: snapshot.coverage,
        compatibility: snapshot.compatibility,
        sourceReferences: snapshot.sourceReferences,
        warnings: snapshot.warnings,
        errors: snapshot.errors,
        limitations: snapshot.limitations,
      );
      expect(
        () => store.saveSnapshot(divergent),
        throwsA(isA<TelemetryConflictException>()),
      );
    });
  });

  group('TelemetryRegistry', () {
    test('registers foundation and freezes', () {
      final registry = TelemetryRegistry();
      TelemetryRegistry.registerFoundation(registry);
      registry.freeze();
      expect(registry.isFrozen, isTrue);
      expect(
        () => registry.registerComponent(TelemetryComponent.ast),
        throwsStateError,
      );
    });
  });

  group('TelemetrySuppressionScope', () {
    test('prevents recursive depth growth', () {
      var depthDuring = 0;
      TelemetrySuppressionScope.runSuppressed(() {
        TelemetrySuppressionScope.runSuppressed(() {
          depthDuring = 2;
        });
      });
      expect(depthDuring, 2);
      expect(TelemetrySuppressionScope.isSuppressed, isFalse);
    });
  });

  group('Platform bootstrap', () {
    test('registers ObservabilityProvider', () {
      final registry = ProviderRegistry();
      MetricsPlatformBootstrap.register(registry: registry);
      HistoryPlatformBootstrap.register(registry: registry);
      ScorePlatformBootstrap.register(registry: registry);
      MESPlatformBootstrap.register(registry: registry);
      DashboardPlatformBootstrap.register(registry: registry);
      ReportPlatformBootstrap.register(registry: registry);
      TelemetryPlatformBootstrap.register(
        registry: registry,
        mode: ObservabilityMode.full,
      );
      final provider = registry.resolve<ObservabilityProvider>();
      expect(provider.isEnabled, isTrue);
    });

    test('disabled mode keeps provider but no decoration required', () {
      final registry = ProviderRegistry();
      MetricsPlatformBootstrap.register(registry: registry);
      TelemetryPlatformBootstrap.register(
        registry: registry,
        mode: ObservabilityMode.disabled,
      );
      expect(registry.resolve<ObservabilityProvider>().isEnabled, isFalse);
    });
  });

  group('Report integration', () {
    test('platformObservability report renders coverage', () async {
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      final engine = ReportEngine();
      final result = await engine.generate(
        ReportRequest(
          reportType: ReportType.platformObservability,
          projectId: projectId,
          telemetrySnapshot: snapshot.toJson(),
        ),
      );
      expect(result.document.metadata.reportType,
          ReportType.platformObservability);
      expect(
        result.document.sections
            .any((s) => s.id == 'platform-observability-summary'),
        isTrue,
      );
    });

    test('ObservabilityReportSource maps snapshot', () async {
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      final data = const ObservabilityReportSource().fromSnapshot(snapshot);
      expect(data.eventCount, greaterThan(0));
      expect(data.componentSummaries, isNotEmpty);
    });
  });

  group('History integration', () {
    test('telemetry artifact mapper', () async {
      final snapshot = await ObservabilityFixtures.buildSnapshot();
      final artifact = const TelemetryHistoryMapper().toArtifact(snapshot);
      expect(artifact.artifactType, HistoryArtifactType.telemetry);
    });

    test('structural comparison detects event count change', () async {
      final from = await ObservabilityFixtures.buildSnapshot();
      final toSnapshot = await ObservabilityFixtures.buildSnapshot();
      final to = TelemetrySnapshot.fromJson(toSnapshot.toJson());
      final changes = const TelemetryHistoryMapper().compare(from, to);
      expect(changes, isA<List<HistoryChange>>());
    });
  });

  group('Canonical serializer', () {
    test('event fingerprint stable for same event', () {
      const serializer = TelemetryCanonicalSerializer();
      final event = ObservabilityFixtures.completedEvent();
      expect(
        serializer.eventFingerprint(event),
        serializer.eventFingerprint(event),
      );
    });

    test('rejects NaN in canonicalization', () {
      const serializer = TelemetryCanonicalSerializer();
      expect(
        () => serializer.fingerprintFromString('nan-test'),
        returnsNormally,
      );
    });
  });
}
