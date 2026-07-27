import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/history/history_change_type.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/observability/telemetry_snapshot.dart';

/// Maps telemetry snapshots to history artifacts and structural diffs.
class TelemetryHistoryMapper {
  const TelemetryHistoryMapper();

  HistoryArtifact toArtifact(TelemetrySnapshot snapshot) {
    return HistoryArtifact(
      artifactType: HistoryArtifactType.telemetry,
      artifactId: snapshot.metadata.telemetrySnapshotId,
      schemaVersion: snapshot.metadata.telemetrySchemaVersion,
      fingerprint: snapshot.metadata.telemetryFingerprint,
      canonicalizationVersion:
          snapshot.metadata.telemetryCanonicalizationVersion,
      calculationVersion: snapshot.metadata.telemetryCalculationVersion,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    TelemetrySnapshot? from,
    TelemetrySnapshot? to,
  ) {
    if (from == null || to == null) return const [];
    final changes = <HistoryChange>[];

    if (from.metadata.status != to.metadata.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.telemetryStatusChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'status',
          previousValue: from.metadata.status.wireName,
          currentValue: to.metadata.status.wireName,
        ),
      );
    }
    if (from.summary.eventCount != to.summary.eventCount) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.eventCountChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'eventCount',
          previousValue: from.summary.eventCount.toString(),
          currentValue: to.summary.eventCount.toString(),
        ),
      );
    }
    if (from.summary.failureCount != to.summary.failureCount) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.failureCountChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'failureCount',
          previousValue: from.summary.failureCount.toString(),
          currentValue: to.summary.failureCount.toString(),
        ),
      );
    }
    if (from.coverage.incompleteOperationCount !=
        to.coverage.incompleteOperationCount) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.incompleteOperationCountChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'incompleteOperationCount',
          previousValue: from.coverage.incompleteOperationCount.toString(),
          currentValue: to.coverage.incompleteOperationCount.toString(),
        ),
      );
    }
    if (from.compatibility != to.compatibility) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.compatibilityChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'compatibility',
          previousValue: from.compatibility.wireName,
          currentValue: to.compatibility.wireName,
        ),
      );
    }
    final fromCoverage = from.coverage.componentCoverage.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final toCoverage = to.coverage.componentCoverage.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (fromCoverage.toString() != toCoverage.toString()) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.componentCoverageChanged,
          category: HistoryChangeCategory.telemetry,
          subjectId: 'componentCoverage',
          previousValue: fromCoverage.length.toString(),
          currentValue: toCoverage.length.toString(),
        ),
      );
    }
    return changes;
  }
}
