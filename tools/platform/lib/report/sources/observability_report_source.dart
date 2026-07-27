import '../../models/observability/telemetry_enums.dart';
import '../../models/observability/telemetry_snapshot.dart';
import '../report_input.dart';

/// Converts [TelemetrySnapshot] into [ObservabilityReportInputData].
class ObservabilityReportSource {
  const ObservabilityReportSource();

  ObservabilityReportInputData fromSnapshot(TelemetrySnapshot snapshot) {
    final componentSummaries = snapshot.componentSummaries
        .map(
          (c) =>
              '${c.component.wireName}: ${c.eventCount} events (${c.successCount} ok, ${c.failureCount} failed)',
        )
        .toList();
    final operationSummaries = snapshot.operationSummaries
        .map(
          (o) =>
              '${o.operation.wireName}: ${o.eventCount} events (${o.successCount} ok, ${o.failureCount} failed)',
        )
        .toList();

    return ObservabilityReportInputData(
      telemetrySnapshotId: snapshot.metadata.telemetrySnapshotId,
      status: snapshot.metadata.status.wireName,
      compatibility: snapshot.compatibility.wireName,
      eventCount: snapshot.summary.eventCount,
      operationCount: snapshot.summary.operationCount,
      successCount: snapshot.summary.successCount,
      failureCount: snapshot.summary.failureCount,
      incompleteOperationCount: snapshot.coverage.incompleteOperationCount,
      totalDurationMicroseconds: snapshot.durationSummary.totalMicroseconds,
      averageDurationMicroseconds: snapshot.durationSummary.averageMicroseconds,
      minDurationMicroseconds: snapshot.durationSummary.minMicroseconds,
      maxDurationMicroseconds: snapshot.durationSummary.maxMicroseconds,
      eventCoveragePercentage: snapshot.coverage.eventCoveragePercentage,
      terminalCoveragePercentage:
          snapshot.coverage.terminalEventCoveragePercentage,
      conflictCount: snapshot.summary.conflictCount,
      componentSummaries: componentSummaries,
      operationSummaries: operationSummaries,
      sourceSummaries: snapshot.sourceReferences
          .map((r) => '${r.sourceType}:${r.artifactId}')
          .toList(),
      limitations: snapshot.limitations.map((l) => l.message).toList(),
      warnings: snapshot.warnings.map((w) => w.message).toList(),
      errors: snapshot.errors
          .map((e) => '${e.errorCode}: ${e.message ?? e.errorType}')
          .toList(),
      projectId: snapshot.metadata.projectId,
      correlationId: snapshot.metadata.correlationId,
    );
  }

  ObservabilityReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(TelemetrySnapshot.fromJson(json));
  }
}
