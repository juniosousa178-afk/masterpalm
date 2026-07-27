/// Release Governance policy lifecycle status.
enum ReleaseGovernancePolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension ReleaseGovernancePolicyStatusX on ReleaseGovernancePolicyStatus {
  String get wireName => name;

  static ReleaseGovernancePolicyStatus fromWireName(String value) {
    return ReleaseGovernancePolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernancePolicyStatus: $value',
      ),
    );
  }
}

/// Final release governance decision.
enum ReleaseGovernanceDecision {
  approved,
  approvedWithConditions,
  rejected,
  pending,
  unavailable,
  incompatible,
  expired,
  cancelled,
  error,
}

extension ReleaseGovernanceDecisionX on ReleaseGovernanceDecision {
  String get wireName => name;

  static ReleaseGovernanceDecision fromWireName(String value) {
    return ReleaseGovernanceDecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceDecision: $value'),
    );
  }
}

/// Operational result of a release governance evaluation run.
enum ReleaseGovernanceResultStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension ReleaseGovernanceResultStatusX on ReleaseGovernanceResultStatus {
  String get wireName => name;

  static ReleaseGovernanceResultStatus fromWireName(String value) {
    return ReleaseGovernanceResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceResultStatus: $value',
      ),
    );
  }
}

/// Target deployment environment.
enum ReleaseEnvironment {
  local,
  development,
  test,
  qa,
  staging,
  preProduction,
  production,
  unknown,
}

extension ReleaseEnvironmentX on ReleaseEnvironment {
  String get wireName => name;

  static ReleaseEnvironment fromWireName(String value) {
    return ReleaseEnvironment.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReleaseEnvironment: $value'),
    );
  }
}

/// Release classification.
enum ReleaseType {
  development,
  internal,
  beta,
  releaseCandidate,
  production,
  hotfix,
  rollback,
  emergency,
}

extension ReleaseTypeX on ReleaseType {
  String get wireName => name;

  static ReleaseType fromWireName(String value) {
    return ReleaseType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReleaseType: $value'),
    );
  }
}

/// Rule severity — separate from requirement.
enum ReleaseGovernanceRuleSeverity {
  informational,
  advisory,
  warning,
  blocking,
  critical,
}

extension ReleaseGovernanceRuleSeverityX on ReleaseGovernanceRuleSeverity {
  String get wireName => name;

  static ReleaseGovernanceRuleSeverity fromWireName(String value) {
    return ReleaseGovernanceRuleSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceRuleSeverity: $value',
      ),
    );
  }
}

/// Whether a rule participates in mandatory evaluation.
enum ReleaseGovernanceRuleRequirement {
  required,
  optional,
  informational,
}

extension ReleaseGovernanceRuleRequirementX
    on ReleaseGovernanceRuleRequirement {
  String get wireName => name;

  static ReleaseGovernanceRuleRequirement fromWireName(String value) {
    return ReleaseGovernanceRuleRequirement.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceRuleRequirement: $value',
      ),
    );
  }
}

/// Terminal status of an individual rule evaluation.
enum ReleaseGovernanceRuleStatus {
  passed,
  failed,
  pending,
  waived,
  conditionallySatisfied,
  unavailable,
  incompatible,
  skipped,
  notApplicable,
  expired,
  error,
}

extension ReleaseGovernanceRuleStatusX on ReleaseGovernanceRuleStatus {
  String get wireName => name;

  static ReleaseGovernanceRuleStatus fromWireName(String value) {
    return ReleaseGovernanceRuleStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceRuleStatus: $value'),
    );
  }
}

/// Impact of a rule evaluation on the final decision.
enum ReleaseGovernanceDecisionImpact {
  none,
  advisory,
  contributesToConditions,
  contributesToPending,
  blocksApproval,
  causesRejection,
  causesUnavailable,
  causesIncompatible,
  causesExpiration,
  internalError,
}

extension ReleaseGovernanceDecisionImpactX on ReleaseGovernanceDecisionImpact {
  String get wireName => name;

  static ReleaseGovernanceDecisionImpact fromWireName(String value) {
    return ReleaseGovernanceDecisionImpact.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceDecisionImpact: $value',
      ),
    );
  }
}

/// Missing-data handling for release governance rules.
enum ReleaseGovernanceMissingDataPolicy {
  reject,
  pending,
  unavailable,
  conditional,
  skip,
  notApplicable,
}

extension ReleaseGovernanceMissingDataPolicyX
    on ReleaseGovernanceMissingDataPolicy {
  String get wireName => name;

  static ReleaseGovernanceMissingDataPolicy fromWireName(String value) {
    return ReleaseGovernanceMissingDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceMissingDataPolicy: $value',
      ),
    );
  }
}

/// Incompatible-data handling for release governance rules.
enum ReleaseGovernanceIncompatibleDataPolicy {
  reject,
  pending,
  incompatible,
  conditional,
  skip,
}

extension ReleaseGovernanceIncompatibleDataPolicyX
    on ReleaseGovernanceIncompatibleDataPolicy {
  String get wireName => name;

  static ReleaseGovernanceIncompatibleDataPolicy fromWireName(String value) {
    return ReleaseGovernanceIncompatibleDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceIncompatibleDataPolicy: $value',
      ),
    );
  }
}

/// Waiver capability per rule.
enum ReleaseGovernanceWaiverCapability {
  forbidden,
  allowed,
  allowedWithConditions,
  emergencyOnly,
}

extension ReleaseGovernanceWaiverCapabilityX
    on ReleaseGovernanceWaiverCapability {
  String get wireName => name;

  static ReleaseGovernanceWaiverCapability fromWireName(String value) {
    return ReleaseGovernanceWaiverCapability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceWaiverCapability: $value',
      ),
    );
  }
}

/// Rule set aggregation mode.
enum ReleaseGovernanceRuleSetAggregationMode {
  all,
  any,
  minimumCount,
  minimumPercentage,
}

extension ReleaseGovernanceRuleSetAggregationModeX
    on ReleaseGovernanceRuleSetAggregationMode {
  String get wireName => name;

  static ReleaseGovernanceRuleSetAggregationMode fromWireName(String value) {
    return ReleaseGovernanceRuleSetAggregationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceRuleSetAggregationMode: $value',
      ),
    );
  }
}

/// Typed rule targets — no arbitrary strings in official policies.
enum ReleaseGovernanceRuleTarget {
  qualityGateDecision,
  qualityGatePolicyId,
  qualityGatePolicyVersion,
  qualityGateEligibility,
  qualityGateCompatibility,
  qualityGateCoverage,
  qualityGateBlockingFailureCount,
  qualityGateCriticalFailureCount,
  qualityGateFailedRuleCount,
  qualityGateFingerprint,
  qualityGateAge,
  qualityGateProjectConsistency,
  qualityGateCommitConsistency,
  releaseProjectId,
  releaseCommitId,
  releaseBranch,
  releaseVersion,
  releaseEnvironment,
  releaseType,
  releaseArtifactCount,
  releaseRequestedByPresent,
  releaseTargetDateValid,
  requiredApprovalCount,
  validApprovalCount,
  missingApprovalCount,
  rejectedApprovalCount,
  expiredApprovalCount,
  approvalAuthorityPresent,
  separationOfDutiesSatisfied,
  approvalEvidenceComplete,
  activeWaiverCount,
  invalidWaiverCount,
  expiredWaiverCount,
  waiverScopeValid,
  waiverAuthorityValid,
  waiverEvidenceComplete,
  waiverExpirationValid,
  waiverLimitSatisfied,
  projectConsistency,
  commitConsistency,
  environmentCompatibility,
  policyCompatibility,
  sourceFreshness,
  requiredSourcesAvailable,
}

extension ReleaseGovernanceRuleTargetX on ReleaseGovernanceRuleTarget {
  String get wireName => name;

  static ReleaseGovernanceRuleTarget fromWireName(String value) {
    return ReleaseGovernanceRuleTarget.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceRuleTarget: $value'),
    );
  }
}

/// Typed comparison and state operators.
enum ReleaseGovernanceRuleOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  betweenInclusive,
  betweenExclusive,
  inSet,
  notInSet,
  contains,
  containsAny,
  containsAll,
  exists,
  doesNotExist,
  isTrue,
  isFalse,
  isAvailable,
  isUnavailable,
  isCompatible,
  isIncompatible,
  isEligible,
  isNotEligible,
  isValid,
  isInvalid,
  isExpired,
  isNotExpired,
}

extension ReleaseGovernanceRuleOperatorX on ReleaseGovernanceRuleOperator {
  String get wireName => name;

  static ReleaseGovernanceRuleOperator fromWireName(String value) {
    return ReleaseGovernanceRuleOperator.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
          'Unknown ReleaseGovernanceRuleOperator: $value'),
    );
  }
}

/// Approval lifecycle status.
enum ReleaseApprovalStatus {
  pending,
  approved,
  rejected,
  revoked,
  expired,
  superseded,
  invalid,
}

extension ReleaseApprovalStatusX on ReleaseApprovalStatus {
  String get wireName => name;

  static ReleaseApprovalStatus fromWireName(String value) {
    return ReleaseApprovalStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseApprovalStatus: $value'),
    );
  }
}

/// Approval role classification.
enum ReleaseApprovalType {
  engineering,
  quality,
  security,
  operations,
  product,
  compliance,
  releaseManager,
  changeManagement,
  emergency,
  rollback,
  custom,
}

extension ReleaseApprovalTypeX on ReleaseApprovalType {
  String get wireName => name;

  static ReleaseApprovalType fromWireName(String value) {
    return ReleaseApprovalType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseApprovalType: $value'),
    );
  }
}

/// Authority lifecycle status.
enum ReleaseAuthorityStatus {
  active,
  suspended,
  revoked,
  expired,
  unknown,
}

extension ReleaseAuthorityStatusX on ReleaseAuthorityStatus {
  String get wireName => name;

  static ReleaseAuthorityStatus fromWireName(String value) {
    return ReleaseAuthorityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseAuthorityStatus: $value'),
    );
  }
}

/// Waiver lifecycle status.
enum ReleaseWaiverStatus {
  requested,
  approved,
  rejected,
  active,
  expired,
  revoked,
  consumed,
  invalid,
  superseded,
}

extension ReleaseWaiverStatusX on ReleaseWaiverStatus {
  String get wireName => name;

  static ReleaseWaiverStatus fromWireName(String value) {
    return ReleaseWaiverStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseWaiverStatus: $value'),
    );
  }
}

/// Waiver expiration mode.
enum ReleaseWaiverExpirationMode {
  timeBased,
  singleUse,
  releaseBound,
  commitBound,
  earliestOfAll,
}

extension ReleaseWaiverExpirationModeX on ReleaseWaiverExpirationMode {
  String get wireName => name;

  static ReleaseWaiverExpirationMode fromWireName(String value) {
    return ReleaseWaiverExpirationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseWaiverExpirationMode: $value',
      ),
    );
  }
}

/// Compensating control status.
enum ReleaseCompensatingControlStatus {
  proposed,
  active,
  verified,
  failed,
  expired,
  revoked,
}

extension ReleaseCompensatingControlStatusX
    on ReleaseCompensatingControlStatus {
  String get wireName => name;

  static ReleaseCompensatingControlStatus fromWireName(String value) {
    return ReleaseCompensatingControlStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseCompensatingControlStatus: $value',
      ),
    );
  }
}

/// Compatibility status.
enum ReleaseGovernanceCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension ReleaseGovernanceCompatibilityStatusX
    on ReleaseGovernanceCompatibilityStatus {
  String get wireName => name;

  static ReleaseGovernanceCompatibilityStatus fromWireName(String value) {
    return ReleaseGovernanceCompatibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceCompatibilityStatus: $value',
      ),
    );
  }
}

/// Eligibility status.
enum ReleaseGovernanceEligibilityStatus {
  eligible,
  partiallyEligible,
  ineligible,
  unknown,
}

extension ReleaseGovernanceEligibilityStatusX
    on ReleaseGovernanceEligibilityStatus {
  String get wireName => name;

  static ReleaseGovernanceEligibilityStatus fromWireName(String value) {
    return ReleaseGovernanceEligibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceEligibilityStatus: $value',
      ),
    );
  }
}

/// Evidence type.
enum ReleaseGovernanceEvidenceType {
  qualityGate,
  approval,
  authority,
  waiver,
  compensatingControl,
  releaseContext,
  policy,
  historical,
  operational,
  unavailable,
  incompatible,
}

extension ReleaseGovernanceEvidenceTypeX on ReleaseGovernanceEvidenceType {
  String get wireName => name;

  static ReleaseGovernanceEvidenceType fromWireName(String value) {
    return ReleaseGovernanceEvidenceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceEvidenceType: $value',
      ),
    );
  }
}

/// Approval requirement evaluation status.
enum ReleaseApprovalEvaluationStatus {
  satisfied,
  partiallySatisfied,
  missing,
  rejected,
  expired,
  incompatible,
  notApplicable,
  error,
}

extension ReleaseApprovalEvaluationStatusX on ReleaseApprovalEvaluationStatus {
  String get wireName => name;

  static ReleaseApprovalEvaluationStatus fromWireName(String value) {
    return ReleaseApprovalEvaluationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseApprovalEvaluationStatus: $value',
      ),
    );
  }
}

/// Condition type for approvedWithConditions.
enum ReleaseConditionType {
  followUp,
  compensatingControl,
  limitedEnvironment,
  limitedAudience,
  monitoringRequired,
  rollbackPreparedness,
  expiration,
  manualVerification,
  documentation,
  custom,
}

extension ReleaseConditionTypeX on ReleaseConditionType {
  String get wireName => name;

  static ReleaseConditionType fromWireName(String value) {
    return ReleaseConditionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseConditionType: $value'),
    );
  }
}

/// Condition lifecycle status.
enum ReleaseConditionStatus {
  open,
  satisfied,
  expired,
  cancelled,
  invalid,
}

extension ReleaseConditionStatusX on ReleaseConditionStatus {
  String get wireName => name;

  static ReleaseConditionStatus fromWireName(String value) {
    return ReleaseConditionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseConditionStatus: $value'),
    );
  }
}

/// Explanation template type.
enum ReleaseGovernanceExplanationType {
  rulePassed,
  ruleFailed,
  rulePending,
  ruleWaived,
  ruleConditional,
  approvalSatisfied,
  approvalMissing,
  approvalRejected,
  approvalExpired,
  waiverAccepted,
  waiverRejected,
  waiverExpired,
  compatibility,
  eligibility,
  decisionApproved,
  decisionApprovedWithConditions,
  decisionRejected,
  decisionPending,
  decisionUnavailable,
  decisionIncompatible,
  decisionExpired,
  decisionError,
}

extension ReleaseGovernanceExplanationTypeX
    on ReleaseGovernanceExplanationType {
  String get wireName => name;

  static ReleaseGovernanceExplanationType fromWireName(String value) {
    return ReleaseGovernanceExplanationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceExplanationType: $value',
      ),
    );
  }
}

/// Source types for release governance resolution.
enum ReleaseGovernanceSourceType {
  releaseContext,
  qualityGateSnapshot,
  releaseGovernancePolicy,
  approvalSet,
  approval,
  approvalAuthority,
  waiverSet,
  waiver,
  waiverAuthority,
  compensatingControl,
  historicalDecision,
  dashboard,
  report,
}

extension ReleaseGovernanceSourceTypeX on ReleaseGovernanceSourceType {
  String get wireName => name;

  static ReleaseGovernanceSourceType fromWireName(String value) {
    return ReleaseGovernanceSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceSourceType: $value'),
    );
  }
}

/// Source resolution mode.
enum ReleaseGovernanceSourceResolutionMode {
  injected,
  byId,
  latest,
  unavailable,
  notRequested,
}

extension ReleaseGovernanceSourceResolutionModeX
    on ReleaseGovernanceSourceResolutionMode {
  String get wireName => name;

  static ReleaseGovernanceSourceResolutionMode fromWireName(String value) {
    return ReleaseGovernanceSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceSourceResolutionMode: $value',
      ),
    );
  }
}

/// Warning classification.
enum ReleaseGovernanceWarningCode {
  approvalNearExpiration,
  waiverNearExpiration,
  optionalApprovalMissing,
  reducedCoverage,
  staleQualityGate,
  deprecatedPolicy,
  derivedEvidence,
  capabilityGap,
}

extension ReleaseGovernanceWarningCodeX on ReleaseGovernanceWarningCode {
  String get wireName => name;

  static ReleaseGovernanceWarningCode fromWireName(String value) {
    return ReleaseGovernanceWarningCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceWarningCode: $value'),
    );
  }
}

/// Error classification.
enum ReleaseGovernanceErrorCode {
  invalidPolicy,
  invalidRequest,
  invalidReleaseContext,
  sourceResolutionFailure,
  evaluationFailure,
  invalidApproval,
  invalidWaiver,
  snapshotValidationFailure,
  serializationFailure,
  identityFailure,
}

extension ReleaseGovernanceErrorCodeX on ReleaseGovernanceErrorCode {
  String get wireName => name;

  static ReleaseGovernanceErrorCode fromWireName(String value) {
    return ReleaseGovernanceErrorCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseGovernanceErrorCode: $value'),
    );
  }
}

/// Limitation classification.
enum ReleaseGovernanceLimitationCode {
  authorityNotCryptographicallyVerified,
  externalIdentityNotVerified,
  noPhysicalPersistence,
  noCiCdEnforcement,
  noSignatureVerification,
  noRemotePolicyValidation,
  noAutomaticWaiverConsumption,
  historicalDataIncomplete,
}

extension ReleaseGovernanceLimitationCodeX on ReleaseGovernanceLimitationCode {
  String get wireName => name;

  static ReleaseGovernanceLimitationCode fromWireName(String value) {
    return ReleaseGovernanceLimitationCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceLimitationCode: $value',
      ),
    );
  }
}

/// Publication status for provider operations (Part 2).
enum ReleaseGovernancePublicationStatus {
  notRequested,
  published,
  skipped,
  failed,
}

extension ReleaseGovernancePublicationStatusX
    on ReleaseGovernancePublicationStatus {
  String get wireName => name;

  static ReleaseGovernancePublicationStatus fromWireName(String value) {
    return ReleaseGovernancePublicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernancePublicationStatus: $value',
      ),
    );
  }
}
