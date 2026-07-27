import '../analysis_result.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../history/history_diff.dart';
import '../mes/mes_snapshot.dart';
import '../metrics/metrics_snapshot.dart';
import '../observability/telemetry_snapshot.dart';
import '../score/score_snapshot.dart';
import 'quality_gate_enums.dart';
import 'quality_gate_messages.dart';
import 'quality_gate_policy.dart';
import 'quality_gate_snapshot.dart';

/// Source resolution summary for a gate request.
class QualityGateSourceResolutionSummary {
  const QualityGateSourceResolutionSummary({
    required this.resolvedSources,
    required this.missingSources,
    required this.incompatibleSources,
    this.requestedSourceCount = 0,
    this.injectedSourceCount = 0,
    this.loadedByIdCount = 0,
    this.loadedLatestCount = 0,
    this.unavailableSourceCount = 0,
    this.failedSourceCount = 0,
    this.availableSourceTypes = const [],
    this.unavailableSourceTypes = const [],
    this.resolutionModesBySource = const {},
    this.warnings = const [],
    this.limitations = const [],
    this.fingerprint = '',
  });

  final List<QualityGateSourceType> resolvedSources;
  final List<QualityGateSourceType> missingSources;
  final List<QualityGateSourceType> incompatibleSources;
  final int requestedSourceCount;
  final int injectedSourceCount;
  final int loadedByIdCount;
  final int loadedLatestCount;
  final int unavailableSourceCount;
  final int failedSourceCount;
  final List<QualityGateSourceType> availableSourceTypes;
  final List<QualityGateSourceType> unavailableSourceTypes;
  final Map<String, String> resolutionModesBySource;
  final List<String> warnings;
  final List<String> limitations;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'resolvedSources': resolvedSources.map((e) => e.wireName).toList(),
        'missingSources': missingSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'requestedSourceCount': requestedSourceCount,
        'injectedSourceCount': injectedSourceCount,
        'loadedByIdCount': loadedByIdCount,
        'loadedLatestCount': loadedLatestCount,
        'unavailableSourceCount': unavailableSourceCount,
        'failedSourceCount': failedSourceCount,
        'availableSourceTypes':
            availableSourceTypes.map((e) => e.wireName).toList(),
        'unavailableSourceTypes':
            unavailableSourceTypes.map((e) => e.wireName).toList(),
        'resolutionModesBySource': resolutionModesBySource,
        'warnings': warnings,
        'limitations': limitations,
        'fingerprint': fingerprint,
      };

  factory QualityGateSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return QualityGateSourceResolutionSummary(
      resolvedSources: (json['resolvedSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      missingSources: (json['missingSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      incompatibleSources: (json['incompatibleSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      requestedSourceCount: json['requestedSourceCount'] as int? ?? 0,
      injectedSourceCount: json['injectedSourceCount'] as int? ?? 0,
      loadedByIdCount: json['loadedByIdCount'] as int? ?? 0,
      loadedLatestCount: json['loadedLatestCount'] as int? ?? 0,
      unavailableSourceCount: json['unavailableSourceCount'] as int? ?? 0,
      failedSourceCount: json['failedSourceCount'] as int? ?? 0,
      availableSourceTypes:
          (json['availableSourceTypes'] as List<dynamic>? ?? [])
              .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
              .toList(),
      unavailableSourceTypes:
          (json['unavailableSourceTypes'] as List<dynamic>? ?? [])
              .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
              .toList(),
      resolutionModesBySource:
          (json['resolutionModesBySource'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, v.toString())),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fingerprint: json['fingerprint'] as String? ?? '',
    );
  }
}

/// Request to evaluate a quality gate policy over injected artifacts.
class QualityGateRequest {
  const QualityGateRequest({
    required this.projectId,
    required this.createdAt,
    required this.referenceTime,
    this.policy,
    this.policyId,
    this.policyVersion,
    this.commitId,
    this.branch,
    this.metricsSnapshot,
    this.guardianAnalysis,
    this.engineeringScoreSnapshot,
    this.mesSnapshot,
    this.historyDiff,
    this.telemetrySnapshot,
    this.dashboardSnapshot,
    this.metricsSnapshotId,
    this.guardianAnalysisId,
    this.scoreSnapshotId,
    this.mesSnapshotId,
    this.historyDiffId,
    this.telemetrySnapshotId,
    this.dashboardSnapshotId,
    this.useLatest = false,
    this.strictCompatibility = false,
    this.historicalEvaluation = false,
    this.requestedRuleIds,
    this.excludedRuleIds,
    this.requestedRuleSetIds,
    this.includeEvidence = true,
    this.includeExplanations = true,
    this.includeWarnings = true,
    this.includeLimitations = true,
    this.metadata = const {},
  });

  final QualityGatePolicy? policy;
  final String? policyId;
  final int? policyVersion;
  final String projectId;
  final String? commitId;
  final String? branch;
  final MetricsSnapshot? metricsSnapshot;
  final AnalysisResult? guardianAnalysis;
  final EngineeringScoreSnapshot? engineeringScoreSnapshot;
  final MESSnapshot? mesSnapshot;
  final HistoryDiff? historyDiff;
  final TelemetrySnapshot? telemetrySnapshot;
  final DashboardSnapshot? dashboardSnapshot;
  final String? metricsSnapshotId;
  final String? guardianAnalysisId;
  final String? scoreSnapshotId;
  final String? mesSnapshotId;
  final String? historyDiffId;
  final String? telemetrySnapshotId;
  final String? dashboardSnapshotId;
  final bool useLatest;
  final String createdAt;
  final String referenceTime;
  final bool strictCompatibility;
  final bool historicalEvaluation;
  final Set<String>? requestedRuleIds;
  final Set<String>? excludedRuleIds;
  final Set<String>? requestedRuleSetIds;
  final bool includeEvidence;
  final bool includeExplanations;
  final bool includeWarnings;
  final bool includeLimitations;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'createdAt': createdAt,
        'referenceTime': referenceTime,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        'useLatest': useLatest,
        'strictCompatibility': strictCompatibility,
        'historicalEvaluation': historicalEvaluation,
        if (requestedRuleIds != null)
          'requestedRuleIds': requestedRuleIds!.toList(),
        if (excludedRuleIds != null)
          'excludedRuleIds': excludedRuleIds!.toList(),
        if (requestedRuleSetIds != null)
          'requestedRuleSetIds': requestedRuleSetIds!.toList(),
        'includeEvidence': includeEvidence,
        'includeExplanations': includeExplanations,
        'includeWarnings': includeWarnings,
        'includeLimitations': includeLimitations,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory QualityGateRequest.fromJson(Map<String, dynamic> json) {
    return QualityGateRequest(
      projectId: json['projectId'] as String,
      createdAt: json['createdAt'] as String,
      referenceTime: json['referenceTime'] as String,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      useLatest: json['useLatest'] as bool? ?? false,
      strictCompatibility: json['strictCompatibility'] as bool? ?? false,
      historicalEvaluation: json['historicalEvaluation'] as bool? ?? false,
      requestedRuleIds: (json['requestedRuleIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet(),
      excludedRuleIds: (json['excludedRuleIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet(),
      requestedRuleSetIds: (json['requestedRuleSetIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet(),
      includeEvidence: json['includeEvidence'] as bool? ?? true,
      includeExplanations: json['includeExplanations'] as bool? ?? true,
      includeWarnings: json['includeWarnings'] as bool? ?? true,
      includeLimitations: json['includeLimitations'] as bool? ?? true,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Execution wrapper for gate evaluation.
class QualityGateResult {
  const QualityGateResult({
    required this.status,
    this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.validationResult,
    this.sourceResolutionSummary,
  });

  final QualityGateResultStatus status;
  final QualityGateSnapshot? snapshot;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;
  final QualityGateValidationResult? validationResult;
  final QualityGateSourceResolutionSummary? sourceResolutionSummary;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
        if (validationResult != null)
          'validationResult': validationResult!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
      };

  factory QualityGateResult.fromJson(Map<String, dynamic> json) {
    return QualityGateResult(
      status: QualityGateResultStatusX.fromWireName(json['status'] as String),
      snapshot: json['snapshot'] == null
          ? null
          : QualityGateSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => QualityGateWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => QualityGateError.fromJson(e as Map<String, dynamic>))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => QualityGateLimitation.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      validationResult: json['validationResult'] == null
          ? null
          : QualityGateValidationResult.fromJson(
              json['validationResult'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : QualityGateSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
    );
  }
}
