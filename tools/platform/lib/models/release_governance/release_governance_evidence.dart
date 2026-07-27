import 'release_governance_enums.dart';
import 'release_governance_messages.dart';
import 'release_governance_rule_value.dart';

/// Source reference for release governance artifacts.
class ReleaseGovernanceSourceReference {
  const ReleaseGovernanceSourceReference({
    required this.sourceType,
    required this.resolutionMode,
    required this.requestedId,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.policyId,
    this.policyVersion,
    this.commitId,
    this.compatibility = ReleaseGovernanceCompatibilityStatus.unknown,
    this.limitations = const [],
  });

  final ReleaseGovernanceSourceType sourceType;
  final ReleaseGovernanceSourceResolutionMode resolutionMode;
  final String requestedId;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? policyId;
  final int? policyVersion;
  final String? commitId;
  final ReleaseGovernanceCompatibilityStatus compatibility;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'resolutionMode': resolutionMode.wireName,
        'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (commitId != null) 'commitId': commitId,
        'compatibility': compatibility.wireName,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseGovernanceSourceReference.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceTypeX.fromWireName(
        json['sourceType'] as String,
      ),
      resolutionMode: ReleaseGovernanceSourceResolutionModeX.fromWireName(
        json['resolutionMode'] as String,
      ),
      requestedId: json['requestedId'] as String,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      commitId: json['commitId'] as String?,
      compatibility: ReleaseGovernanceCompatibilityStatusX.fromWireName(
        json['compatibility'] as String? ?? 'unknown',
      ),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Typed evidence reference — no full snapshot duplication.
class ReleaseGovernanceEvidence {
  const ReleaseGovernanceEvidence({
    required this.evidenceId,
    required this.evidenceType,
    required this.sourceArtifactId,
    required this.status,
    required this.observedAt,
    required this.fingerprint,
    this.sourceFingerprint,
    this.sourceType,
    this.authorityId,
    this.ruleId,
    this.approvalId,
    this.waiverId,
    this.observedValue,
    this.expectedValue,
    this.reference,
    this.limitations = const [],
  });

  final String evidenceId;
  final ReleaseGovernanceEvidenceType evidenceType;
  final String sourceArtifactId;
  final String? sourceFingerprint;
  final String? sourceType;
  final String? authorityId;
  final String? ruleId;
  final String? approvalId;
  final String? waiverId;
  final ReleaseGovernanceRuleValue? observedValue;
  final ReleaseGovernanceRuleValue? expectedValue;
  final String status;
  final String observedAt;
  final ReleaseGovernanceSourceReference? reference;
  final String fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'evidenceType': evidenceType.wireName,
        'sourceArtifactId': sourceArtifactId,
        if (sourceFingerprint != null) 'sourceFingerprint': sourceFingerprint,
        if (sourceType != null) 'sourceType': sourceType,
        if (authorityId != null) 'authorityId': authorityId,
        if (ruleId != null) 'ruleId': ruleId,
        if (approvalId != null) 'approvalId': approvalId,
        if (waiverId != null) 'waiverId': waiverId,
        if (observedValue != null) 'observedValue': observedValue!.toJson(),
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        'status': status,
        'observedAt': observedAt,
        if (reference != null) 'reference': reference!.toJson(),
        'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseGovernanceEvidence.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceEvidence(
      evidenceId: json['evidenceId'] as String,
      evidenceType: ReleaseGovernanceEvidenceTypeX.fromWireName(
        json['evidenceType'] as String,
      ),
      sourceArtifactId: json['sourceArtifactId'] as String,
      sourceFingerprint: json['sourceFingerprint'] as String?,
      sourceType: json['sourceType'] as String?,
      authorityId: json['authorityId'] as String?,
      ruleId: json['ruleId'] as String?,
      approvalId: json['approvalId'] as String?,
      waiverId: json['waiverId'] as String?,
      observedValue: json['observedValue'] == null
          ? null
          : ReleaseGovernanceRuleValue.fromJson(
              json['observedValue'] as Map<String, dynamic>,
            ),
      expectedValue: json['expectedValue'] == null
          ? null
          : ReleaseGovernanceRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      status: json['status'] as String,
      observedAt: json['observedAt'] as String,
      reference: json['reference'] == null
          ? null
          : ReleaseGovernanceSourceReference.fromJson(
              json['reference'] as Map<String, dynamic>,
            ),
      fingerprint: json['fingerprint'] as String,
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ReleaseGovernanceCompatibilityCheck {
  const ReleaseGovernanceCompatibilityCheck({
    required this.checkId,
    required this.checkType,
    required this.status,
    this.expected,
    this.actual,
    this.reasons = const [],
    this.sourceReference,
    this.limitations = const [],
  });

  final String checkId;
  final String checkType;
  final ReleaseGovernanceCompatibilityStatus status;
  final String? expected;
  final String? actual;
  final List<String> reasons;
  final ReleaseGovernanceSourceReference? sourceReference;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'checkId': checkId,
        'checkType': checkType,
        'status': status.wireName,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        if (reasons.isNotEmpty) 'reasons': reasons,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseGovernanceCompatibilityCheck.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceCompatibilityCheck(
      checkId: json['checkId'] as String,
      checkType: json['checkType'] as String,
      status: ReleaseGovernanceCompatibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      expected: json['expected'] as String?,
      actual: json['actual'] as String?,
      reasons: (json['reasons'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseGovernanceSourceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ReleaseGovernanceCompatibility {
  const ReleaseGovernanceCompatibility({
    required this.status,
    required this.checks,
    required this.compatibleSources,
    required this.partiallyCompatibleSources,
    required this.incompatibleSources,
    required this.unknownSources,
    required this.reasons,
    required this.compatibilityFingerprint,
  });

  final ReleaseGovernanceCompatibilityStatus status;
  final List<ReleaseGovernanceCompatibilityCheck> checks;
  final List<ReleaseGovernanceSourceType> compatibleSources;
  final List<ReleaseGovernanceSourceType> partiallyCompatibleSources;
  final List<ReleaseGovernanceSourceType> incompatibleSources;
  final List<ReleaseGovernanceSourceType> unknownSources;
  final List<String> reasons;
  final String compatibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'checks': checks.map((e) => e.toJson()).toList(),
        'compatibleSources': compatibleSources.map((e) => e.wireName).toList(),
        'partiallyCompatibleSources':
            partiallyCompatibleSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'unknownSources': unknownSources.map((e) => e.wireName).toList(),
        'reasons': reasons,
        'compatibilityFingerprint': compatibilityFingerprint,
      };

  factory ReleaseGovernanceCompatibility.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceCompatibility(
      status: ReleaseGovernanceCompatibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      checks: (json['checks'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceCompatibilityCheck.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      compatibleSources: (json['compatibleSources'] as List<dynamic>)
          .map((e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String))
          .toList(),
      partiallyCompatibleSources:
          (json['partiallyCompatibleSources'] as List<dynamic>)
              .map(
                (e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String),
              )
              .toList(),
      incompatibleSources: (json['incompatibleSources'] as List<dynamic>)
          .map((e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String))
          .toList(),
      unknownSources: (json['unknownSources'] as List<dynamic>)
          .map((e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String))
          .toList(),
      reasons:
          (json['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
      compatibilityFingerprint: json['compatibilityFingerprint'] as String,
    );
  }
}

class ReleaseGovernanceEligibility {
  const ReleaseGovernanceEligibility({
    required this.status,
    required this.reasons,
    required this.missingSources,
    required this.incompatibleSources,
    required this.eligibilityFingerprint,
  });

  final ReleaseGovernanceEligibilityStatus status;
  final List<String> reasons;
  final List<ReleaseGovernanceSourceType> missingSources;
  final List<ReleaseGovernanceSourceType> incompatibleSources;
  final String eligibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'reasons': reasons,
        'missingSources': missingSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'eligibilityFingerprint': eligibilityFingerprint,
      };

  factory ReleaseGovernanceEligibility.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceEligibility(
      status: ReleaseGovernanceEligibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      reasons:
          (json['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
      missingSources: (json['missingSources'] as List<dynamic>)
          .map((e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String))
          .toList(),
      incompatibleSources: (json['incompatibleSources'] as List<dynamic>)
          .map((e) => ReleaseGovernanceSourceTypeX.fromWireName(e as String))
          .toList(),
      eligibilityFingerprint: json['eligibilityFingerprint'] as String,
    );
  }
}

class ReleaseGovernanceCoverage {
  const ReleaseGovernanceCoverage({
    required this.totalRuleCount,
    required this.enabledRuleCount,
    required this.evaluatedRuleCount,
    required this.passedRuleCount,
    required this.failedRuleCount,
    required this.pendingRuleCount,
    required this.waivedRuleCount,
    required this.unavailableRuleCount,
    required this.incompatibleRuleCount,
    required this.requiredRuleCount,
    required this.requiredRuleEvaluatedCount,
    required this.approvalRequirementCount,
    required this.approvalRequirementSatisfiedCount,
    required this.waiverEvaluationCount,
    required this.validWaiverCount,
    required this.evidenceRequiredCount,
    required this.evidencePresentCount,
    required this.ruleCoveragePercentage,
    required this.requiredRuleCoveragePercentage,
    required this.approvalCoveragePercentage,
    required this.evidenceCoveragePercentage,
    required this.sourceCoveragePercentage,
    required this.fingerprint,
  });

  final int totalRuleCount;
  final int enabledRuleCount;
  final int evaluatedRuleCount;
  final int passedRuleCount;
  final int failedRuleCount;
  final int pendingRuleCount;
  final int waivedRuleCount;
  final int unavailableRuleCount;
  final int incompatibleRuleCount;
  final int requiredRuleCount;
  final int requiredRuleEvaluatedCount;
  final int approvalRequirementCount;
  final int approvalRequirementSatisfiedCount;
  final int waiverEvaluationCount;
  final int validWaiverCount;
  final int evidenceRequiredCount;
  final int evidencePresentCount;
  final double ruleCoveragePercentage;
  final double requiredRuleCoveragePercentage;
  final double approvalCoveragePercentage;
  final double evidenceCoveragePercentage;
  final double sourceCoveragePercentage;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'totalRuleCount': totalRuleCount,
        'enabledRuleCount': enabledRuleCount,
        'evaluatedRuleCount': evaluatedRuleCount,
        'passedRuleCount': passedRuleCount,
        'failedRuleCount': failedRuleCount,
        'pendingRuleCount': pendingRuleCount,
        'waivedRuleCount': waivedRuleCount,
        'unavailableRuleCount': unavailableRuleCount,
        'incompatibleRuleCount': incompatibleRuleCount,
        'requiredRuleCount': requiredRuleCount,
        'requiredRuleEvaluatedCount': requiredRuleEvaluatedCount,
        'approvalRequirementCount': approvalRequirementCount,
        'approvalRequirementSatisfiedCount': approvalRequirementSatisfiedCount,
        'waiverEvaluationCount': waiverEvaluationCount,
        'validWaiverCount': validWaiverCount,
        'evidenceRequiredCount': evidenceRequiredCount,
        'evidencePresentCount': evidencePresentCount,
        'ruleCoveragePercentage': ruleCoveragePercentage,
        'requiredRuleCoveragePercentage': requiredRuleCoveragePercentage,
        'approvalCoveragePercentage': approvalCoveragePercentage,
        'evidenceCoveragePercentage': evidenceCoveragePercentage,
        'sourceCoveragePercentage': sourceCoveragePercentage,
        'fingerprint': fingerprint,
      };

  factory ReleaseGovernanceCoverage.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceCoverage(
      totalRuleCount: json['totalRuleCount'] as int,
      enabledRuleCount: json['enabledRuleCount'] as int,
      evaluatedRuleCount: json['evaluatedRuleCount'] as int,
      passedRuleCount: json['passedRuleCount'] as int,
      failedRuleCount: json['failedRuleCount'] as int,
      pendingRuleCount: json['pendingRuleCount'] as int,
      waivedRuleCount: json['waivedRuleCount'] as int,
      unavailableRuleCount: json['unavailableRuleCount'] as int,
      incompatibleRuleCount: json['incompatibleRuleCount'] as int,
      requiredRuleCount: json['requiredRuleCount'] as int,
      requiredRuleEvaluatedCount: json['requiredRuleEvaluatedCount'] as int,
      approvalRequirementCount: json['approvalRequirementCount'] as int,
      approvalRequirementSatisfiedCount:
          json['approvalRequirementSatisfiedCount'] as int,
      waiverEvaluationCount: json['waiverEvaluationCount'] as int,
      validWaiverCount: json['validWaiverCount'] as int,
      evidenceRequiredCount: json['evidenceRequiredCount'] as int,
      evidencePresentCount: json['evidencePresentCount'] as int,
      ruleCoveragePercentage:
          (json['ruleCoveragePercentage'] as num).toDouble(),
      requiredRuleCoveragePercentage:
          (json['requiredRuleCoveragePercentage'] as num).toDouble(),
      approvalCoveragePercentage:
          (json['approvalCoveragePercentage'] as num).toDouble(),
      evidenceCoveragePercentage:
          (json['evidenceCoveragePercentage'] as num).toDouble(),
      sourceCoveragePercentage:
          (json['sourceCoveragePercentage'] as num).toDouble(),
      fingerprint: json['fingerprint'] as String,
    );
  }
}

class ReleaseCondition {
  const ReleaseCondition({
    required this.conditionId,
    required this.type,
    required this.description,
    required this.owner,
    required this.severity,
    required this.status,
    required this.evidenceRequired,
    required this.fingerprint,
    this.dueAt,
    this.sourceRuleId,
    this.sourceWaiverId,
    this.sourceApprovalRequirementId,
  });

  final String conditionId;
  final ReleaseConditionType type;
  final String description;
  final String owner;
  final String? dueAt;
  final String? sourceRuleId;
  final String? sourceWaiverId;
  final String? sourceApprovalRequirementId;
  final ReleaseGovernanceRuleSeverity severity;
  final ReleaseConditionStatus status;
  final bool evidenceRequired;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'conditionId': conditionId,
        'type': type.wireName,
        'description': description,
        'owner': owner,
        if (dueAt != null) 'dueAt': dueAt,
        if (sourceRuleId != null) 'sourceRuleId': sourceRuleId,
        if (sourceWaiverId != null) 'sourceWaiverId': sourceWaiverId,
        if (sourceApprovalRequirementId != null)
          'sourceApprovalRequirementId': sourceApprovalRequirementId,
        'severity': severity.wireName,
        'status': status.wireName,
        'evidenceRequired': evidenceRequired,
        'fingerprint': fingerprint,
      };

  factory ReleaseCondition.fromJson(Map<String, dynamic> json) {
    return ReleaseCondition(
      conditionId: json['conditionId'] as String,
      type: ReleaseConditionTypeX.fromWireName(json['type'] as String),
      description: json['description'] as String,
      owner: json['owner'] as String,
      dueAt: json['dueAt'] as String?,
      sourceRuleId: json['sourceRuleId'] as String?,
      sourceWaiverId: json['sourceWaiverId'] as String?,
      sourceApprovalRequirementId:
          json['sourceApprovalRequirementId'] as String?,
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      status: ReleaseConditionStatusX.fromWireName(json['status'] as String),
      evidenceRequired: json['evidenceRequired'] as bool,
      fingerprint: json['fingerprint'] as String,
    );
  }
}

class ReleaseGovernanceEvaluation {
  const ReleaseGovernanceEvaluation({
    required this.evaluationId,
    required this.ruleId,
    required this.ruleSetId,
    required this.target,
    required this.operator,
    required this.status,
    required this.decisionImpact,
    required this.explanation,
    required this.fingerprint,
    this.selector = const ReleaseGovernanceRuleSelector(),
    this.expectedValue,
    this.actualValue,
    this.evidenceIds = const [],
    this.approvalIds = const [],
    this.waiverIds = const [],
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final String evaluationId;
  final String ruleId;
  final String ruleSetId;
  final ReleaseGovernanceRuleTarget target;
  final ReleaseGovernanceRuleOperator operator;
  final ReleaseGovernanceRuleSelector selector;
  final ReleaseGovernanceRuleValue? expectedValue;
  final ReleaseGovernanceRuleValue? actualValue;
  final ReleaseGovernanceRuleStatus status;
  final ReleaseGovernanceDecisionImpact decisionImpact;
  final List<String> evidenceIds;
  final List<String> approvalIds;
  final List<String> waiverIds;
  final ReleaseGovernanceExplanation explanation;
  final List<String> warnings;
  final List<String> errors;
  final List<String> limitations;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'evaluationId': evaluationId,
        'ruleId': ruleId,
        'ruleSetId': ruleSetId,
        'target': target.wireName,
        'operator': operator.wireName,
        'selector': selector.toJson(),
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        if (actualValue != null) 'actualValue': actualValue!.toJson(),
        'status': status.wireName,
        'decisionImpact': decisionImpact.wireName,
        'evidenceIds': evidenceIds,
        'approvalIds': approvalIds,
        'waiverIds': waiverIds,
        'explanation': explanation.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (errors.isNotEmpty) 'errors': errors,
        if (limitations.isNotEmpty) 'limitations': limitations,
        'fingerprint': fingerprint,
      };

  factory ReleaseGovernanceEvaluation.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceEvaluation(
      evaluationId: json['evaluationId'] as String,
      ruleId: json['ruleId'] as String,
      ruleSetId: json['ruleSetId'] as String,
      target: ReleaseGovernanceRuleTargetX.fromWireName(
        json['target'] as String,
      ),
      operator: ReleaseGovernanceRuleOperatorX.fromWireName(
        json['operator'] as String,
      ),
      selector: ReleaseGovernanceRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      expectedValue: json['expectedValue'] == null
          ? null
          : ReleaseGovernanceRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      actualValue: json['actualValue'] == null
          ? null
          : ReleaseGovernanceRuleValue.fromJson(
              json['actualValue'] as Map<String, dynamic>,
            ),
      status: ReleaseGovernanceRuleStatusX.fromWireName(
        json['status'] as String,
      ),
      decisionImpact: ReleaseGovernanceDecisionImpactX.fromWireName(
        json['decisionImpact'] as String,
      ),
      evidenceIds: (json['evidenceIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      approvalIds: (json['approvalIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      waiverIds: (json['waiverIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      explanation: ReleaseGovernanceExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
      ),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fingerprint: json['fingerprint'] as String,
    );
  }
}

class ReleaseWaiverEvaluation {
  const ReleaseWaiverEvaluation({
    required this.waiverId,
    required this.status,
    required this.scopeValid,
    required this.authorityValid,
    required this.expirationValid,
    required this.policyValid,
    required this.releaseValid,
    required this.commitValid,
    required this.environmentValid,
    required this.ruleCoverageValid,
    required this.compensatingControlsValid,
    required this.usageValid,
    required this.decisionImpact,
    required this.explanation,
    required this.fingerprint,
    this.affectedEvaluationIds = const [],
    this.evidenceIds = const [],
  });

  final String waiverId;
  final ReleaseWaiverStatus status;
  final bool scopeValid;
  final bool authorityValid;
  final bool expirationValid;
  final bool policyValid;
  final bool releaseValid;
  final bool commitValid;
  final bool environmentValid;
  final bool ruleCoverageValid;
  final bool compensatingControlsValid;
  final bool usageValid;
  final List<String> affectedEvaluationIds;
  final ReleaseGovernanceDecisionImpact decisionImpact;
  final List<String> evidenceIds;
  final ReleaseGovernanceExplanation explanation;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'waiverId': waiverId,
        'status': status.wireName,
        'scopeValid': scopeValid,
        'authorityValid': authorityValid,
        'expirationValid': expirationValid,
        'policyValid': policyValid,
        'releaseValid': releaseValid,
        'commitValid': commitValid,
        'environmentValid': environmentValid,
        'ruleCoverageValid': ruleCoverageValid,
        'compensatingControlsValid': compensatingControlsValid,
        'usageValid': usageValid,
        'affectedEvaluationIds': affectedEvaluationIds,
        'decisionImpact': decisionImpact.wireName,
        'evidenceIds': evidenceIds,
        'explanation': explanation.toJson(),
        'fingerprint': fingerprint,
      };

  factory ReleaseWaiverEvaluation.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverEvaluation(
      waiverId: json['waiverId'] as String,
      status: ReleaseWaiverStatusX.fromWireName(json['status'] as String),
      scopeValid: json['scopeValid'] as bool,
      authorityValid: json['authorityValid'] as bool,
      expirationValid: json['expirationValid'] as bool,
      policyValid: json['policyValid'] as bool,
      releaseValid: json['releaseValid'] as bool,
      commitValid: json['commitValid'] as bool,
      environmentValid: json['environmentValid'] as bool,
      ruleCoverageValid: json['ruleCoverageValid'] as bool,
      compensatingControlsValid: json['compensatingControlsValid'] as bool,
      usageValid: json['usageValid'] as bool,
      affectedEvaluationIds:
          (json['affectedEvaluationIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      decisionImpact: ReleaseGovernanceDecisionImpactX.fromWireName(
        json['decisionImpact'] as String,
      ),
      evidenceIds: (json['evidenceIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      explanation: ReleaseGovernanceExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
      ),
      fingerprint: json['fingerprint'] as String,
    );
  }
}

/// Reference to a published Quality Gate snapshot.
class ReleaseQualityGateReference {
  const ReleaseQualityGateReference({
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.policyId,
    required this.policyVersion,
    required this.decision,
    this.projectId,
    this.commitId,
  });

  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final String policyId;
  final int policyVersion;
  final String decision;
  final String? projectId;
  final String? commitId;

  Map<String, dynamic> toJson() => {
        'qualityGateSnapshotId': qualityGateSnapshotId,
        'qualityGateFingerprint': qualityGateFingerprint,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'decision': decision,
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
      };

  factory ReleaseQualityGateReference.fromJson(Map<String, dynamic> json) {
    return ReleaseQualityGateReference(
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      decision: json['decision'] as String,
      projectId: json['projectId'] as String?,
      commitId: json['commitId'] as String?,
    );
  }
}
