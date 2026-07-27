import 'history_artifact_type.dart';
import 'history_snapshot.dart';
import 'history_snapshot_status.dart';

/// Request to capture a historical snapshot.
class HistoryRequest {
  const HistoryRequest({
    required this.projectId,
    required this.createdAt,
    this.projectGraph,
    this.metricsSnapshot,
    this.reportDocument,
    this.guardianAnalysis,
    this.astReport,
    this.mesSnapshot,
    this.dashboardSnapshot,
    this.telemetrySnapshot,
    this.qualityGateSnapshot,
    this.releaseDecisionSnapshot,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.cicdIntegrationSnapshot,
    this.cryptographicTrustSnapshot,
    this.gitRef,
    this.branch,
    this.sourceEventId,
    this.tags = const [],
    this.metadata = const {},
    this.artifactSelection,
    this.requireComplete = false,
  });

  final String projectId;
  final String createdAt;
  final Map<String, dynamic>? projectGraph;
  final Map<String, dynamic>? metricsSnapshot;
  final Map<String, dynamic>? reportDocument;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? astReport;
  final Map<String, dynamic>? mesSnapshot;
  final Map<String, dynamic>? dashboardSnapshot;
  final Map<String, dynamic>? telemetrySnapshot;
  final Map<String, dynamic>? qualityGateSnapshot;
  final Map<String, dynamic>? releaseDecisionSnapshot;
  final Map<String, dynamic>? releaseEvidenceBundle;
  final Map<String, dynamic>? releaseSupplyChainSnapshot;
  final Map<String, dynamic>? cicdIntegrationSnapshot;
  final Map<String, dynamic>? cryptographicTrustSnapshot;
  final String? gitRef;
  final String? branch;
  final String? sourceEventId;
  final List<String> tags;
  final Map<String, String> metadata;
  final Set<HistoryArtifactType>? artifactSelection;
  final bool requireComplete;
}

/// Result of a history capture operation.
class HistoryResult {
  const HistoryResult({
    required this.status,
    required this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.idempotent = false,
  });

  final HistorySnapshotStatus status;
  final HistorySnapshot snapshot;
  final List<String> warnings;
  final List<HistoryError> errors;
  final bool idempotent;
}

/// Typed history error.
class HistoryError {
  const HistoryError({
    required this.code,
    required this.message,
    this.artifactType,
  });

  final String code;
  final String message;
  final HistoryArtifactType? artifactType;

  Map<String, dynamic> toJson() => {
        'code': code,
        if (artifactType != null) 'artifactType': artifactType!.wireName,
        'message': message,
      };
}

/// Query for listing historical snapshots.
class HistoryQuery {
  const HistoryQuery({
    required this.projectId,
    this.snapshotIds,
    this.artifactTypes,
    this.gitRef,
    this.branch,
    this.tags,
    this.createdFrom,
    this.createdTo,
    this.status,
    this.limit,
    this.descending = true,
  });

  final String projectId;
  final Set<String>? snapshotIds;
  final Set<HistoryArtifactType>? artifactTypes;
  final String? gitRef;
  final String? branch;
  final Set<String>? tags;
  final String? createdFrom;
  final String? createdTo;
  final HistorySnapshotStatus? status;
  final int? limit;
  final bool descending;
}

/// Result of a history query.
class HistoryQueryResult {
  const HistoryQueryResult({
    required this.snapshots,
    required this.totalCount,
  });

  final List<HistorySnapshot> snapshots;
  final int totalCount;
}
