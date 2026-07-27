import 'report_document.dart';
import 'report_format.dart';
import 'report_status.dart';
import 'report_type.dart';

/// Request to generate a platform report.
class ReportRequest {
  const ReportRequest({
    required this.reportType,
    required this.projectId,
    this.format = ReportFormat.markdown,
    this.sourceSnapshotId,
    this.gitRef,
    this.guardianAnalysis,
    this.astReport,
    this.projectGraph,
    this.metricsSnapshot,
    this.historyDiff,
    this.engineeringScore,
    this.mesSnapshot,
    this.dashboardSnapshot,
    this.telemetrySnapshot,
    this.qualityGateSnapshot,
    this.releaseDecisionSnapshot,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.cicdIntegrationSnapshot,
    this.cryptographicTrustSnapshot,
    this.persistentArtifactSnapshot,
    this.extra = const {},
  });

  final ReportType reportType;
  final String projectId;
  final ReportFormat format;
  final String? sourceSnapshotId;
  final String? gitRef;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? astReport;
  final Map<String, dynamic>? projectGraph;
  final Map<String, dynamic>? metricsSnapshot;
  final Map<String, dynamic>? historyDiff;
  final Map<String, dynamic>? engineeringScore;
  final Map<String, dynamic>? mesSnapshot;
  final Map<String, dynamic>? dashboardSnapshot;
  final Map<String, dynamic>? telemetrySnapshot;
  final Map<String, dynamic>? qualityGateSnapshot;
  final Map<String, dynamic>? releaseDecisionSnapshot;
  final Map<String, dynamic>? releaseEvidenceBundle;
  final Map<String, dynamic>? releaseSupplyChainSnapshot;
  final Map<String, dynamic>? cicdIntegrationSnapshot;
  final Map<String, dynamic>? cryptographicTrustSnapshot;
  final Map<String, dynamic>? persistentArtifactSnapshot;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'reportType': reportType.wireName,
        'projectId': projectId,
        'format': format.wireName,
        if (sourceSnapshotId != null) 'sourceSnapshotId': sourceSnapshotId,
        if (gitRef != null) 'gitRef': gitRef,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

/// Result of report generation.
class ReportResult {
  const ReportResult({
    required this.status,
    required this.document,
    this.rendered,
    this.warnings = const [],
    this.errors = const [],
  });

  final ReportStatus status;
  final ReportDocument document;
  final String? rendered;
  final List<String> warnings;
  final List<String> errors;
}
