import 'quality_gate_enums.dart';
import 'quality_gate_messages.dart';
import 'quality_gate_rule_value.dart';

/// Reference to an artifact used as gate evidence.
class QualityGateEvidenceReference {
  const QualityGateEvidenceReference({
    required this.artifactType,
    required this.artifactId,
    required this.fingerprint,
    required this.schemaVersion,
    this.calculationVersion,
    this.policyId,
    this.policyVersion,
    this.projectId,
    this.commitId,
    this.branch,
    this.createdAt,
  });

  final String artifactType;
  final String artifactId;
  final String fingerprint;
  final int schemaVersion;
  final int? calculationVersion;
  final String? policyId;
  final int? policyVersion;
  final String? projectId;
  final String? commitId;
  final String? branch;
  final String? createdAt;

  Map<String, dynamic> toJson() => {
        'artifactType': artifactType,
        'artifactId': artifactId,
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        if (createdAt != null) 'createdAt': createdAt,
      };

  factory QualityGateEvidenceReference.fromJson(Map<String, dynamic> json) {
    return QualityGateEvidenceReference(
      artifactType: json['artifactType'] as String,
      artifactId: json['artifactId'] as String,
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      projectId: json['projectId'] as String?,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

/// Resolved source reference for gate evaluation.
class QualityGateSourceReference {
  const QualityGateSourceReference({
    required this.sourceType,
    required this.resolutionMode,
    required this.availability,
    required this.compatibility,
    this.requestedId,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.commitId,
    this.branch,
    this.policyId,
    this.policyVersion,
    this.schemaVersion,
    this.calculationVersion,
    this.limitations = const [],
  });

  final QualityGateSourceType sourceType;
  final QualityGateSourceResolutionMode resolutionMode;
  final String? requestedId;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? commitId;
  final String? branch;
  final String? policyId;
  final int? policyVersion;
  final int? schemaVersion;
  final int? calculationVersion;
  final QualityGateSourceAvailability availability;
  final QualityGateCompatibilityStatus compatibility;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'resolutionMode': resolutionMode.wireName,
        if (requestedId != null) 'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        'availability': availability.wireName,
        'compatibility': compatibility.wireName,
        'limitations': limitations,
      };

  factory QualityGateSourceReference.fromJson(Map<String, dynamic> json) {
    return QualityGateSourceReference(
      sourceType:
          QualityGateSourceTypeX.fromWireName(json['sourceType'] as String),
      resolutionMode: QualityGateSourceResolutionModeX.fromWireName(
        json['resolutionMode'] as String,
      ),
      requestedId: json['requestedId'] as String?,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      schemaVersion: json['schemaVersion'] as int?,
      calculationVersion: json['calculationVersion'] as int?,
      availability: QualityGateSourceAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      compatibility: QualityGateCompatibilityStatusX.fromWireName(
        json['compatibility'] as String,
      ),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Evidence produced by rule evaluation.
class QualityGateEvidence {
  const QualityGateEvidence({
    required this.evidenceId,
    required this.evidenceType,
    required this.sourceType,
    required this.sourceArtifactId,
    required this.sourceFingerprint,
    required this.target,
    required this.operator,
    required this.observedStatus,
    required this.sourceReference,
    required this.explanation,
    this.selector = const QualityGateRuleSelector(),
    this.sourcePolicyId,
    this.sourcePolicyVersion,
    this.actualValue,
    this.expectedValue,
    this.limitations = const [],
    this.metadata = const {},
  });

  final String evidenceId;
  final QualityGateEvidenceType evidenceType;
  final QualityGateSourceType sourceType;
  final String sourceArtifactId;
  final String sourceFingerprint;
  final String? sourcePolicyId;
  final int? sourcePolicyVersion;
  final QualityGateRuleTarget target;
  final QualityGateRuleSelector selector;
  final QualityGateRuleOperator operator;
  final QualityGateRuleValue? actualValue;
  final QualityGateRuleValue? expectedValue;
  final QualityGateRuleStatus observedStatus;
  final QualityGateEvidenceReference sourceReference;
  final String explanation;
  final List<String> limitations;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'evidenceType': evidenceType.wireName,
        'sourceType': sourceType.wireName,
        'sourceArtifactId': sourceArtifactId,
        'sourceFingerprint': sourceFingerprint,
        if (sourcePolicyId != null) 'sourcePolicyId': sourcePolicyId,
        if (sourcePolicyVersion != null)
          'sourcePolicyVersion': sourcePolicyVersion,
        'target': target.wireName,
        'selector': selector.toJson(),
        'operator': operator.wireName,
        if (actualValue != null) 'actualValue': actualValue!.toJson(),
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        'observedStatus': observedStatus.wireName,
        'sourceReference': sourceReference.toJson(),
        'explanation': explanation,
        'limitations': limitations,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory QualityGateEvidence.fromJson(Map<String, dynamic> json) {
    return QualityGateEvidence(
      evidenceId: json['evidenceId'] as String,
      evidenceType:
          QualityGateEvidenceTypeX.fromWireName(json['evidenceType'] as String),
      sourceType:
          QualityGateSourceTypeX.fromWireName(json['sourceType'] as String),
      sourceArtifactId: json['sourceArtifactId'] as String,
      sourceFingerprint: json['sourceFingerprint'] as String,
      sourcePolicyId: json['sourcePolicyId'] as String?,
      sourcePolicyVersion: json['sourcePolicyVersion'] as int?,
      target: QualityGateRuleTargetX.fromWireName(json['target'] as String),
      selector: QualityGateRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      operator:
          QualityGateRuleOperatorX.fromWireName(json['operator'] as String),
      actualValue: json['actualValue'] == null
          ? null
          : QualityGateRuleValue.fromJson(
              json['actualValue'] as Map<String, dynamic>,
            ),
      expectedValue: json['expectedValue'] == null
          ? null
          : QualityGateRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      observedStatus: QualityGateRuleStatusX.fromWireName(
        json['observedStatus'] as String,
      ),
      sourceReference: QualityGateEvidenceReference.fromJson(
        json['sourceReference'] as Map<String, dynamic>,
      ),
      explanation: json['explanation'] as String,
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Deterministic explanation for a gate decision or rule.
class QualityGateExplanation {
  const QualityGateExplanation({
    required this.explanationId,
    required this.summary,
    required this.detail,
    required this.ruleExplanation,
    required this.decisionExplanation,
    required this.evidenceExplanation,
    required this.impactExplanation,
    required this.templateId,
    this.remediationHint,
    this.parameters = const {},
    this.limitations = const [],
  });

  final String explanationId;
  final String summary;
  final String detail;
  final String ruleExplanation;
  final String decisionExplanation;
  final String evidenceExplanation;
  final String impactExplanation;
  final String? remediationHint;
  final String templateId;
  final Map<String, String> parameters;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'explanationId': explanationId,
        'summary': summary,
        'detail': detail,
        'ruleExplanation': ruleExplanation,
        'decisionExplanation': decisionExplanation,
        'evidenceExplanation': evidenceExplanation,
        'impactExplanation': impactExplanation,
        if (remediationHint != null) 'remediationHint': remediationHint,
        'templateId': templateId,
        if (parameters.isNotEmpty) 'parameters': parameters,
        'limitations': limitations,
      };

  factory QualityGateExplanation.fromJson(Map<String, dynamic> json) {
    return QualityGateExplanation(
      explanationId: json['explanationId'] as String,
      summary: json['summary'] as String,
      detail: json['detail'] as String,
      ruleExplanation: json['ruleExplanation'] as String,
      decisionExplanation: json['decisionExplanation'] as String,
      evidenceExplanation: json['evidenceExplanation'] as String,
      impactExplanation: json['impactExplanation'] as String,
      remediationHint: json['remediationHint'] as String?,
      templateId: json['templateId'] as String,
      parameters: (json['parameters'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Result of evaluating a single rule.
class QualityGateEvaluation {
  const QualityGateEvaluation({
    required this.ruleId,
    required this.status,
    required this.decisionImpact,
    required this.severity,
    required this.requirement,
    required this.target,
    required this.operator,
    required this.evidence,
    required this.explanation,
    required this.evaluationFingerprint,
    this.ruleSetId,
    this.selector = const QualityGateRuleSelector(),
    this.expectedValue,
    this.actualValue,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final String ruleId;
  final String? ruleSetId;
  final QualityGateRuleStatus status;
  final QualityGateDecisionImpact decisionImpact;
  final QualityGateRuleSeverity severity;
  final QualityGateRuleRequirement requirement;
  final QualityGateRuleTarget target;
  final QualityGateRuleSelector selector;
  final QualityGateRuleOperator operator;
  final QualityGateRuleValue? expectedValue;
  final QualityGateRuleValue? actualValue;
  final List<QualityGateEvidence> evidence;
  final QualityGateExplanation explanation;
  final List<QualityGateWarning> warnings;
  final List<QualityGateError> errors;
  final List<QualityGateLimitation> limitations;
  final String evaluationFingerprint;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        if (ruleSetId != null) 'ruleSetId': ruleSetId,
        'status': status.wireName,
        'decisionImpact': decisionImpact.wireName,
        'severity': severity.wireName,
        'requirement': requirement.wireName,
        'target': target.wireName,
        'selector': selector.toJson(),
        'operator': operator.wireName,
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        if (actualValue != null) 'actualValue': actualValue!.toJson(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'explanation': explanation.toJson(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
        'evaluationFingerprint': evaluationFingerprint,
      };

  factory QualityGateEvaluation.fromJson(Map<String, dynamic> json) {
    return QualityGateEvaluation(
      ruleId: json['ruleId'] as String,
      ruleSetId: json['ruleSetId'] as String?,
      status: QualityGateRuleStatusX.fromWireName(json['status'] as String),
      decisionImpact: QualityGateDecisionImpactX.fromWireName(
        json['decisionImpact'] as String,
      ),
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      requirement: QualityGateRuleRequirementX.fromWireName(
        json['requirement'] as String,
      ),
      target: QualityGateRuleTargetX.fromWireName(json['target'] as String),
      selector: QualityGateRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      operator:
          QualityGateRuleOperatorX.fromWireName(json['operator'] as String),
      expectedValue: json['expectedValue'] == null
          ? null
          : QualityGateRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      actualValue: json['actualValue'] == null
          ? null
          : QualityGateRuleValue.fromJson(
              json['actualValue'] as Map<String, dynamic>,
            ),
      evidence: (json['evidence'] as List<dynamic>)
          .map((e) => QualityGateEvidence.fromJson(e as Map<String, dynamic>))
          .toList(),
      explanation: QualityGateExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
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
      evaluationFingerprint: json['evaluationFingerprint'] as String,
    );
  }
}
