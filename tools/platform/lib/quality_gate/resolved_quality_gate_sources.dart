import '../models/analysis_result.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/history/history_diff.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';
import '../models/score/score_snapshot.dart';

/// Availability state for a resolved gate source wrapper.
enum ResolvedQualityGateSourceState {
  available,
  unavailable,
  notRequested,
  resolutionFailed,
}

/// Wrapper for a resolved source artifact with explicit availability.
class ResolvedQualityGateSource<T> {
  const ResolvedQualityGateSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.requestedId,
    this.resolvedArtifact,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.commitId,
    this.branch,
    this.policyId,
    this.policyVersion,
    this.schemaVersion,
    this.calculationVersion,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final QualityGateSourceType sourceType;
  final QualityGateSourceResolutionMode resolutionMode;
  final ResolvedQualityGateSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? commitId;
  final String? branch;
  final String? policyId;
  final int? policyVersion;
  final int? schemaVersion;
  final int? calculationVersion;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;

  bool get isAvailable =>
      state == ResolvedQualityGateSourceState.available &&
      resolvedArtifact != null;
}

/// Container for all resolved quality gate sources.
class ResolvedQualityGateSources {
  const ResolvedQualityGateSources({
    required this.metrics,
    required this.guardian,
    required this.score,
    required this.mes,
    required this.history,
    required this.telemetry,
    required this.dashboard,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.compatibilityHints = const [],
  });

  final ResolvedQualityGateSource<MetricsSnapshot> metrics;
  final ResolvedQualityGateSource<Map<String, dynamic>> guardian;
  final ResolvedQualityGateSource<EngineeringScoreSnapshot> score;
  final ResolvedQualityGateSource<MESSnapshot> mes;
  final ResolvedQualityGateSource<HistoryDiff> history;
  final ResolvedQualityGateSource<TelemetrySnapshot> telemetry;
  final ResolvedQualityGateSource<DashboardSnapshot> dashboard;
  final List<QualityGateSourceReference> sourceReferences;
  final QualityGateSourceResolutionSummary resolutionSummary;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;
  final List<String> compatibilityHints;

  List<ResolvedQualityGateSource<dynamic>> get allSources => [
        metrics,
        guardian,
        score,
        mes,
        history,
        telemetry,
        dashboard,
      ];
}

/// Evaluation context passed to target resolvers.
class QualityGateEvaluationContext {
  const QualityGateEvaluationContext({
    required this.projectId,
    required this.referenceTime,
    this.commitId,
    this.branch,
    this.strictCompatibility = false,
    this.requiredSourceTypes = const [],
  });

  final String projectId;
  final String referenceTime;
  final String? commitId;
  final String? branch;
  final bool strictCompatibility;
  final List<QualityGateSourceType> requiredSourceTypes;
}

/// Result of resolving a rule target value.
class QualityGateTargetResolution {
  const QualityGateTargetResolution({
    required this.status,
    this.actualValue,
    this.sourceReference,
    this.evidenceType = QualityGateEvidenceType.authoritative,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.notApplicable = false,
  });

  final QualityGateTargetResolutionStatus status;
  final QualityGateRuleValue? actualValue;
  final QualityGateSourceReference? sourceReference;
  final QualityGateEvidenceType evidenceType;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;
  final bool notApplicable;
}

enum QualityGateTargetResolutionStatus {
  resolved,
  unavailable,
  incompatible,
  notApplicable,
  unsupported,
  error,
}

/// Extracts guardian analysis map from [AnalysisResult].
Map<String, dynamic>? guardianAnalysisMap(AnalysisResult? analysis) {
  if (analysis == null) return null;
  if (analysis.details.isNotEmpty && analysis.details.containsKey('decision')) {
    return Map<String, dynamic>.from(analysis.details);
  }
  if (analysis.details.isNotEmpty) {
    return Map<String, dynamic>.from(analysis.details);
  }
  return {
    'decision': analysis.success ? 'go' : 'noGo',
    'summary': analysis.summary,
    'violations': analysis.errors,
    'warnings': analysis.warnings,
  };
}

/// Normalizes guardian decision strings to canonical GO/NO-GO.
String normalizeGuardianDecision(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll('-', '');
  if (normalized == 'go') return 'GO';
  if (normalized == 'nogo') return 'NO-GO';
  return raw.toUpperCase();
}
