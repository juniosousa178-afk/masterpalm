import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';

/// Checks compatibility between telemetry events.
class TelemetryCompatibilityChecker {
  const TelemetryCompatibilityChecker();

  TelemetryCompatibility evaluate(List<TelemetryEvent> events) {
    if (events.isEmpty) return TelemetryCompatibility.unknown;

    final starts = <String>{};
    final terminals = <String>{};
    var partial = false;

    for (final event in events) {
      final opId = event.correlation.operationId;
      if (event.eventType == TelemetryEventType.operationStarted) {
        starts.add(opId);
      }
      if (event.eventType == TelemetryEventType.operationCompleted ||
          event.eventType == TelemetryEventType.operationFailed) {
        terminals.add(opId);
      }

      if (event.correlation.parentEventId != null) {
        final parentExists = events.any(
          (e) => e.eventId == event.correlation.parentEventId,
        );
        if (!parentExists) partial = true;
      }
      if (event.correlation.causationId != null) {
        final causeExists = events.any(
          (e) => e.eventId == event.correlation.causationId,
        );
        if (!causeExists) partial = true;
      }
    }

    final orphans = terminals.difference(starts);
    final incomplete = starts.difference(terminals);
    if (orphans.isNotEmpty || incomplete.isNotEmpty) {
      partial = true;
    }

    final projectIds = events
        .map((e) => e.correlation.projectId)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    if (projectIds.length > 1) return TelemetryCompatibility.incompatible;

    if (partial) return TelemetryCompatibility.partiallyCompatible;
    return TelemetryCompatibility.compatible;
  }

  List<String> orphanEventIds(List<TelemetryEvent> events) {
    final starts = events
        .where((e) => e.eventType == TelemetryEventType.operationStarted)
        .map((e) => e.correlation.operationId)
        .toSet();
    return events
        .where(
          (e) =>
              (e.eventType == TelemetryEventType.operationCompleted ||
                  e.eventType == TelemetryEventType.operationFailed) &&
              !starts.contains(e.correlation.operationId),
        )
        .map((e) => e.eventId)
        .toList();
  }

  List<String> missingOperationIds(List<TelemetryEvent> events) {
    final starts = events
        .where((e) => e.eventType == TelemetryEventType.operationStarted)
        .map((e) => e.correlation.operationId)
        .toSet();
    final terminals = events
        .where(
          (e) =>
              e.eventType == TelemetryEventType.operationCompleted ||
              e.eventType == TelemetryEventType.operationFailed,
        )
        .map((e) => e.correlation.operationId)
        .toSet();
    return starts.difference(terminals).toList();
  }
}
