import '../analysis_result.dart';
import '../graph/project_graph.dart';
import '../history/history_diff.dart';
import '../history/history_snapshot.dart';
import '../mes/mes_snapshot.dart';
import '../metrics/metrics_snapshot.dart';
import '../observability/telemetry_snapshot.dart';
import '../quality_gate/quality_gate_snapshot.dart';
import '../release_governance/release_decision_snapshot.dart';
import '../release_evidence/release_evidence_bundle.dart';
import '../release_supply_chain/release_supply_chain_snapshot.dart';
import '../cicd_integration/cicd_integration_snapshot.dart';
import '../cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../score/score_snapshot.dart';
import 'dashboard_enums.dart';
import 'dashboard_snapshot.dart';

/// Optional time range filter for dashboard queries.
class DashboardTimeRange {
  const DashboardTimeRange({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  factory DashboardTimeRange.fromJson(Map<String, dynamic> json) {
    return DashboardTimeRange(
      from: json['from'] as String,
      to: json['to'] as String,
    );
  }
}

/// Named filter for dashboard composition.
class DashboardFilter {
  const DashboardFilter({required this.key, required this.value});

  final String key;
  final String value;

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  factory DashboardFilter.fromJson(Map<String, dynamic> json) {
    return DashboardFilter(
      key: json['key'] as String,
      value: json['value'] as String,
    );
  }
}

/// Query context for dashboard store lookups.
class DashboardQueryContext {
  const DashboardQueryContext({
    required this.projectId,
    this.branch,
    this.timeRange,
    this.filters = const [],
  });

  final String projectId;
  final String? branch;
  final DashboardTimeRange? timeRange;
  final List<DashboardFilter> filters;
}

/// Store query for dashboard snapshots.
class DashboardQuery {
  const DashboardQuery({
    required this.projectId,
    this.branch,
    this.from,
    this.to,
    this.limit,
  });

  final String projectId;
  final String? branch;
  final String? from;
  final String? to;
  final int? limit;
}

/// Request to compose a dashboard snapshot.
class DashboardRequest {
  const DashboardRequest({
    required this.projectId,
    required this.createdAt,
    required this.referenceTime,
    this.branch,
    this.gitRef,
    this.timeRange,
    this.filters = const [],
    this.requestedSections,
    this.requestedWidgetIds,
    this.metricsSnapshot,
    this.historySnapshot,
    this.historyDiff,
    this.engineeringScoreSnapshot,
    this.mesSnapshot,
    this.telemetrySnapshot,
    this.qualityGateSnapshot,
    this.releaseDecisionSnapshot,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.cicdIntegrationSnapshot,
    this.cryptographicTrustSnapshot,
    this.projectGraph,
    this.guardianResult,
    this.guardianAnalysis,
    this.metricsSnapshotId,
    this.historySnapshotId,
    this.scoreSnapshotId,
    this.mesSnapshotId,
    this.qualityGateSnapshotId,
    this.releaseDecisionSnapshotId,
    this.releaseEvidenceBundleId,
    this.releaseSupplyChainSnapshotId,
    this.cicdIntegrationSnapshotId,
    this.cryptographicTrustSnapshotId,
    this.useLatest = true,
    this.includeUnavailable = true,
    this.includeWarnings = true,
    this.includeLimitations = true,
    this.includeSourceReferences = true,
    this.strictCompatibility = false,
    this.freshnessPolicy = const DashboardFreshnessPolicy(),
    this.layoutId,
    this.comparisonMode = DashboardComparisonMode.none,
    this.baselineSnapshotId,
  });

  final String projectId;
  final String createdAt;
  final String referenceTime;
  final String? branch;
  final String? gitRef;
  final DashboardTimeRange? timeRange;
  final List<DashboardFilter> filters;
  final Set<DashboardSectionType>? requestedSections;
  final Set<String>? requestedWidgetIds;
  final MetricsSnapshot? metricsSnapshot;
  final HistorySnapshot? historySnapshot;
  final HistoryDiff? historyDiff;
  final EngineeringScoreSnapshot? engineeringScoreSnapshot;
  final MESSnapshot? mesSnapshot;
  final TelemetrySnapshot? telemetrySnapshot;
  final QualityGateSnapshot? qualityGateSnapshot;
  final ReleaseDecisionSnapshot? releaseDecisionSnapshot;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot;
  final CicdIntegrationSnapshot? cicdIntegrationSnapshot;
  final CryptographicTrustSnapshot? cryptographicTrustSnapshot;
  final ProjectGraph? projectGraph;
  final AnalysisResult? guardianResult;
  final Map<String, dynamic>? guardianAnalysis;
  final String? metricsSnapshotId;
  final String? historySnapshotId;
  final String? scoreSnapshotId;
  final String? mesSnapshotId;
  final String? qualityGateSnapshotId;
  final String? releaseDecisionSnapshotId;
  final String? releaseEvidenceBundleId;
  final String? releaseSupplyChainSnapshotId;
  final String? cicdIntegrationSnapshotId;
  final String? cryptographicTrustSnapshotId;
  final bool useLatest;
  final bool includeUnavailable;
  final bool includeWarnings;
  final bool includeLimitations;
  final bool includeSourceReferences;
  final bool strictCompatibility;
  final DashboardFreshnessPolicy freshnessPolicy;
  final String? layoutId;
  final DashboardComparisonMode comparisonMode;
  final String? baselineSnapshotId;
}

/// Result of dashboard composition.
class DashboardResult {
  const DashboardResult({
    required this.status,
    this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.idempotent = false,
  });

  final DashboardStatus status;
  final DashboardSnapshot? snapshot;
  final List<DashboardWarning> warnings;
  final List<DashboardError> errors;
  final bool idempotent;
}
