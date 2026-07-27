import 'quality_gate_enums.dart';
import 'quality_gate_evidence.dart';
import 'quality_gate_governance.dart';
import 'quality_gate_messages.dart';

/// Metadata for a composed quality gate snapshot.
class QualityGateSnapshotMetadata {
  const QualityGateSnapshotMetadata({
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.requestFingerprint,
    required this.policyFingerprint,
    required this.projectId,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.evaluatedAt,
    required this.decision,
    required this.policyId,
    required this.policyVersion,
    required this.totalRuleCount,
    required this.evaluatedRuleCount,
    required this.failedRuleCount,
    required this.blockingFailureCount,
    required this.warningCount,
    required this.errorCount,
    required this.sourceCount,
    this.commitId,
    this.branch,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final String requestFingerprint;
  final String policyFingerprint;
  final String projectId;
  final String? commitId;
  final String? branch;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String evaluatedAt;
  final QualityGateDecision decision;
  final String policyId;
  final int policyVersion;
  final int totalRuleCount;
  final int evaluatedRuleCount;
  final int failedRuleCount;
  final int blockingFailureCount;
  final int warningCount;
  final int errorCount;
  final int sourceCount;

  Map<String, dynamic> toJson() => {
        'qualityGateSnapshotId': qualityGateSnapshotId,
        'qualityGateFingerprint': qualityGateFingerprint,
        'requestFingerprint': requestFingerprint,
        'policyFingerprint': policyFingerprint,
        'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        'evaluatedAt': evaluatedAt,
        'decision': decision.wireName,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'totalRuleCount': totalRuleCount,
        'evaluatedRuleCount': evaluatedRuleCount,
        'failedRuleCount': failedRuleCount,
        'blockingFailureCount': blockingFailureCount,
        'warningCount': warningCount,
        'errorCount': errorCount,
        'sourceCount': sourceCount,
      };

  factory QualityGateSnapshotMetadata.fromJson(Map<String, dynamic> json) {
    return QualityGateSnapshotMetadata(
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String,
      requestFingerprint: json['requestFingerprint'] as String,
      policyFingerprint: json['policyFingerprint'] as String,
      projectId: json['projectId'] as String,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      calculationVersion:
          json['calculationVersion'] as int? ?? currentCalculationVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String,
      decision: QualityGateDecisionX.fromWireName(json['decision'] as String),
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      totalRuleCount: json['totalRuleCount'] as int,
      evaluatedRuleCount: json['evaluatedRuleCount'] as int,
      failedRuleCount: json['failedRuleCount'] as int,
      blockingFailureCount: json['blockingFailureCount'] as int,
      warningCount: json['warningCount'] as int,
      errorCount: json['errorCount'] as int,
      sourceCount: json['sourceCount'] as int,
    );
  }
}

/// Rule set evaluation summary.
class QualityGateRuleSetEvaluation {
  const QualityGateRuleSetEvaluation({
    required this.ruleSetId,
    required this.status,
    required this.aggregationMode,
    required this.totalRuleCount,
    required this.evaluatedRuleCount,
    required this.passedRuleCount,
    required this.failedRuleCount,
    required this.unavailableRuleCount,
    required this.incompatibleRuleCount,
    required this.required,
    required this.severity,
    required this.decisionImpact,
    required this.ruleEvaluationIds,
    required this.fingerprint,
    this.explanation,
  });

  final String ruleSetId;
  final QualityGateRuleStatus status;
  final QualityGateRuleSetAggregationMode aggregationMode;
  final int totalRuleCount;
  final int evaluatedRuleCount;
  final int passedRuleCount;
  final int failedRuleCount;
  final int unavailableRuleCount;
  final int incompatibleRuleCount;
  final bool required;
  final QualityGateRuleSeverity severity;
  final QualityGateDecisionImpact decisionImpact;
  final List<String> ruleEvaluationIds;
  final QualityGateExplanation? explanation;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'ruleSetId': ruleSetId,
        'status': status.wireName,
        'aggregationMode': aggregationMode.wireName,
        'totalRuleCount': totalRuleCount,
        'evaluatedRuleCount': evaluatedRuleCount,
        'passedRuleCount': passedRuleCount,
        'failedRuleCount': failedRuleCount,
        'unavailableRuleCount': unavailableRuleCount,
        'incompatibleRuleCount': incompatibleRuleCount,
        'required': required,
        'severity': severity.wireName,
        'decisionImpact': decisionImpact.wireName,
        'ruleEvaluationIds': ruleEvaluationIds,
        if (explanation != null) 'explanation': explanation!.toJson(),
        'fingerprint': fingerprint,
      };

  factory QualityGateRuleSetEvaluation.fromJson(Map<String, dynamic> json) {
    return QualityGateRuleSetEvaluation(
      ruleSetId: json['ruleSetId'] as String,
      status: QualityGateRuleStatusX.fromWireName(json['status'] as String),
      aggregationMode: QualityGateRuleSetAggregationModeX.fromWireName(
        json['aggregationMode'] as String? ??
            QualityGateRuleSetAggregationMode.all.wireName,
      ),
      totalRuleCount: json['totalRuleCount'] as int? ??
          json['evaluatedRuleCount'] as int? ??
          0,
      evaluatedRuleCount: json['evaluatedRuleCount'] as int,
      passedRuleCount: json['passedRuleCount'] as int,
      failedRuleCount: json['failedRuleCount'] as int,
      unavailableRuleCount: json['unavailableRuleCount'] as int? ?? 0,
      incompatibleRuleCount: json['incompatibleRuleCount'] as int? ?? 0,
      required: json['required'] as bool? ?? true,
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String? ??
            QualityGateRuleSeverity.blocking.wireName,
      ),
      decisionImpact: QualityGateDecisionImpactX.fromWireName(
        json['decisionImpact'] as String? ??
            QualityGateDecisionImpact.none.wireName,
      ),
      ruleEvaluationIds: (json['ruleEvaluationIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      explanation: json['explanation'] == null
          ? null
          : QualityGateExplanation.fromJson(
              json['explanation'] as Map<String, dynamic>,
            ),
      fingerprint: json['fingerprint'] as String? ?? '',
    );
  }
}

/// Immutable consolidated quality gate snapshot.
class QualityGateSnapshot {
  const QualityGateSnapshot({
    required this.metadata,
    required this.policyReference,
    required this.decision,
    required this.eligibility,
    required this.compatibility,
    required this.coverage,
    required this.evaluations,
    required this.ruleSetEvaluations,
    required this.evidence,
    required this.sourceReferences,
    required this.explanations,
    required this.warnings,
    required this.errors,
    required this.limitations,
  });

  final QualityGateSnapshotMetadata metadata;
  final QualityGatePolicyVersion policyReference;
  final QualityGateDecision decision;
  final QualityGateEligibility eligibility;
  final QualityGateCompatibility compatibility;
  final QualityGateCoverage coverage;
  final List<QualityGateEvaluation> evaluations;
  final List<QualityGateRuleSetEvaluation> ruleSetEvaluations;
  final List<QualityGateEvidence> evidence;
  final List<QualityGateSourceReference> sourceReferences;
  final List<QualityGateExplanation> explanations;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policyReference': policyReference.toJson(),
        'decision': decision.wireName,
        'eligibility': eligibility.toJson(),
        'compatibility': compatibility.toJson(),
        'coverage': coverage.toJson(),
        'evaluations': evaluations.map((e) => e.toJson()).toList(),
        'ruleSetEvaluations':
            ruleSetEvaluations.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'explanations': explanations.map((e) => e.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
      };

  factory QualityGateSnapshot.fromJson(Map<String, dynamic> json) {
    return QualityGateSnapshot(
      metadata: QualityGateSnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policyReference: QualityGatePolicyVersion.fromJson(
        json['policyReference'] as Map<String, dynamic>,
      ),
      decision: QualityGateDecisionX.fromWireName(json['decision'] as String),
      eligibility: QualityGateEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      compatibility: QualityGateCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>,
      ),
      coverage: QualityGateCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      evaluations: (json['evaluations'] as List<dynamic>)
          .map((e) => QualityGateEvaluation.fromJson(e as Map<String, dynamic>))
          .toList(),
      ruleSetEvaluations: (json['ruleSetEvaluations'] as List<dynamic>)
          .map(
            (e) => QualityGateRuleSetEvaluation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      evidence: (json['evidence'] as List<dynamic>)
          .map((e) => QualityGateEvidence.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>)
          .map(
            (e) => QualityGateSourceReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      explanations: (json['explanations'] as List<dynamic>)
          .map(
            (e) => QualityGateExplanation.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => QualityGateWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>)
          .map((e) => QualityGateError.fromJson(e as Map<String, dynamic>))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>)
          .map(
            (e) => QualityGateLimitation.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    meta.remove('evaluatedAt');
    json['metadata'] = meta;
    return json;
  }
}
