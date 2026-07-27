import 'release_governance_enums.dart';
import 'release_governance_evidence.dart';
import 'release_governance_messages.dart';

/// Published approval authority definition.
class ReleaseApprovalAuthority {
  const ReleaseApprovalAuthority({
    required this.authorityId,
    required this.authorityType,
    required this.role,
    required this.organization,
    required this.allowedApprovalTypes,
    required this.allowedEnvironments,
    required this.allowedReleaseTypes,
    required this.separationOfDutiesGroup,
    required this.validFrom,
    required this.status,
    required this.schemaVersion,
    this.expiresAt,
    this.evidenceReferences = const [],
  });

  final String authorityId;
  final String authorityType;
  final String role;
  final String organization;
  final List<ReleaseApprovalType> allowedApprovalTypes;
  final List<ReleaseEnvironment> allowedEnvironments;
  final List<ReleaseType> allowedReleaseTypes;
  final String separationOfDutiesGroup;
  final String validFrom;
  final String? expiresAt;
  final ReleaseAuthorityStatus status;
  final List<String> evidenceReferences;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'authorityId': authorityId,
        'authorityType': authorityType,
        'role': role,
        'organization': organization,
        'allowedApprovalTypes':
            allowedApprovalTypes.map((e) => e.wireName).toList(),
        'allowedEnvironments':
            allowedEnvironments.map((e) => e.wireName).toList(),
        'allowedReleaseTypes':
            allowedReleaseTypes.map((e) => e.wireName).toList(),
        'separationOfDutiesGroup': separationOfDutiesGroup,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'status': status.wireName,
        'evidenceReferences': evidenceReferences,
        'schemaVersion': schemaVersion,
      };

  factory ReleaseApprovalAuthority.fromJson(Map<String, dynamic> json) {
    return ReleaseApprovalAuthority(
      authorityId: json['authorityId'] as String,
      authorityType: json['authorityType'] as String,
      role: json['role'] as String,
      organization: json['organization'] as String,
      allowedApprovalTypes: (json['allowedApprovalTypes'] as List<dynamic>)
          .map((e) => ReleaseApprovalTypeX.fromWireName(e as String))
          .toList(),
      allowedEnvironments: (json['allowedEnvironments'] as List<dynamic>)
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      allowedReleaseTypes: (json['allowedReleaseTypes'] as List<dynamic>)
          .map((e) => ReleaseTypeX.fromWireName(e as String))
          .toList(),
      separationOfDutiesGroup: json['separationOfDutiesGroup'] as String,
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      status: ReleaseAuthorityStatusX.fromWireName(json['status'] as String),
      evidenceReferences: (json['evidenceReferences'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      schemaVersion: json['schemaVersion'] as int,
    );
  }
}

/// Scope of an individual approval.
class ReleaseApprovalScope {
  const ReleaseApprovalScope({
    required this.projectId,
    required this.releaseId,
    this.commitId,
    this.branch,
    this.environment,
    this.releaseType,
    this.policyId,
    this.policyVersion,
  });

  final String projectId;
  final String releaseId;
  final String? commitId;
  final String? branch;
  final ReleaseEnvironment? environment;
  final ReleaseType? releaseType;
  final String? policyId;
  final int? policyVersion;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        if (environment != null) 'environment': environment!.wireName,
        if (releaseType != null) 'releaseType': releaseType!.wireName,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
      };

  factory ReleaseApprovalScope.fromJson(Map<String, dynamic> json) {
    return ReleaseApprovalScope(
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      environment: json['environment'] == null
          ? null
          : ReleaseEnvironmentX.fromWireName(json['environment'] as String),
      releaseType: json['releaseType'] == null
          ? null
          : ReleaseTypeX.fromWireName(json['releaseType'] as String),
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
    );
  }
}

/// Immutable published approval record.
class ReleaseApproval {
  const ReleaseApproval({
    required this.approvalId,
    required this.releaseId,
    required this.policyId,
    required this.policyVersion,
    required this.approvalType,
    required this.authority,
    required this.approverId,
    required this.status,
    required this.decision,
    required this.scope,
    required this.issuedAt,
    required this.validFrom,
    required this.evidence,
    required this.reason,
    required this.fingerprint,
    required this.schemaVersion,
    this.approverDisplayName,
    this.expiresAt,
    this.comments,
    this.sourceReference,
    this.metadata = const {},
  });

  final String approvalId;
  final String releaseId;
  final String policyId;
  final int policyVersion;
  final ReleaseApprovalType approvalType;
  final ReleaseApprovalAuthority authority;
  final String approverId;
  final String? approverDisplayName;
  final ReleaseApprovalStatus status;
  final ReleaseGovernanceDecision decision;
  final ReleaseApprovalScope scope;
  final String issuedAt;
  final String validFrom;
  final String? expiresAt;
  final List<ReleaseGovernanceEvidence> evidence;
  final String reason;
  final String? comments;
  final ReleaseGovernanceSourceReference? sourceReference;
  final String fingerprint;
  final int schemaVersion;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'approvalId': approvalId,
        'releaseId': releaseId,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'approvalType': approvalType.wireName,
        'authority': authority.toJson(),
        'approverId': approverId,
        if (approverDisplayName != null)
          'approverDisplayName': approverDisplayName,
        'status': status.wireName,
        'decision': decision.wireName,
        'scope': scope.toJson(),
        'issuedAt': issuedAt,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'reason': reason,
        if (comments != null) 'comments': comments,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseApproval.fromJson(Map<String, dynamic> json) {
    return ReleaseApproval(
      approvalId: json['approvalId'] as String,
      releaseId: json['releaseId'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      approvalType:
          ReleaseApprovalTypeX.fromWireName(json['approvalType'] as String),
      authority: ReleaseApprovalAuthority.fromJson(
        json['authority'] as Map<String, dynamic>,
      ),
      approverId: json['approverId'] as String,
      approverDisplayName: json['approverDisplayName'] as String?,
      status: ReleaseApprovalStatusX.fromWireName(json['status'] as String),
      decision: ReleaseGovernanceDecisionX.fromWireName(
        json['decision'] as String,
      ),
      scope: ReleaseApprovalScope.fromJson(
        json['scope'] as Map<String, dynamic>,
      ),
      issuedAt: json['issuedAt'] as String,
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceEvidence.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      reason: json['reason'] as String,
      comments: json['comments'] as String?,
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseGovernanceSourceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Policy requirement for approvals.
class ReleaseApprovalRequirement {
  const ReleaseApprovalRequirement({
    required this.requirementId,
    required this.approvalType,
    required this.minimumCount,
    required this.distinctApproversRequired,
    required this.allowedAuthorityIds,
    required this.environmentScope,
    required this.releaseTypeScope,
    required this.requiredForDecisions,
    required this.evidenceRequired,
    required this.order,
    required this.enabled,
    this.authorityRole,
    this.separationOfDutiesRule,
    this.expiresAfter,
  });

  final String requirementId;
  final ReleaseApprovalType approvalType;
  final int minimumCount;
  final bool distinctApproversRequired;
  final String? authorityRole;
  final List<String> allowedAuthorityIds;
  final List<ReleaseEnvironment> environmentScope;
  final List<ReleaseType> releaseTypeScope;
  final List<ReleaseGovernanceDecision> requiredForDecisions;
  final ReleaseSeparationOfDutiesRule? separationOfDutiesRule;
  final String? expiresAfter;
  final bool evidenceRequired;
  final int order;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'approvalType': approvalType.wireName,
        'minimumCount': minimumCount,
        'distinctApproversRequired': distinctApproversRequired,
        if (authorityRole != null) 'authorityRole': authorityRole,
        'allowedAuthorityIds': allowedAuthorityIds,
        'environmentScope': environmentScope.map((e) => e.wireName).toList(),
        'releaseTypeScope': releaseTypeScope.map((e) => e.wireName).toList(),
        'requiredForDecisions':
            requiredForDecisions.map((e) => e.wireName).toList(),
        if (separationOfDutiesRule != null)
          'separationOfDutiesRule': separationOfDutiesRule!.toJson(),
        if (expiresAfter != null) 'expiresAfter': expiresAfter,
        'evidenceRequired': evidenceRequired,
        'order': order,
        'enabled': enabled,
      };

  factory ReleaseApprovalRequirement.fromJson(Map<String, dynamic> json) {
    return ReleaseApprovalRequirement(
      requirementId: json['requirementId'] as String,
      approvalType:
          ReleaseApprovalTypeX.fromWireName(json['approvalType'] as String),
      minimumCount: json['minimumCount'] as int,
      distinctApproversRequired: json['distinctApproversRequired'] as bool,
      authorityRole: json['authorityRole'] as String?,
      allowedAuthorityIds: (json['allowedAuthorityIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      environmentScope: (json['environmentScope'] as List<dynamic>)
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      releaseTypeScope: (json['releaseTypeScope'] as List<dynamic>)
          .map((e) => ReleaseTypeX.fromWireName(e as String))
          .toList(),
      requiredForDecisions: (json['requiredForDecisions'] as List<dynamic>)
          .map((e) => ReleaseGovernanceDecisionX.fromWireName(e as String))
          .toList(),
      separationOfDutiesRule: json['separationOfDutiesRule'] == null
          ? null
          : ReleaseSeparationOfDutiesRule.fromJson(
              json['separationOfDutiesRule'] as Map<String, dynamic>,
            ),
      expiresAfter: json['expiresAfter'] as String?,
      evidenceRequired: json['evidenceRequired'] as bool,
      order: json['order'] as int,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Separation of duties constraints.
class ReleaseSeparationOfDutiesRule {
  const ReleaseSeparationOfDutiesRule({
    required this.ruleId,
    required this.prohibitedSameApproverTypes,
    required this.prohibitedAuthorityGroups,
    required this.minimumDistinctApprovers,
    required this.requesterCannotApprove,
    required this.waiverIssuerCannotApprove,
    required this.emergencyOverrides,
    required this.rationale,
  });

  final String ruleId;
  final List<ReleaseApprovalType> prohibitedSameApproverTypes;
  final List<String> prohibitedAuthorityGroups;
  final int minimumDistinctApprovers;
  final bool requesterCannotApprove;
  final bool waiverIssuerCannotApprove;
  final bool emergencyOverrides;
  final String rationale;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'prohibitedSameApproverTypes':
            prohibitedSameApproverTypes.map((e) => e.wireName).toList(),
        'prohibitedAuthorityGroups': prohibitedAuthorityGroups,
        'minimumDistinctApprovers': minimumDistinctApprovers,
        'requesterCannotApprove': requesterCannotApprove,
        'waiverIssuerCannotApprove': waiverIssuerCannotApprove,
        'emergencyOverrides': emergencyOverrides,
        'rationale': rationale,
      };

  factory ReleaseSeparationOfDutiesRule.fromJson(Map<String, dynamic> json) {
    return ReleaseSeparationOfDutiesRule(
      ruleId: json['ruleId'] as String,
      prohibitedSameApproverTypes:
          (json['prohibitedSameApproverTypes'] as List<dynamic>)
              .map((e) => ReleaseApprovalTypeX.fromWireName(e as String))
              .toList(),
      prohibitedAuthorityGroups:
          (json['prohibitedAuthorityGroups'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      minimumDistinctApprovers: json['minimumDistinctApprovers'] as int,
      requesterCannotApprove: json['requesterCannotApprove'] as bool,
      waiverIssuerCannotApprove: json['waiverIssuerCannotApprove'] as bool,
      emergencyOverrides: json['emergencyOverrides'] as bool,
      rationale: json['rationale'] as String,
    );
  }
}

/// Immutable collection of approvals for a release.
class ReleaseApprovalSet {
  const ReleaseApprovalSet({
    required this.releaseId,
    required this.approvals,
    required this.fingerprint,
    required this.schemaVersion,
    this.sourceReferences = const [],
    this.warnings = const [],
    this.limitations = const [],
  });

  final String releaseId;
  final List<ReleaseApproval> approvals;
  final List<ReleaseGovernanceSourceReference> sourceReferences;
  final String fingerprint;
  final int schemaVersion;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'releaseId': releaseId,
        'approvals': approvals.map((e) => e.toJson()).toList(),
        'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseApprovalSet.fromJson(Map<String, dynamic> json) {
    return ReleaseApprovalSet(
      releaseId: json['releaseId'] as String,
      approvals: (json['approvals'] as List<dynamic>)
          .map((e) => ReleaseApproval.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceSourceReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Evaluation of approval requirements.
class ReleaseApprovalEvaluation {
  const ReleaseApprovalEvaluation({
    required this.requirementId,
    required this.approvalType,
    required this.requiredCount,
    required this.validCount,
    required this.missingCount,
    required this.expiredCount,
    required this.rejectedCount,
    required this.duplicateCount,
    required this.authorityInvalidCount,
    required this.separationOfDutiesSatisfied,
    required this.status,
    required this.approvalIds,
    required this.evidenceIds,
    required this.explanation,
    required this.fingerprint,
  });

  final String requirementId;
  final ReleaseApprovalType approvalType;
  final int requiredCount;
  final int validCount;
  final int missingCount;
  final int expiredCount;
  final int rejectedCount;
  final int duplicateCount;
  final int authorityInvalidCount;
  final bool separationOfDutiesSatisfied;
  final ReleaseApprovalEvaluationStatus status;
  final List<String> approvalIds;
  final List<String> evidenceIds;
  final ReleaseGovernanceExplanation explanation;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'approvalType': approvalType.wireName,
        'requiredCount': requiredCount,
        'validCount': validCount,
        'missingCount': missingCount,
        'expiredCount': expiredCount,
        'rejectedCount': rejectedCount,
        'duplicateCount': duplicateCount,
        'authorityInvalidCount': authorityInvalidCount,
        'separationOfDutiesSatisfied': separationOfDutiesSatisfied,
        'status': status.wireName,
        'approvalIds': approvalIds,
        'evidenceIds': evidenceIds,
        'explanation': explanation.toJson(),
        'fingerprint': fingerprint,
      };

  factory ReleaseApprovalEvaluation.fromJson(Map<String, dynamic> json) {
    return ReleaseApprovalEvaluation(
      requirementId: json['requirementId'] as String,
      approvalType:
          ReleaseApprovalTypeX.fromWireName(json['approvalType'] as String),
      requiredCount: json['requiredCount'] as int,
      validCount: json['validCount'] as int,
      missingCount: json['missingCount'] as int,
      expiredCount: json['expiredCount'] as int,
      rejectedCount: json['rejectedCount'] as int,
      duplicateCount: json['duplicateCount'] as int,
      authorityInvalidCount: json['authorityInvalidCount'] as int,
      separationOfDutiesSatisfied: json['separationOfDutiesSatisfied'] as bool,
      status: ReleaseApprovalEvaluationStatusX.fromWireName(
        json['status'] as String,
      ),
      approvalIds: (json['approvalIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
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
