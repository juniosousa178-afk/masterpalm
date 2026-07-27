import 'release_approval.dart';
import 'release_governance_enums.dart';
import 'release_governance_rule_value.dart';
import 'release_waiver.dart';

/// Policy lifecycle metadata.
class ReleaseGovernancePolicyMetadata {
  const ReleaseGovernancePolicyMetadata({
    required this.policyId,
    required this.policyVersion,
    required this.displayName,
    required this.description,
    required this.owner,
    required this.status,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.changelog,
    required this.rationale,
    this.updatedAt,
    this.tags = const [],
    this.fingerprint,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String policyId;
  final int policyVersion;
  final String displayName;
  final String description;
  final String owner;
  final ReleaseGovernancePolicyStatus status;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String? updatedAt;
  final List<ReleaseGovernancePolicyChangelogEntry> changelog;
  final String rationale;
  final List<String> tags;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'displayName': displayName,
        'description': description,
        'owner': owner,
        'status': status.wireName,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        'changelog': changelog.map((e) => e.toJson()).toList(),
        'rationale': rationale,
        if (tags.isNotEmpty) 'tags': tags,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory ReleaseGovernancePolicyMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernancePolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      description: json['description'] as String,
      owner: json['owner'] as String,
      status: ReleaseGovernancePolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String?,
      changelog: (json['changelog'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernancePolicyChangelogEntry.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      rationale: json['rationale'] as String,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fingerprint: json['fingerprint'] as String?,
    );
  }
}

class ReleaseGovernancePolicyChangelogEntry {
  const ReleaseGovernancePolicyChangelogEntry({
    required this.version,
    required this.summary,
    required this.author,
    required this.createdAt,
  });

  final int version;
  final String summary;
  final String author;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'summary': summary,
        'author': author,
        'createdAt': createdAt,
      };

  factory ReleaseGovernancePolicyChangelogEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernancePolicyChangelogEntry(
      version: json['version'] as int,
      summary: json['summary'] as String,
      author: json['author'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Governance metadata for a release governance policy.
class ReleaseGovernanceGovernance {
  const ReleaseGovernanceGovernance({
    required this.policyOwner,
    required this.approvalAuthority,
    required this.policyApprovalStatus,
    required this.versioningStrategy,
    required this.rollbackPolicy,
    required this.emergencyPolicy,
    required this.waiverPolicy,
    required this.evidenceRequirements,
    required this.compatibilityRequirements,
    required this.retentionRequirements,
    required this.reviewCadence,
    required this.escalationAuthority,
    this.releaseApprovalAuthority,
    this.waiverGrantAuthority,
  });

  final String policyOwner;
  final String approvalAuthority;
  final String policyApprovalStatus;
  final String versioningStrategy;
  final String rollbackPolicy;
  final String emergencyPolicy;
  final String waiverPolicy;
  final String evidenceRequirements;
  final String compatibilityRequirements;
  final String retentionRequirements;
  final String reviewCadence;
  final String escalationAuthority;
  final String? releaseApprovalAuthority;
  final String? waiverGrantAuthority;

  Map<String, dynamic> toJson() => {
        'policyOwner': policyOwner,
        'approvalAuthority': approvalAuthority,
        'policyApprovalStatus': policyApprovalStatus,
        'versioningStrategy': versioningStrategy,
        'rollbackPolicy': rollbackPolicy,
        'emergencyPolicy': emergencyPolicy,
        'waiverPolicy': waiverPolicy,
        'evidenceRequirements': evidenceRequirements,
        'compatibilityRequirements': compatibilityRequirements,
        'retentionRequirements': retentionRequirements,
        'reviewCadence': reviewCadence,
        'escalationAuthority': escalationAuthority,
        if (releaseApprovalAuthority != null)
          'releaseApprovalAuthority': releaseApprovalAuthority,
        if (waiverGrantAuthority != null)
          'waiverGrantAuthority': waiverGrantAuthority,
      };

  factory ReleaseGovernanceGovernance.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceGovernance(
      policyOwner: json['policyOwner'] as String,
      approvalAuthority: json['approvalAuthority'] as String,
      policyApprovalStatus: json['policyApprovalStatus'] as String,
      versioningStrategy: json['versioningStrategy'] as String,
      rollbackPolicy: json['rollbackPolicy'] as String,
      emergencyPolicy: json['emergencyPolicy'] as String,
      waiverPolicy: json['waiverPolicy'] as String,
      evidenceRequirements: json['evidenceRequirements'] as String,
      compatibilityRequirements: json['compatibilityRequirements'] as String,
      retentionRequirements: json['retentionRequirements'] as String,
      reviewCadence: json['reviewCadence'] as String,
      escalationAuthority: json['escalationAuthority'] as String,
      releaseApprovalAuthority: json['releaseApprovalAuthority'] as String?,
      waiverGrantAuthority: json['waiverGrantAuthority'] as String?,
    );
  }
}

/// Per-rule evidence requirement declaration.
class ReleaseGovernanceEvidenceRequirement {
  const ReleaseGovernanceEvidenceRequirement({
    required this.requireSourceReference,
    required this.requireFingerprint,
    required this.minimumEvidenceCount,
    this.requireAuthorityEvidence = false,
    this.requireObservedValue = true,
  });

  final bool requireSourceReference;
  final bool requireFingerprint;
  final int minimumEvidenceCount;
  final bool requireAuthorityEvidence;
  final bool requireObservedValue;

  Map<String, dynamic> toJson() => {
        'requireSourceReference': requireSourceReference,
        'requireFingerprint': requireFingerprint,
        'minimumEvidenceCount': minimumEvidenceCount,
        'requireAuthorityEvidence': requireAuthorityEvidence,
        'requireObservedValue': requireObservedValue,
      };

  factory ReleaseGovernanceEvidenceRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceEvidenceRequirement(
      requireSourceReference: json['requireSourceReference'] as bool,
      requireFingerprint: json['requireFingerprint'] as bool,
      minimumEvidenceCount: json['minimumEvidenceCount'] as int,
      requireAuthorityEvidence:
          json['requireAuthorityEvidence'] as bool? ?? false,
      requireObservedValue: json['requireObservedValue'] as bool? ?? true,
    );
  }
}

/// Declarative release governance rule.
class ReleaseGovernanceRule {
  const ReleaseGovernanceRule({
    required this.ruleId,
    required this.ruleSetId,
    required this.name,
    required this.description,
    required this.target,
    required this.operator,
    required this.severity,
    required this.requirement,
    required this.missingDataPolicy,
    required this.incompatibleDataPolicy,
    required this.evidenceRequirement,
    required this.waiverCapability,
    required this.rationale,
    required this.order,
    this.selector = const ReleaseGovernanceRuleSelector(),
    this.expectedValue,
    this.enabled = true,
    this.tags = const [],
  });

  final String ruleId;
  final String ruleSetId;
  final String name;
  final String description;
  final ReleaseGovernanceRuleTarget target;
  final ReleaseGovernanceRuleSelector selector;
  final ReleaseGovernanceRuleOperator operator;
  final ReleaseGovernanceRuleValue? expectedValue;
  final ReleaseGovernanceRuleSeverity severity;
  final ReleaseGovernanceRuleRequirement requirement;
  final ReleaseGovernanceMissingDataPolicy missingDataPolicy;
  final ReleaseGovernanceIncompatibleDataPolicy incompatibleDataPolicy;
  final ReleaseGovernanceEvidenceRequirement evidenceRequirement;
  final ReleaseGovernanceWaiverCapability waiverCapability;
  final String rationale;
  final bool enabled;
  final int order;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'ruleSetId': ruleSetId,
        'name': name,
        'description': description,
        'target': target.wireName,
        'selector': selector.toJson(),
        'operator': operator.wireName,
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        'severity': severity.wireName,
        'requirement': requirement.wireName,
        'missingDataPolicy': missingDataPolicy.wireName,
        'incompatibleDataPolicy': incompatibleDataPolicy.wireName,
        'evidenceRequirement': evidenceRequirement.toJson(),
        'waiverCapability': waiverCapability.wireName,
        'rationale': rationale,
        'enabled': enabled,
        'order': order,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory ReleaseGovernanceRule.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceRule(
      ruleId: json['ruleId'] as String,
      ruleSetId: json['ruleSetId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      target: ReleaseGovernanceRuleTargetX.fromWireName(
        json['target'] as String,
      ),
      selector: ReleaseGovernanceRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      operator: ReleaseGovernanceRuleOperatorX.fromWireName(
        json['operator'] as String,
      ),
      expectedValue: json['expectedValue'] == null
          ? null
          : ReleaseGovernanceRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      requirement: ReleaseGovernanceRuleRequirementX.fromWireName(
        json['requirement'] as String,
      ),
      missingDataPolicy: ReleaseGovernanceMissingDataPolicyX.fromWireName(
        json['missingDataPolicy'] as String,
      ),
      incompatibleDataPolicy:
          ReleaseGovernanceIncompatibleDataPolicyX.fromWireName(
        json['incompatibleDataPolicy'] as String,
      ),
      evidenceRequirement: ReleaseGovernanceEvidenceRequirement.fromJson(
        json['evidenceRequirement'] as Map<String, dynamic>,
      ),
      waiverCapability: ReleaseGovernanceWaiverCapabilityX.fromWireName(
        json['waiverCapability'] as String,
      ),
      rationale: json['rationale'] as String,
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Logical grouping of release governance rules.
class ReleaseGovernanceRuleSet {
  const ReleaseGovernanceRuleSet({
    required this.ruleSetId,
    required this.name,
    required this.description,
    required this.order,
    required this.enabled,
    required this.required,
    required this.severity,
    required this.aggregationMode,
    required this.ruleIds,
    required this.rationale,
    this.minimumPassCount,
    this.minimumPassPercentage,
    this.tags = const [],
  });

  final String ruleSetId;
  final String name;
  final String description;
  final int order;
  final bool enabled;
  final bool required;
  final ReleaseGovernanceRuleSeverity severity;
  final ReleaseGovernanceRuleSetAggregationMode aggregationMode;
  final int? minimumPassCount;
  final double? minimumPassPercentage;
  final List<String> ruleIds;
  final String rationale;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'ruleSetId': ruleSetId,
        'name': name,
        'description': description,
        'order': order,
        'enabled': enabled,
        'required': required,
        'severity': severity.wireName,
        'aggregationMode': aggregationMode.wireName,
        if (minimumPassCount != null) 'minimumPassCount': minimumPassCount,
        if (minimumPassPercentage != null)
          'minimumPassPercentage': minimumPassPercentage,
        'ruleIds': ruleIds,
        'rationale': rationale,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory ReleaseGovernanceRuleSet.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceRuleSet(
      ruleSetId: json['ruleSetId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      order: json['order'] as int,
      enabled: json['enabled'] as bool? ?? true,
      required: json['required'] as bool,
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      aggregationMode: ReleaseGovernanceRuleSetAggregationModeX.fromWireName(
        json['aggregationMode'] as String,
      ),
      minimumPassCount: json['minimumPassCount'] as int?,
      minimumPassPercentage:
          (json['minimumPassPercentage'] as num?)?.toDouble(),
      ruleIds:
          (json['ruleIds'] as List<dynamic>).map((e) => e.toString()).toList(),
      rationale: json['rationale'] as String,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Decision aggregation policy for release governance.
class ReleaseGovernanceDecisionPolicy {
  const ReleaseGovernanceDecisionPolicy({
    this.requiredFailuresReject = true,
    this.blockingFailuresReject = true,
    this.criticalFailuresReject = true,
    this.optionalFailuresCreateConditions = false,
    this.missingApprovalsCreatePending = true,
    this.rejectedApprovalRejects = true,
    this.expiredApprovalCreatesPending = true,
    this.validWaiverMayCreateConditionalApproval = true,
    this.warningMayCreateCondition = true,
    this.partialCompatibilityAllowed = false,
    this.partialEligibilityAllowed = false,
    this.minimumRuleCoverage = 100,
    this.minimumApprovalCoverage = 100,
    this.minimumEvidenceCoverage = 100,
    this.qualityGateAcceptedDecisions = const ['passed'],
    this.qualityGateConditionalDecisions = const ['partial'],
    this.qualityGateRejectedDecisions = const [
      'failed',
      'unavailable',
      'incompatible',
      'error'
    ],
    this.allowEmergencyOverride = false,
    this.allowHistoricalEvaluation = false,
    this.allowRetiredPolicyForHistoricalEvaluation = false,
  });

  final bool requiredFailuresReject;
  final bool blockingFailuresReject;
  final bool criticalFailuresReject;
  final bool optionalFailuresCreateConditions;
  final bool missingApprovalsCreatePending;
  final bool rejectedApprovalRejects;
  final bool expiredApprovalCreatesPending;
  final bool validWaiverMayCreateConditionalApproval;
  final bool warningMayCreateCondition;
  final bool partialCompatibilityAllowed;
  final bool partialEligibilityAllowed;
  final double minimumRuleCoverage;
  final double minimumApprovalCoverage;
  final double minimumEvidenceCoverage;
  final List<String> qualityGateAcceptedDecisions;
  final List<String> qualityGateConditionalDecisions;
  final List<String> qualityGateRejectedDecisions;
  final bool allowEmergencyOverride;
  final bool allowHistoricalEvaluation;
  final bool allowRetiredPolicyForHistoricalEvaluation;

  Map<String, dynamic> toJson() => {
        'requiredFailuresReject': requiredFailuresReject,
        'blockingFailuresReject': blockingFailuresReject,
        'criticalFailuresReject': criticalFailuresReject,
        'optionalFailuresCreateConditions': optionalFailuresCreateConditions,
        'missingApprovalsCreatePending': missingApprovalsCreatePending,
        'rejectedApprovalRejects': rejectedApprovalRejects,
        'expiredApprovalCreatesPending': expiredApprovalCreatesPending,
        'validWaiverMayCreateConditionalApproval':
            validWaiverMayCreateConditionalApproval,
        'warningMayCreateCondition': warningMayCreateCondition,
        'partialCompatibilityAllowed': partialCompatibilityAllowed,
        'partialEligibilityAllowed': partialEligibilityAllowed,
        'minimumRuleCoverage': minimumRuleCoverage,
        'minimumApprovalCoverage': minimumApprovalCoverage,
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
        'qualityGateAcceptedDecisions': qualityGateAcceptedDecisions,
        'qualityGateConditionalDecisions': qualityGateConditionalDecisions,
        'qualityGateRejectedDecisions': qualityGateRejectedDecisions,
        'allowEmergencyOverride': allowEmergencyOverride,
        'allowHistoricalEvaluation': allowHistoricalEvaluation,
        'allowRetiredPolicyForHistoricalEvaluation':
            allowRetiredPolicyForHistoricalEvaluation,
      };

  factory ReleaseGovernanceDecisionPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceDecisionPolicy(
      requiredFailuresReject: json['requiredFailuresReject'] as bool? ?? true,
      blockingFailuresReject: json['blockingFailuresReject'] as bool? ?? true,
      criticalFailuresReject: json['criticalFailuresReject'] as bool? ?? true,
      optionalFailuresCreateConditions:
          json['optionalFailuresCreateConditions'] as bool? ?? false,
      missingApprovalsCreatePending:
          json['missingApprovalsCreatePending'] as bool? ?? true,
      rejectedApprovalRejects: json['rejectedApprovalRejects'] as bool? ?? true,
      expiredApprovalCreatesPending:
          json['expiredApprovalCreatesPending'] as bool? ?? true,
      validWaiverMayCreateConditionalApproval:
          json['validWaiverMayCreateConditionalApproval'] as bool? ?? true,
      warningMayCreateCondition:
          json['warningMayCreateCondition'] as bool? ?? true,
      partialCompatibilityAllowed:
          json['partialCompatibilityAllowed'] as bool? ?? false,
      partialEligibilityAllowed:
          json['partialEligibilityAllowed'] as bool? ?? false,
      minimumRuleCoverage:
          (json['minimumRuleCoverage'] as num?)?.toDouble() ?? 100,
      minimumApprovalCoverage:
          (json['minimumApprovalCoverage'] as num?)?.toDouble() ?? 100,
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 100,
      qualityGateAcceptedDecisions:
          (json['qualityGateAcceptedDecisions'] as List<dynamic>? ?? ['passed'])
              .map((e) => e.toString())
              .toList(),
      qualityGateConditionalDecisions:
          (json['qualityGateConditionalDecisions'] as List<dynamic>? ??
                  ['partial'])
              .map((e) => e.toString())
              .toList(),
      qualityGateRejectedDecisions:
          (json['qualityGateRejectedDecisions'] as List<dynamic>? ??
                  ['failed', 'unavailable', 'incompatible', 'error'])
              .map((e) => e.toString())
              .toList(),
      allowEmergencyOverride: json['allowEmergencyOverride'] as bool? ?? false,
      allowHistoricalEvaluation:
          json['allowHistoricalEvaluation'] as bool? ?? false,
      allowRetiredPolicyForHistoricalEvaluation:
          json['allowRetiredPolicyForHistoricalEvaluation'] as bool? ?? false,
    );
  }
}

/// Evidence collection policy.
class ReleaseGovernanceEvidencePolicy {
  const ReleaseGovernanceEvidencePolicy({
    this.requireQualityGateFingerprint = true,
    this.requireQualityGateSnapshotId = true,
    this.requireApprovalEvidence = true,
    this.requireAuthorityEvidence = true,
    this.requireWaiverEvidence = true,
    this.requireCompensatingControlEvidence = true,
    this.requireReleaseArtifactReferences = false,
    this.requireCommitId = true,
    this.requireProjectId = true,
    this.requirePolicyFingerprint = true,
    this.minimumEvidenceCoverage = 100,
    this.allowDerivedEvidence = false,
    this.allowContextualEvidence = true,
    this.evidenceRetentionClass = 'standard',
  });

  final bool requireQualityGateFingerprint;
  final bool requireQualityGateSnapshotId;
  final bool requireApprovalEvidence;
  final bool requireAuthorityEvidence;
  final bool requireWaiverEvidence;
  final bool requireCompensatingControlEvidence;
  final bool requireReleaseArtifactReferences;
  final bool requireCommitId;
  final bool requireProjectId;
  final bool requirePolicyFingerprint;
  final double minimumEvidenceCoverage;
  final bool allowDerivedEvidence;
  final bool allowContextualEvidence;
  final String evidenceRetentionClass;

  Map<String, dynamic> toJson() => {
        'requireQualityGateFingerprint': requireQualityGateFingerprint,
        'requireQualityGateSnapshotId': requireQualityGateSnapshotId,
        'requireApprovalEvidence': requireApprovalEvidence,
        'requireAuthorityEvidence': requireAuthorityEvidence,
        'requireWaiverEvidence': requireWaiverEvidence,
        'requireCompensatingControlEvidence':
            requireCompensatingControlEvidence,
        'requireReleaseArtifactReferences': requireReleaseArtifactReferences,
        'requireCommitId': requireCommitId,
        'requireProjectId': requireProjectId,
        'requirePolicyFingerprint': requirePolicyFingerprint,
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
        'allowDerivedEvidence': allowDerivedEvidence,
        'allowContextualEvidence': allowContextualEvidence,
        'evidenceRetentionClass': evidenceRetentionClass,
      };

  factory ReleaseGovernanceEvidencePolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceEvidencePolicy(
      requireQualityGateFingerprint:
          json['requireQualityGateFingerprint'] as bool? ?? true,
      requireQualityGateSnapshotId:
          json['requireQualityGateSnapshotId'] as bool? ?? true,
      requireApprovalEvidence: json['requireApprovalEvidence'] as bool? ?? true,
      requireAuthorityEvidence:
          json['requireAuthorityEvidence'] as bool? ?? true,
      requireWaiverEvidence: json['requireWaiverEvidence'] as bool? ?? true,
      requireCompensatingControlEvidence:
          json['requireCompensatingControlEvidence'] as bool? ?? true,
      requireReleaseArtifactReferences:
          json['requireReleaseArtifactReferences'] as bool? ?? false,
      requireCommitId: json['requireCommitId'] as bool? ?? true,
      requireProjectId: json['requireProjectId'] as bool? ?? true,
      requirePolicyFingerprint:
          json['requirePolicyFingerprint'] as bool? ?? true,
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 100,
      allowDerivedEvidence: json['allowDerivedEvidence'] as bool? ?? false,
      allowContextualEvidence: json['allowContextualEvidence'] as bool? ?? true,
      evidenceRetentionClass:
          json['evidenceRetentionClass'] as String? ?? 'standard',
    );
  }
}

/// Compatibility policy for release governance inputs.
class ReleaseGovernanceCompatibilityPolicy {
  const ReleaseGovernanceCompatibilityPolicy({
    this.requireSameProject = true,
    this.requireSameCommit = true,
    this.requireSameBranch = false,
    this.requireSupportedEnvironment = true,
    this.requireSupportedReleaseType = true,
    this.requireQualityGatePolicyCompatibility = true,
    this.requireQualityGateSchemaCompatibility = true,
    this.requireApprovalPolicyCompatibility = true,
    this.requireWaiverPolicyCompatibility = true,
    this.requireAuthorityValidity = true,
    this.requireFingerprints = true,
    this.allowPartialCompatibility = false,
    this.allowedQualityGatePolicyIds = const [],
    this.allowedQualityGatePolicyVersions = const [],
    this.supportedSchemas = const [
      ReleaseGovernancePolicyMetadata.currentSchemaVersion
    ],
    this.supportedCalculationVersions = const [
      ReleaseGovernancePolicyMetadata.currentCalculationVersion
    ],
    this.supportedCanonicalizationVersions = const [
      ReleaseGovernancePolicyMetadata.currentCanonicalizationVersion
    ],
  });

  final bool requireSameProject;
  final bool requireSameCommit;
  final bool requireSameBranch;
  final bool requireSupportedEnvironment;
  final bool requireSupportedReleaseType;
  final bool requireQualityGatePolicyCompatibility;
  final bool requireQualityGateSchemaCompatibility;
  final bool requireApprovalPolicyCompatibility;
  final bool requireWaiverPolicyCompatibility;
  final bool requireAuthorityValidity;
  final bool requireFingerprints;
  final bool allowPartialCompatibility;
  final List<String> allowedQualityGatePolicyIds;
  final List<int> allowedQualityGatePolicyVersions;
  final List<int> supportedSchemas;
  final List<int> supportedCalculationVersions;
  final List<int> supportedCanonicalizationVersions;

  Map<String, dynamic> toJson() => {
        'requireSameProject': requireSameProject,
        'requireSameCommit': requireSameCommit,
        'requireSameBranch': requireSameBranch,
        'requireSupportedEnvironment': requireSupportedEnvironment,
        'requireSupportedReleaseType': requireSupportedReleaseType,
        'requireQualityGatePolicyCompatibility':
            requireQualityGatePolicyCompatibility,
        'requireQualityGateSchemaCompatibility':
            requireQualityGateSchemaCompatibility,
        'requireApprovalPolicyCompatibility':
            requireApprovalPolicyCompatibility,
        'requireWaiverPolicyCompatibility': requireWaiverPolicyCompatibility,
        'requireAuthorityValidity': requireAuthorityValidity,
        'requireFingerprints': requireFingerprints,
        'allowPartialCompatibility': allowPartialCompatibility,
        'allowedQualityGatePolicyIds': allowedQualityGatePolicyIds,
        'allowedQualityGatePolicyVersions': allowedQualityGatePolicyVersions,
        'supportedSchemas': supportedSchemas,
        'supportedCalculationVersions': supportedCalculationVersions,
        'supportedCanonicalizationVersions': supportedCanonicalizationVersions,
      };

  factory ReleaseGovernanceCompatibilityPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceCompatibilityPolicy(
      requireSameProject: json['requireSameProject'] as bool? ?? true,
      requireSameCommit: json['requireSameCommit'] as bool? ?? true,
      requireSameBranch: json['requireSameBranch'] as bool? ?? false,
      requireSupportedEnvironment:
          json['requireSupportedEnvironment'] as bool? ?? true,
      requireSupportedReleaseType:
          json['requireSupportedReleaseType'] as bool? ?? true,
      requireQualityGatePolicyCompatibility:
          json['requireQualityGatePolicyCompatibility'] as bool? ?? true,
      requireQualityGateSchemaCompatibility:
          json['requireQualityGateSchemaCompatibility'] as bool? ?? true,
      requireApprovalPolicyCompatibility:
          json['requireApprovalPolicyCompatibility'] as bool? ?? true,
      requireWaiverPolicyCompatibility:
          json['requireWaiverPolicyCompatibility'] as bool? ?? true,
      requireAuthorityValidity:
          json['requireAuthorityValidity'] as bool? ?? true,
      requireFingerprints: json['requireFingerprints'] as bool? ?? true,
      allowPartialCompatibility:
          json['allowPartialCompatibility'] as bool? ?? false,
      allowedQualityGatePolicyIds:
          (json['allowedQualityGatePolicyIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      allowedQualityGatePolicyVersions:
          (json['allowedQualityGatePolicyVersions'] as List<dynamic>? ?? [])
              .map((e) => e as int)
              .toList(),
      supportedSchemas: (json['supportedSchemas'] as List<dynamic>? ??
              [ReleaseGovernancePolicyMetadata.currentSchemaVersion])
          .map((e) => e as int)
          .toList(),
      supportedCalculationVersions:
          (json['supportedCalculationVersions'] as List<dynamic>? ??
                  [ReleaseGovernancePolicyMetadata.currentCalculationVersion])
              .map((e) => e as int)
              .toList(),
      supportedCanonicalizationVersions:
          (json['supportedCanonicalizationVersions'] as List<dynamic>? ??
                  [
                    ReleaseGovernancePolicyMetadata
                        .currentCanonicalizationVersion,
                  ])
              .map((e) => e as int)
              .toList(),
    );
  }
}

/// Eligibility policy for release governance evaluation.
class ReleaseGovernanceEligibilityPolicy {
  const ReleaseGovernanceEligibilityPolicy({
    this.requireQualityGate = true,
    this.requireReleaseContext = true,
    this.requireApprovalsForEvaluation = true,
    this.requireWaiversForEvaluation = false,
    this.minimumNormativeRuleCount = 1,
    this.allowCandidatePolicy = true,
    this.allowDeprecatedPolicy = false,
    this.allowRetiredPolicyForHistoricalEvaluation = false,
    this.allowUnknownEnvironment = false,
    this.allowUnknownReleaseType = false,
    this.allowPartialEligibility = false,
  });

  final bool requireQualityGate;
  final bool requireReleaseContext;
  final bool requireApprovalsForEvaluation;
  final bool requireWaiversForEvaluation;
  final int minimumNormativeRuleCount;
  final bool allowCandidatePolicy;
  final bool allowDeprecatedPolicy;
  final bool allowRetiredPolicyForHistoricalEvaluation;
  final bool allowUnknownEnvironment;
  final bool allowUnknownReleaseType;
  final bool allowPartialEligibility;

  Map<String, dynamic> toJson() => {
        'requireQualityGate': requireQualityGate,
        'requireReleaseContext': requireReleaseContext,
        'requireApprovalsForEvaluation': requireApprovalsForEvaluation,
        'requireWaiversForEvaluation': requireWaiversForEvaluation,
        'minimumNormativeRuleCount': minimumNormativeRuleCount,
        'allowCandidatePolicy': allowCandidatePolicy,
        'allowDeprecatedPolicy': allowDeprecatedPolicy,
        'allowRetiredPolicyForHistoricalEvaluation':
            allowRetiredPolicyForHistoricalEvaluation,
        'allowUnknownEnvironment': allowUnknownEnvironment,
        'allowUnknownReleaseType': allowUnknownReleaseType,
        'allowPartialEligibility': allowPartialEligibility,
      };

  factory ReleaseGovernanceEligibilityPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceEligibilityPolicy(
      requireQualityGate: json['requireQualityGate'] as bool? ?? true,
      requireReleaseContext: json['requireReleaseContext'] as bool? ?? true,
      requireApprovalsForEvaluation:
          json['requireApprovalsForEvaluation'] as bool? ?? true,
      requireWaiversForEvaluation:
          json['requireWaiversForEvaluation'] as bool? ?? false,
      minimumNormativeRuleCount: json['minimumNormativeRuleCount'] as int? ?? 1,
      allowCandidatePolicy: json['allowCandidatePolicy'] as bool? ?? true,
      allowDeprecatedPolicy: json['allowDeprecatedPolicy'] as bool? ?? false,
      allowRetiredPolicyForHistoricalEvaluation:
          json['allowRetiredPolicyForHistoricalEvaluation'] as bool? ?? false,
      allowUnknownEnvironment:
          json['allowUnknownEnvironment'] as bool? ?? false,
      allowUnknownReleaseType:
          json['allowUnknownReleaseType'] as bool? ?? false,
      allowPartialEligibility:
          json['allowPartialEligibility'] as bool? ?? false,
    );
  }
}

/// Reference to a published policy without duplicating payload.
class ReleaseGovernancePolicyReference {
  const ReleaseGovernancePolicyReference({
    required this.policyId,
    required this.policyVersion,
    required this.fingerprint,
    this.displayName,
    this.status,
  });

  final String policyId;
  final int policyVersion;
  final String fingerprint;
  final String? displayName;
  final ReleaseGovernancePolicyStatus? status;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'fingerprint': fingerprint,
        if (displayName != null) 'displayName': displayName,
        if (status != null) 'status': status!.wireName,
      };

  factory ReleaseGovernancePolicyReference.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernancePolicyReference(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      fingerprint: json['fingerprint'] as String,
      displayName: json['displayName'] as String?,
      status: json['status'] == null
          ? null
          : ReleaseGovernancePolicyStatusX.fromWireName(
              json['status'] as String,
            ),
    );
  }
}

/// Complete declarative release governance policy.
class ReleaseGovernancePolicy {
  const ReleaseGovernancePolicy({
    required this.metadata,
    required this.governance,
    required this.rules,
    required this.ruleSets,
    required this.approvalRequirements,
    required this.waiverRules,
    required this.decisionPolicy,
    required this.evidencePolicy,
    required this.compatibilityPolicy,
    required this.eligibilityPolicy,
    required this.supportedReleaseTypes,
    required this.supportedEnvironments,
    this.limitations = const [],
    this.extensions = const {},
  });

  static const int currentSchemaVersion =
      ReleaseGovernancePolicyMetadata.currentSchemaVersion;
  static const int currentCalculationVersion =
      ReleaseGovernancePolicyMetadata.currentCalculationVersion;
  static const int currentCanonicalizationVersion =
      ReleaseGovernancePolicyMetadata.currentCanonicalizationVersion;

  final ReleaseGovernancePolicyMetadata metadata;
  final ReleaseGovernanceGovernance governance;
  final List<ReleaseGovernanceRule> rules;
  final List<ReleaseGovernanceRuleSet> ruleSets;
  final List<ReleaseApprovalRequirement> approvalRequirements;
  final ReleaseWaiverPolicy waiverRules;
  final ReleaseGovernanceDecisionPolicy decisionPolicy;
  final ReleaseGovernanceEvidencePolicy evidencePolicy;
  final ReleaseGovernanceCompatibilityPolicy compatibilityPolicy;
  final ReleaseGovernanceEligibilityPolicy eligibilityPolicy;
  final List<ReleaseType> supportedReleaseTypes;
  final List<ReleaseEnvironment> supportedEnvironments;
  final List<String> limitations;
  final Map<String, String> extensions;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'governance': governance.toJson(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'ruleSets': ruleSets.map((s) => s.toJson()).toList(),
        'approvalRequirements':
            approvalRequirements.map((r) => r.toJson()).toList(),
        'waiverRules': waiverRules.toJson(),
        'decisionPolicy': decisionPolicy.toJson(),
        'evidencePolicy': evidencePolicy.toJson(),
        'compatibilityPolicy': compatibilityPolicy.toJson(),
        'eligibilityPolicy': eligibilityPolicy.toJson(),
        'supportedReleaseTypes':
            supportedReleaseTypes.map((e) => e.wireName).toList(),
        'supportedEnvironments':
            supportedEnvironments.map((e) => e.wireName).toList(),
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  factory ReleaseGovernancePolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernancePolicy(
      metadata: ReleaseGovernancePolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      governance: ReleaseGovernanceGovernance.fromJson(
        json['governance'] as Map<String, dynamic>,
      ),
      rules: (json['rules'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceRule.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      ruleSets: (json['ruleSets'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceRuleSet.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      approvalRequirements: (json['approvalRequirements'] as List<dynamic>)
          .map(
            (e) => ReleaseApprovalRequirement.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      waiverRules: ReleaseWaiverPolicy.fromJson(
        json['waiverRules'] as Map<String, dynamic>,
      ),
      decisionPolicy: ReleaseGovernanceDecisionPolicy.fromJson(
        json['decisionPolicy'] as Map<String, dynamic>,
      ),
      evidencePolicy: ReleaseGovernanceEvidencePolicy.fromJson(
        json['evidencePolicy'] as Map<String, dynamic>,
      ),
      compatibilityPolicy: ReleaseGovernanceCompatibilityPolicy.fromJson(
        json['compatibilityPolicy'] as Map<String, dynamic>,
      ),
      eligibilityPolicy: ReleaseGovernanceEligibilityPolicy.fromJson(
        json['eligibilityPolicy'] as Map<String, dynamic>,
      ),
      supportedReleaseTypes: (json['supportedReleaseTypes'] as List<dynamic>)
          .map((e) => ReleaseTypeX.fromWireName(e as String))
          .toList(),
      supportedEnvironments: (json['supportedEnvironments'] as List<dynamic>)
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      extensions: (json['extensions'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    meta.remove('updatedAt');
    meta.remove('fingerprint');
    json['metadata'] = meta;
    final ruleSets = List<Map<String, dynamic>>.from(
      (json['ruleSets'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['ruleSetId'].toString().compareTo(
              b['ruleSetId'].toString(),
            ),
      );
    json['ruleSets'] = ruleSets;
    final rules = List<Map<String, dynamic>>.from(
      (json['rules'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['ruleId'].toString().compareTo(b['ruleId'].toString()),
      );
    json['rules'] = rules;
    return json;
  }
}
