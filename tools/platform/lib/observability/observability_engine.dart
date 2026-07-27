import 'dart:convert';

import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_request.dart';
import '../models/observability/telemetry_snapshot.dart';
import 'observability_collector.dart';
import 'telemetry_canonical_serializer.dart';
import 'telemetry_compatibility_checker.dart';
import 'telemetry_event_id_factory.dart';
import 'telemetry_snapshot_validator.dart';
import 'telemetry_summary_builder.dart';

/// Stateless engine composing telemetry snapshots from collected events.
class ObservabilityEngine {
  ObservabilityEngine({
    required ObservabilityCollector collector,
    TelemetryCanonicalSerializer? serializer,
    TelemetrySummaryBuilder? summaryBuilder,
    TelemetryCompatibilityChecker? compatibilityChecker,
    TelemetrySnapshotValidator? snapshotValidator,
    TelemetrySnapshotIdFactory? idFactory,
  })  : _collector = collector,
        _serializer = serializer ?? const TelemetryCanonicalSerializer(),
        _summaryBuilder = summaryBuilder ?? const TelemetrySummaryBuilder(),
        _compatibilityChecker =
            compatibilityChecker ?? const TelemetryCompatibilityChecker(),
        _snapshotValidator =
            snapshotValidator ?? const TelemetrySnapshotValidator(),
        _idFactory = idFactory ?? const TelemetrySnapshotIdFactory();

  final ObservabilityCollector _collector;
  final TelemetryCanonicalSerializer _serializer;
  final TelemetrySummaryBuilder _summaryBuilder;
  final TelemetryCompatibilityChecker _compatibilityChecker;
  final TelemetrySnapshotValidator _snapshotValidator;
  final TelemetrySnapshotIdFactory _idFactory;

  Future<TelemetrySnapshotResult> capture(
    TelemetrySnapshotRequest request,
  ) async {
    final validationErrors = _validateRequest(request);
    if (validationErrors.isNotEmpty) {
      return TelemetrySnapshotResult(
        status: TelemetrySnapshotStatus.failure,
        errors: validationErrors
            .map(
              (e) => TelemetryError(
                errorCode: 'request.invalid',
                errorType: 'ValidationError',
                message: e,
                component: TelemetryComponent.observability,
                operation: TelemetryOperation.compose,
                classification: TelemetryAttributeClassification.internal,
                originalErrorAvailable: false,
                redacted: false,
              ),
            )
            .toList(),
      );
    }

    try {
      final events = _selectEvents(request);
      if (events.isEmpty) {
        return const TelemetrySnapshotResult(
          status: TelemetrySnapshotStatus.unavailable,
        );
      }

      final compatibility = _compatibilityChecker.evaluate(events);
      if (request.strictCompatibility &&
          compatibility == TelemetryCompatibility.incompatible) {
        return TelemetrySnapshotResult(
          status: TelemetrySnapshotStatus.incompatible,
          errors: [
            TelemetryError(
              errorCode: 'compatibility.incompatible',
              errorType: 'CompatibilityError',
              message: 'Events are incompatible in strict mode',
              component: TelemetryComponent.observability,
              operation: TelemetryOperation.compose,
              classification: TelemetryAttributeClassification.internal,
              originalErrorAvailable: false,
              redacted: false,
            ),
          ],
        );
      }

      final componentSummaries = request.includeSummaries
          ? _summaryBuilder.buildComponentSummaries(events)
          : const <TelemetryComponentSummary>[];
      final operationSummaries = request.includeSummaries
          ? _summaryBuilder.buildOperationSummaries(events)
          : const <TelemetryOperationSummary>[];
      final durationSummary = request.includeSummaries
          ? _summaryBuilder.buildDurationSummary(events)
          : const TelemetryDurationSummary(
              totalMicroseconds: 0,
              averageMicroseconds: 0,
              minMicroseconds: 0,
              maxMicroseconds: 0,
              sampleCount: 0,
            );
      final failureSummary = request.includeSummaries
          ? _summaryBuilder.buildFailureSummary(events)
          : const TelemetryFailureSummary(failureCount: 0, errorCodes: {});
      final coverage = _summaryBuilder.buildCoverage(
        events,
        _compatibilityChecker,
      );

      final filteredEvents = _filterEventPayloads(events, request);
      final sourceReferences = request.includeSourceReferences
          ? _collectSourceReferences(filteredEvents)
          : const <TelemetrySourceReference>[];

      final actualSummary = request.includeSummaries
          ? _summaryBuilder.buildSummary(filteredEvents)
          : TelemetrySummary(
              eventCount: filteredEvents.length,
              operationCount: 0,
              successCount: 0,
              failureCount: 0,
              unavailableCount: 0,
              cacheHitCount: 0,
              cacheMissCount: 0,
              storeReadCount: 0,
              storeWriteCount: 0,
              conflictCount: 0,
              successRatePercentage: 0,
            );

      final scopeFingerprint = _serializer.scopeFingerprint(
        projectId: request.projectId,
        correlationId: request.correlationId,
        operationId: request.operationId,
        timeRangeFrom: request.timeRange?.from,
        timeRangeTo: request.timeRange?.to,
        components:
            request.components?.map((c) => c.wireName).toList() ?? const [],
        operations:
            request.operations?.map((o) => o.wireName).toList() ?? const [],
        statuses: request.statuses?.map((s) => s.wireName).toList() ?? const [],
        severities:
            request.severities?.map((s) => s.wireName).toList() ?? const [],
        includeEvents: request.includeEvents,
        includeAttributes: request.includeAttributes,
        includeErrors: request.includeErrors,
        includeWarnings: request.includeWarnings,
        includeSourceReferences: request.includeSourceReferences,
        includeSummaries: request.includeSummaries,
        strictCompatibility: request.strictCompatibility,
        maximumEventCount: request.maximumEventCount,
        ordering: request.ordering,
      );

      final eventFingerprints =
          filteredEvents.map((e) => e.metadata.eventFingerprint).toList();
      final summaryFp = _serializer.fingerprintFromString(
        jsonEncode(actualSummary.toJson()),
      );
      final coverageFp = _serializer.fingerprintFromString(
        jsonEncode(coverage.toJson()),
      );
      final telemetryFingerprint = _serializer.telemetryFingerprint(
        eventFingerprints: eventFingerprints,
        summaryFingerprint: summaryFp,
        coverageFingerprint: coverageFp,
        compatibility: compatibility.wireName,
        schemaVersion: TelemetrySnapshotMetadata.currentSchemaVersion,
        calculationVersion: TelemetrySnapshotMetadata.currentCalculationVersion,
        canonicalizationVersion:
            TelemetrySnapshotMetadata.currentCanonicalizationVersion,
      );

      final snapshotId = _idFactory.create(
        scopeFingerprint: scopeFingerprint,
        telemetryFingerprint: telemetryFingerprint,
      );

      final status = _resolveStatus(
        events: filteredEvents,
        compatibility: compatibility,
        coverage: coverage,
      );

      final warnings = <TelemetryWarning>[];
      final errors = <TelemetryError>[];
      final limitations = <TelemetryLimitation>[];
      if (!request.includeEvents) {
        limitations.add(
          const TelemetryLimitation(
            code: 'events.excluded',
            message: 'Events excluded by request',
          ),
        );
      }

      final snapshot = TelemetrySnapshot(
        metadata: TelemetrySnapshotMetadata(
          telemetrySnapshotId: snapshotId,
          telemetrySchemaVersion:
              TelemetrySnapshotMetadata.currentSchemaVersion,
          telemetryCalculationVersion:
              TelemetrySnapshotMetadata.currentCalculationVersion,
          telemetryCanonicalizationVersion:
              TelemetrySnapshotMetadata.currentCanonicalizationVersion,
          createdAt: request.createdAt,
          scopeFingerprint: scopeFingerprint,
          telemetryFingerprint: telemetryFingerprint,
          status: status,
          compatibility: compatibility,
          eventCount: filteredEvents.length,
          warningCount: warnings.length,
          errorCount: errors.length,
          projectId: request.projectId,
          correlationId: request.correlationId,
        ),
        events: filteredEvents,
        summary: actualSummary,
        componentSummaries: componentSummaries,
        operationSummaries: operationSummaries,
        failureSummary: failureSummary,
        durationSummary: durationSummary,
        coverage: coverage,
        compatibility: compatibility,
        sourceReferences: sourceReferences,
        warnings: warnings,
        errors: errors,
        limitations: limitations,
      );

      final snapValidation = _snapshotValidator.validate(snapshot);
      if (!snapValidation.isValid) {
        return TelemetrySnapshotResult(
          status: TelemetrySnapshotStatus.failure,
          errors: snapValidation.errors
              .map(
                (e) => TelemetryError(
                  errorCode: 'snapshot.invalid',
                  errorType: 'ValidationError',
                  message: e,
                  component: TelemetryComponent.observability,
                  operation: TelemetryOperation.compose,
                  classification: TelemetryAttributeClassification.internal,
                  originalErrorAvailable: false,
                  redacted: false,
                ),
              )
              .toList(),
        );
      }

      return TelemetrySnapshotResult(
        status: status,
        snapshot: snapshot,
        warnings: warnings,
        errors: errors,
      );
    } catch (e) {
      return TelemetrySnapshotResult(
        status: TelemetrySnapshotStatus.failure,
        errors: [
          TelemetryError(
            errorCode: 'compose.failed',
            errorType: e.runtimeType.toString(),
            message: e.toString(),
            component: TelemetryComponent.observability,
            operation: TelemetryOperation.compose,
            classification: TelemetryAttributeClassification.internal,
            originalErrorAvailable: true,
            redacted: true,
          ),
        ],
      );
    }
  }

  List<String> _validateRequest(TelemetrySnapshotRequest request) {
    final errors = <String>[];
    if (request.maximumEventCount <= 0) {
      errors.add('maximumEventCount must be positive');
    }
    if (request.referenceTime.trim().isEmpty) {
      errors.add('referenceTime is required');
    }
    if (request.timeRange != null &&
        request.timeRange!.from.compareTo(request.timeRange!.to) > 0) {
      errors.add('timeRange is inverted');
    }
    final hasScope = request.projectId != null ||
        request.correlationId != null ||
        request.operationId != null ||
        request.components != null ||
        request.operations != null ||
        request.timeRange != null;
    if (!hasScope) {
      errors.add('At least one selection criterion is required');
    }
    return errors;
  }

  List<TelemetryEvent> _selectEvents(TelemetrySnapshotRequest request) {
    final query = TelemetryEventQuery(
      correlationId: request.correlationId,
      operationId: request.operationId,
      projectId: request.projectId,
      from: request.timeRange?.from,
      to: request.timeRange?.to,
      limit: request.maximumEventCount,
    );
    var events = _collector.queryEvents(query);
    if (request.components != null && request.components!.isNotEmpty) {
      events = events
          .where((e) => request.components!.contains(e.component))
          .toList();
    }
    if (request.operations != null && request.operations!.isNotEmpty) {
      events = events
          .where((e) => request.operations!.contains(e.operation))
          .toList();
    }
    if (request.statuses != null && request.statuses!.isNotEmpty) {
      events =
          events.where((e) => request.statuses!.contains(e.status)).toList();
    }
    if (request.severities != null && request.severities!.isNotEmpty) {
      events = events
          .where((e) => request.severities!.contains(e.severity))
          .toList();
    }
    return events;
  }

  List<TelemetryEvent> _filterEventPayloads(
    List<TelemetryEvent> events,
    TelemetrySnapshotRequest request,
  ) {
    if (!request.includeEvents) return const [];
    return events.map((event) {
      return TelemetryEvent(
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
        sourceReferences:
            request.includeSourceReferences ? event.sourceReferences : const [],
        attributes: request.includeAttributes ? event.attributes : const [],
        warnings: request.includeWarnings ? event.warnings : const [],
        errors: request.includeErrors ? event.errors : const [],
        metadata: event.metadata,
      );
    }).toList();
  }

  List<TelemetrySourceReference> _collectSourceReferences(
    List<TelemetryEvent> events,
  ) {
    final refs = <TelemetrySourceReference>[];
    final seen = <String>{};
    for (final event in events) {
      for (final ref in event.sourceReferences) {
        final key = '${ref.sourceType}:${ref.artifactId}';
        if (seen.add(key)) refs.add(ref);
      }
    }
    refs.sort((a, b) {
      final cmp = a.sourceType.compareTo(b.sourceType);
      if (cmp != 0) return cmp;
      return a.artifactId.compareTo(b.artifactId);
    });
    return refs;
  }

  TelemetrySnapshotStatus _resolveStatus({
    required List<TelemetryEvent> events,
    required TelemetryCompatibility compatibility,
    required TelemetryCoverage coverage,
  }) {
    if (compatibility == TelemetryCompatibility.incompatible) {
      return TelemetrySnapshotStatus.incompatible;
    }
    if (events.isEmpty) return TelemetrySnapshotStatus.unavailable;
    if (coverage.incompleteOperationCount > 0 ||
        compatibility == TelemetryCompatibility.partiallyCompatible) {
      return TelemetrySnapshotStatus.partial;
    }
    return TelemetrySnapshotStatus.success;
  }
}
