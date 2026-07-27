/// Quality Gate policy lifecycle status.
enum QualityGatePolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension QualityGatePolicyStatusX on QualityGatePolicyStatus {
  String get wireName => name;

  static QualityGatePolicyStatus fromWireName(String value) {
    return QualityGatePolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGatePolicyStatus: $value'),
    );
  }
}

/// Final gate decision over evaluated artifacts.
enum QualityGateDecision {
  passed,
  failed,
  partial,
  unavailable,
  incompatible,
  error,
}

extension QualityGateDecisionX on QualityGateDecision {
  String get wireName => name;

  static QualityGateDecision fromWireName(String value) {
    return QualityGateDecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateDecision: $value'),
    );
  }
}

/// Rule severity — separate from requirement.
enum QualityGateRuleSeverity {
  info,
  advisory,
  warning,
  blocking,
  critical,
}

extension QualityGateRuleSeverityX on QualityGateRuleSeverity {
  String get wireName => name;

  static QualityGateRuleSeverity fromWireName(String value) {
    return QualityGateRuleSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateRuleSeverity: $value'),
    );
  }
}

/// Whether a rule participates in mandatory evaluation.
enum QualityGateRuleRequirement {
  required,
  optional,
  informational,
}

extension QualityGateRuleRequirementX on QualityGateRuleRequirement {
  String get wireName => name;

  static QualityGateRuleRequirement fromWireName(String value) {
    return QualityGateRuleRequirement.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateRuleRequirement: $value'),
    );
  }
}

/// Terminal status of an individual rule evaluation.
enum QualityGateRuleStatus {
  passed,
  failed,
  unavailable,
  incompatible,
  skipped,
  notApplicable,
  error,
}

extension QualityGateRuleStatusX on QualityGateRuleStatus {
  String get wireName => name;

  static QualityGateRuleStatus fromWireName(String value) {
    return QualityGateRuleStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateRuleStatus: $value'),
    );
  }
}

/// Typed rule targets — no arbitrary strings in official policies.
enum QualityGateRuleTarget {
  guardianDecision,
  guardianRiskLevel,
  guardianViolationCount,
  guardianCriticalViolationCount,
  guardianWarningCount,
  guardianRuleStatus,
  guardianCompatibility,
  metricValue,
  metricAvailability,
  metricCoverage,
  cycleCount,
  criticalCycleCount,
  componentCount,
  isolatedComponentCount,
  dependencyCount,
  maximumFanIn,
  maximumFanOut,
  graphDensity,
  engineeringScoreGlobal,
  engineeringScoreDimension,
  engineeringScoreCoverage,
  engineeringScoreConfidence,
  engineeringScoreCompatibility,
  engineeringScoreEligibility,
  mesGlobalScore,
  mesBand,
  mesDimensionScore,
  mesCoverage,
  mesConfidence,
  mesEligibility,
  mesCompatibility,
  mesPolicyId,
  mesPolicyVersion,
  historyChangeCount,
  historyAddedCount,
  historyRemovedCount,
  historyModifiedCount,
  historyRegressionCount,
  historyArtifactCompatibility,
  telemetryFailureCount,
  telemetryIncompleteOperationCount,
  telemetrySuccessRate,
  telemetryEventCoverage,
  telemetryTerminalCoverage,
  telemetryCompatibility,
  telemetrySnapshotStatus,
  dashboardStatus,
  dashboardFreshness,
  dashboardCompatibility,
  dashboardWarningCount,
  dashboardErrorCount,
  sourceProjectConsistency,
  sourceCommitConsistency,
  sourcePolicyConsistency,
  sourceSchemaCompatibility,
  sourceFreshness,
  requiredSourcesAvailable,
}

extension QualityGateRuleTargetX on QualityGateRuleTarget {
  String get wireName => name;

  static QualityGateRuleTarget fromWireName(String value) {
    return QualityGateRuleTarget.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateRuleTarget: $value'),
    );
  }
}

/// Typed comparison and state operators.
enum QualityGateRuleOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains,
  notContains,
  containsAny,
  containsAll,
  isEmpty,
  isNotEmpty,
  isAvailable,
  isUnavailable,
  isCompatible,
  isIncompatible,
  isEligible,
  isNotEligible,
  betweenInclusive,
  betweenExclusive,
  outsideRange,
  inSet,
  notInSet,
  exists,
  doesNotExist,
  isTrue,
  isFalse,
}

extension QualityGateRuleOperatorX on QualityGateRuleOperator {
  String get wireName => name;

  static QualityGateRuleOperator fromWireName(String value) {
    return QualityGateRuleOperator.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateRuleOperator: $value'),
    );
  }
}

/// Policy for missing evidence.
enum QualityGateMissingDataPolicy {
  fail,
  partial,
  unavailable,
  skip,
  notApplicable,
}

extension QualityGateMissingDataPolicyX on QualityGateMissingDataPolicy {
  String get wireName => name;

  static QualityGateMissingDataPolicy fromWireName(String value) {
    return QualityGateMissingDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateMissingDataPolicy: $value',
      ),
    );
  }
}

/// Policy for incompatible evidence.
enum QualityGateIncompatibleDataPolicy {
  fail,
  partial,
  incompatible,
  skip,
}

extension QualityGateIncompatibleDataPolicyX
    on QualityGateIncompatibleDataPolicy {
  String get wireName => name;

  static QualityGateIncompatibleDataPolicy fromWireName(String value) {
    return QualityGateIncompatibleDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateIncompatibleDataPolicy: $value',
      ),
    );
  }
}

/// Evidence classification.
enum QualityGateEvidenceType {
  authoritative,
  derived,
  contextual,
  operational,
  historical,
  unavailable,
  incompatible,
}

extension QualityGateEvidenceTypeX on QualityGateEvidenceType {
  String get wireName => name;

  static QualityGateEvidenceType fromWireName(String value) {
    return QualityGateEvidenceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateEvidenceType: $value'),
    );
  }
}

/// Source artifact kinds for gate evaluation.
enum QualityGateSourceType {
  metrics,
  guardian,
  score,
  mes,
  history,
  telemetry,
  dashboard,
  qualityGatePolicy,
}

extension QualityGateSourceTypeX on QualityGateSourceType {
  String get wireName => name;

  static QualityGateSourceType fromWireName(String value) {
    return QualityGateSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateSourceType: $value'),
    );
  }
}

/// How a source artifact was resolved.
enum QualityGateSourceResolutionMode {
  injected,
  byId,
  latest,
  unavailable,
  incompatible,
}

extension QualityGateSourceResolutionModeX on QualityGateSourceResolutionMode {
  String get wireName => name;

  static QualityGateSourceResolutionMode fromWireName(String value) {
    return QualityGateSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateSourceResolutionMode: $value',
      ),
    );
  }
}

/// Source availability for gate evaluation.
enum QualityGateSourceAvailability {
  available,
  partial,
  unavailable,
  incompatible,
}

extension QualityGateSourceAvailabilityX on QualityGateSourceAvailability {
  String get wireName => name;

  static QualityGateSourceAvailability fromWireName(String value) {
    return QualityGateSourceAvailability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateSourceAvailability: $value',
      ),
    );
  }
}

/// Rule set aggregation mode.
enum QualityGateRuleSetAggregationMode {
  all,
  any,
  minimumCount,
  minimumPercentage,
}

extension QualityGateRuleSetAggregationModeX
    on QualityGateRuleSetAggregationMode {
  String get wireName => name;

  static QualityGateRuleSetAggregationMode fromWireName(String value) {
    return QualityGateRuleSetAggregationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateRuleSetAggregationMode: $value',
      ),
    );
  }
}

/// How a rule evaluation affects the final decision.
enum QualityGateDecisionImpact {
  none,
  advisory,
  contributesToPartial,
  blocksApproval,
  causesUnavailable,
  causesIncompatible,
  internalError,
}

extension QualityGateDecisionImpactX on QualityGateDecisionImpact {
  String get wireName => name;

  static QualityGateDecisionImpact fromWireName(String value) {
    return QualityGateDecisionImpact.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateDecisionImpact: $value'),
    );
  }
}

/// Gate eligibility — distinct from decision.
enum QualityGateEligibilityStatus {
  eligible,
  partiallyEligible,
  ineligible,
  unknown,
}

extension QualityGateEligibilityStatusX on QualityGateEligibilityStatus {
  String get wireName => name;

  static QualityGateEligibilityStatus fromWireName(String value) {
    return QualityGateEligibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateEligibilityStatus: $value',
      ),
    );
  }
}

/// Structural compatibility of sources and policy.
enum QualityGateCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension QualityGateCompatibilityStatusX on QualityGateCompatibilityStatus {
  String get wireName => name;

  static QualityGateCompatibilityStatus fromWireName(String value) {
    return QualityGateCompatibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateCompatibilityStatus: $value',
      ),
    );
  }
}

/// Engine execution result wrapper status.
enum QualityGateResultStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension QualityGateResultStatusX on QualityGateResultStatus {
  String get wireName => name;

  static QualityGateResultStatus fromWireName(String value) {
    return QualityGateResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateResultStatus: $value'),
    );
  }
}

/// Limitation kinds surfaced during evaluation.
enum QualityGateLimitationType {
  missingSource,
  incompatibleSource,
  unsupportedTarget,
  unsupportedOperator,
  missingEvidence,
  partialCoverage,
  staleSource,
  historicalContextMissing,
  optionalRuleUnavailable,
  policyCandidate,
  providerCapabilityGap,
}

extension QualityGateLimitationTypeX on QualityGateLimitationType {
  String get wireName => name;

  static QualityGateLimitationType fromWireName(String value) {
    return QualityGateLimitationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown QualityGateLimitationType: $value'),
    );
  }
}
