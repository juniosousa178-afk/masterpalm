import 'score_policy.dart';
import 'score_snapshot.dart';
import 'score_enums.dart';

/// Request to calculate an engineering score.
class ScoreRequest {
  const ScoreRequest({
    required this.projectId,
    required this.metricsSnapshot,
    required this.createdAt,
    this.policy,
    this.policyId,
    this.guardianAnalysis,
    this.historyDiff,
    this.historySnapshot,
    this.calculationContext = const {},
    this.sourceEventId,
    this.gitRef,
    this.branch,
    this.requestedDimensions,
    this.requestedRuleIds,
    this.strictCompatibility = false,
    this.includeTrace = false,
    this.includeExplanations = true,
  });

  final String projectId;
  final Map<String, dynamic> metricsSnapshot;
  final String createdAt;
  final ScorePolicy? policy;
  final String? policyId;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? historyDiff;
  final Map<String, dynamic>? historySnapshot;
  final Map<String, String> calculationContext;
  final String? sourceEventId;
  final String? gitRef;
  final String? branch;
  final Set<String>? requestedDimensions;
  final Set<String>? requestedRuleIds;
  final bool strictCompatibility;
  final bool includeTrace;
  final bool includeExplanations;
}

/// Result of score calculation.
class ScoreResult {
  const ScoreResult({
    required this.status,
    required this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.idempotent = false,
  });

  final ScoreStatus status;
  final EngineeringScoreSnapshot snapshot;
  final List<ScoreWarning> warnings;
  final List<ScoreError> errors;
  final bool idempotent;
}
