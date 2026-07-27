import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_snapshot.dart';
import 'telemetry_compatibility_checker.dart';

/// Builds operational summaries from telemetry events.
class TelemetrySummaryBuilder {
  const TelemetrySummaryBuilder();

  TelemetrySummary buildSummary(List<TelemetryEvent> events) {
    final operationIds = <String>{};
    var success = 0;
    var failure = 0;
    var cacheHit = 0;
    var cacheMiss = 0;
    var storeRead = 0;
    var storeWrite = 0;
    var conflict = 0;

    for (final event in events) {
      operationIds.add(event.correlation.operationId);
      if (event.eventType == TelemetryEventType.operationCompleted) success++;
      if (event.eventType == TelemetryEventType.operationFailed) failure++;
      if (event.eventType == TelemetryEventType.cacheHit) cacheHit++;
      if (event.eventType == TelemetryEventType.cacheMiss) cacheMiss++;
      if (event.eventType == TelemetryEventType.storeRead) storeRead++;
      if (event.eventType == TelemetryEventType.storeWrite) storeWrite++;
      if (event.eventType == TelemetryEventType.storeConflict) conflict++;
    }

    final terminal = success + failure;
    final rate = terminal == 0 ? 0.0 : (success / terminal) * 100;

    return TelemetrySummary(
      eventCount: events.length,
      operationCount: operationIds.length,
      successCount: success,
      failureCount: failure,
      unavailableCount: events
          .where((e) => e.status == TelemetryEventStatus.unavailable)
          .length,
      cacheHitCount: cacheHit,
      cacheMissCount: cacheMiss,
      storeReadCount: storeRead,
      storeWriteCount: storeWrite,
      conflictCount: conflict,
      successRatePercentage: rate,
    );
  }

  List<TelemetryComponentSummary> buildComponentSummaries(
    List<TelemetryEvent> events,
  ) {
    final map = <TelemetryComponent, List<TelemetryEvent>>{};
    for (final event in events) {
      map.putIfAbsent(event.component, () => []).add(event);
    }
    return map.entries
        .map(
          (e) => TelemetryComponentSummary(
            component: e.key,
            eventCount: e.value.length,
            successCount: e.value
                .where(
                    (v) => v.eventType == TelemetryEventType.operationCompleted)
                .length,
            failureCount: e.value
                .where((v) => v.eventType == TelemetryEventType.operationFailed)
                .length,
          ),
        )
        .toList()
      ..sort((a, b) => a.component.wireName.compareTo(b.component.wireName));
  }

  List<TelemetryOperationSummary> buildOperationSummaries(
    List<TelemetryEvent> events,
  ) {
    final map = <TelemetryOperation, List<TelemetryEvent>>{};
    for (final event in events) {
      map.putIfAbsent(event.operation, () => []).add(event);
    }
    return map.entries
        .map(
          (e) => TelemetryOperationSummary(
            operation: e.key,
            eventCount: e.value.length,
            successCount: e.value
                .where(
                    (v) => v.eventType == TelemetryEventType.operationCompleted)
                .length,
            failureCount: e.value
                .where((v) => v.eventType == TelemetryEventType.operationFailed)
                .length,
          ),
        )
        .toList()
      ..sort((a, b) => a.operation.wireName.compareTo(b.operation.wireName));
  }

  TelemetryDurationSummary buildDurationSummary(List<TelemetryEvent> events) {
    final durations = events
        .map((e) => e.duration?.durationMicroseconds)
        .whereType<int>()
        .toList();
    if (durations.isEmpty) {
      return const TelemetryDurationSummary(
        totalMicroseconds: 0,
        averageMicroseconds: 0,
        minMicroseconds: 0,
        maxMicroseconds: 0,
        sampleCount: 0,
      );
    }
    final total = durations.fold<int>(0, (sum, d) => sum + d);
    final min = durations.reduce((a, b) => a < b ? a : b);
    final max = durations.reduce((a, b) => a > b ? a : b);
    return TelemetryDurationSummary(
      totalMicroseconds: total,
      averageMicroseconds: total ~/ durations.length,
      minMicroseconds: min,
      maxMicroseconds: max,
      sampleCount: durations.length,
    );
  }

  TelemetryFailureSummary buildFailureSummary(List<TelemetryEvent> events) {
    final codes = <String, int>{};
    for (final event in events) {
      for (final error in event.errors) {
        codes[error.errorCode] = (codes[error.errorCode] ?? 0) + 1;
      }
    }
    return TelemetryFailureSummary(
      failureCount: events
          .where((e) => e.eventType == TelemetryEventType.operationFailed)
          .length,
      errorCodes: codes,
    );
  }

  TelemetryCoverage buildCoverage(
    List<TelemetryEvent> events,
    TelemetryCompatibilityChecker checker,
  ) {
    final starts = events
        .where((e) => e.eventType == TelemetryEventType.operationStarted)
        .map((e) => e.correlation.operationId)
        .toSet();
    final completed = events
        .where((e) => e.eventType == TelemetryEventType.operationCompleted)
        .map((e) => e.correlation.operationId)
        .toSet();
    final failed = events
        .where((e) => e.eventType == TelemetryEventType.operationFailed)
        .map((e) => e.correlation.operationId)
        .toSet();
    final terminals = {...completed, ...failed};
    final incomplete = starts.difference(terminals);

    final componentMap = <String, int>{};
    final componentTotal = <String, int>{};
    for (final event in events) {
      final key = event.component.wireName;
      componentTotal[key] = (componentTotal[key] ?? 0) + 1;
      if (event.eventType == TelemetryEventType.operationCompleted) {
        componentMap[key] = (componentMap[key] ?? 0) + 1;
      }
    }
    final componentCoverage = <String, double>{};
    for (final entry in componentTotal.entries) {
      final successes = componentMap[entry.key] ?? 0;
      componentCoverage[entry.key] =
          entry.value == 0 ? 0 : (successes / entry.value) * 100;
    }

    final eventCoverage =
        starts.isEmpty ? 100.0 : (terminals.length / starts.length) * 100;
    final terminalCoverage =
        events.isEmpty ? 0.0 : (terminals.length / events.length) * 100;

    return TelemetryCoverage(
      observedOperationCount: starts.length,
      completedOperationCount: completed.length,
      failedOperationCount: failed.length,
      incompleteOperationCount: incomplete.length,
      eventCoveragePercentage: eventCoverage,
      terminalEventCoveragePercentage: terminalCoverage,
      componentCoverage: componentCoverage,
      missingOperationIds: checker.missingOperationIds(events),
      orphanEventIds: checker.orphanEventIds(events),
    );
  }
}
