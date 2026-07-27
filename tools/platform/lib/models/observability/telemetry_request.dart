import 'telemetry_enums.dart';
import 'telemetry_event.dart';
import 'telemetry_snapshot.dart';

/// Time range filter for telemetry queries.
class TelemetryTimeRange {
  const TelemetryTimeRange({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  factory TelemetryTimeRange.fromJson(Map<String, dynamic> json) {
    return TelemetryTimeRange(
      from: json['from'] as String,
      to: json['to'] as String,
    );
  }
}

/// Query for telemetry snapshots.
class TelemetryQuery {
  const TelemetryQuery({
    this.projectId,
    this.correlationId,
    this.from,
    this.to,
    this.limit,
  });

  final String? projectId;
  final String? correlationId;
  final String? from;
  final String? to;
  final int? limit;
}

/// Query for telemetry events.
class TelemetryEventQuery {
  const TelemetryEventQuery({
    this.correlationId,
    this.operationId,
    this.component,
    this.projectId,
    this.from,
    this.to,
    this.limit,
  });

  final String? correlationId;
  final String? operationId;
  final TelemetryComponent? component;
  final String? projectId;
  final String? from;
  final String? to;
  final int? limit;
}

/// Request to compose a telemetry snapshot.
class TelemetrySnapshotRequest {
  const TelemetrySnapshotRequest({
    required this.createdAt,
    required this.referenceTime,
    this.projectId,
    this.correlationId,
    this.operationId,
    this.components,
    this.operations,
    this.statuses,
    this.severities,
    this.timeRange,
    this.includeEvents = true,
    this.includeAttributes = true,
    this.includeErrors = true,
    this.includeWarnings = true,
    this.includeSourceReferences = true,
    this.includeSummaries = true,
    this.strictCompatibility = false,
    this.maximumEventCount = 10000,
    this.ordering = 'startedAt',
  });

  final String createdAt;
  final String referenceTime;
  final String? projectId;
  final String? correlationId;
  final String? operationId;
  final Set<TelemetryComponent>? components;
  final Set<TelemetryOperation>? operations;
  final Set<TelemetryEventStatus>? statuses;
  final Set<TelemetrySeverity>? severities;
  final TelemetryTimeRange? timeRange;
  final bool includeEvents;
  final bool includeAttributes;
  final bool includeErrors;
  final bool includeWarnings;
  final bool includeSourceReferences;
  final bool includeSummaries;
  final bool strictCompatibility;
  final int maximumEventCount;
  final String ordering;
}

/// Result of telemetry snapshot composition.
class TelemetrySnapshotResult {
  const TelemetrySnapshotResult({
    required this.status,
    this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.idempotent = false,
  });

  final TelemetrySnapshotStatus status;
  final TelemetrySnapshot? snapshot;
  final List<TelemetryWarning> warnings;
  final List<TelemetryError> errors;
  final bool idempotent;
}
