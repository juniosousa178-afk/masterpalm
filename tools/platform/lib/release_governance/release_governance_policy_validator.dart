import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_rule_value.dart';
import '../models/release_governance/release_waiver.dart';

/// Validates declarative release governance policies.
class ReleaseGovernancePolicyValidator {
  const ReleaseGovernancePolicyValidator();

  ReleaseGovernanceValidationResult validate(
    ReleaseGovernancePolicy policy, {
    bool allowRetired = false,
  }) {
    final issues = <ReleaseGovernanceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message,
        {String? relatedId}) {
      errors.add(message);
      issues.add(
        ReleaseGovernanceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseGovernanceRuleSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(String code, String path, String message,
        {String? relatedId}) {
      warnings.add(message);
      issues.add(
        ReleaseGovernanceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseGovernanceRuleSeverity.warning,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError(
          'RG_POLICY_ID_REQUIRED', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RG_POLICY_VERSION_INVALID',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.owner.isEmpty) {
      addError('RG_OWNER_REQUIRED', 'metadata.owner', 'owner is required');
    }
    if (metadata.rationale.isEmpty) {
      addError('RG_RATIONALE_REQUIRED', 'metadata.rationale',
          'rationale is required');
    }
    if (metadata.calculationVersion < 1) {
      addError(
        'RG_CALCULATION_VERSION_REQUIRED',
        'metadata.calculationVersion',
        'calculationVersion is required',
      );
    }
    if (metadata.canonicalizationVersion < 1) {
      addError(
        'RG_CANONICALIZATION_VERSION_REQUIRED',
        'metadata.canonicalizationVersion',
        'canonicalizationVersion is required',
      );
    }
    if (!policy.compatibilityPolicy.supportedSchemas
        .contains(metadata.schemaVersion)) {
      addError(
        'RG_SCHEMA_UNSUPPORTED',
        'metadata.schemaVersion',
        'schemaVersion ${metadata.schemaVersion} is not supported',
      );
    }
    if (metadata.status == ReleaseGovernancePolicyStatus.retired &&
        !allowRetired) {
      addWarning(
        'RG_RETIRED_POLICY',
        'metadata.status',
        'retired policy should only be used with historicalEvaluation',
      );
    }
    if (metadata.status == ReleaseGovernancePolicyStatus.active &&
        metadata.policyId.contains('candidate')) {
      addWarning(
        'RG_CANDIDATE_ACTIVE',
        'metadata.status',
        'candidate policy should not be active',
      );
    }

    final ruleSetIds = <String>{};
    for (final ruleSet in policy.ruleSets) {
      if (!ruleSetIds.add(ruleSet.ruleSetId)) {
        addError(
          'RG_DUPLICATE_RULE_SET_ID',
          'ruleSets',
          'duplicate ruleSetId: ${ruleSet.ruleSetId}',
          relatedId: ruleSet.ruleSetId,
        );
      }
      if (ruleSet.aggregationMode ==
              ReleaseGovernanceRuleSetAggregationMode.minimumCount &&
          ruleSet.minimumPassCount == null) {
        addError(
          'RG_RULE_SET_MIN_COUNT',
          'ruleSets.${ruleSet.ruleSetId}',
          'rule set ${ruleSet.ruleSetId} requires minimumPassCount',
          relatedId: ruleSet.ruleSetId,
        );
      }
      if (ruleSet.aggregationMode ==
              ReleaseGovernanceRuleSetAggregationMode.minimumPercentage &&
          ruleSet.minimumPassPercentage == null) {
        addError(
          'RG_RULE_SET_MIN_PERCENTAGE',
          'ruleSets.${ruleSet.ruleSetId}',
          'rule set ${ruleSet.ruleSetId} requires minimumPassPercentage',
          relatedId: ruleSet.ruleSetId,
        );
      }
    }

    final ruleIds = <String>{};
    final ruleSetIdSet = ruleSetIds;
    for (final rule in policy.rules) {
      if (!ruleIds.add(rule.ruleId)) {
        addError(
          'RG_DUPLICATE_RULE_ID',
          'rules',
          'duplicate ruleId: ${rule.ruleId}',
          relatedId: rule.ruleId,
        );
      }
      if (!ruleSetIdSet.contains(rule.ruleSetId)) {
        addError(
          'RG_RULE_SET_MISSING',
          'rules.${rule.ruleId}',
          'rule ${rule.ruleId} references missing ruleSet ${rule.ruleSetId}',
          relatedId: rule.ruleId,
        );
      }
      _validateRule(rule, addError, addWarning);
    }

    for (final ruleSet in policy.ruleSets) {
      for (final ruleId in ruleSet.ruleIds) {
        if (!ruleIds.contains(ruleId)) {
          addError(
            'RG_RULE_MISSING',
            'ruleSets.${ruleSet.ruleSetId}',
            'rule set ${ruleSet.ruleSetId} references missing rule $ruleId',
            relatedId: ruleId,
          );
        }
      }
    }

    final requirementIds = <String>{};
    for (final requirement in policy.approvalRequirements) {
      if (!requirementIds.add(requirement.requirementId)) {
        addError(
          'RG_DUPLICATE_APPROVAL_REQUIREMENT',
          'approvalRequirements',
          'duplicate requirementId: ${requirement.requirementId}',
          relatedId: requirement.requirementId,
        );
      }
    }

    final hasProductionApprovals = policy.approvalRequirements.any(
      (r) =>
          r.enabled &&
          r.environmentScope.contains(ReleaseEnvironment.production) &&
          r.releaseTypeScope.contains(ReleaseType.production),
    );
    if (!hasProductionApprovals) {
      addWarning(
        'RG_PRODUCTION_APPROVALS',
        'approvalRequirements',
        'production environment has no enabled approval requirements',
      );
    }

    if (policy.supportedEnvironments.isEmpty) {
      addError(
        'RG_SUPPORTED_ENVIRONMENTS_EMPTY',
        'supportedEnvironments',
        'supportedEnvironments must not be empty',
      );
    }
    if (policy.supportedReleaseTypes.isEmpty) {
      addError(
        'RG_SUPPORTED_RELEASE_TYPES_EMPTY',
        'supportedReleaseTypes',
        'supportedReleaseTypes must not be empty',
      );
    }

    _validateDecisionPolicy(policy.decisionPolicy, addError);
    _validatePercentages(policy, addError);
    _validateWaiverPolicy(policy.waiverRules, addError);

    return ReleaseGovernanceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  void _validateRule(
    ReleaseGovernanceRule rule,
    void Function(String, String, String, {String? relatedId}) addError,
    void Function(String, String, String, {String? relatedId}) addWarning,
  ) {
    if (rule.name.isEmpty) {
      addError(
        'RG_RULE_NAME_REQUIRED',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId} missing name',
        relatedId: rule.ruleId,
      );
    }

    if (rule.requirement == ReleaseGovernanceRuleRequirement.informational &&
        (rule.severity == ReleaseGovernanceRuleSeverity.blocking ||
            rule.severity == ReleaseGovernanceRuleSeverity.critical)) {
      addError(
        'RG_INFORMATIONAL_BLOCKING',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId}: informational rules cannot be blocking or critical',
        relatedId: rule.ruleId,
      );
    }

    if (rule.requirement == ReleaseGovernanceRuleRequirement.optional &&
        rule.severity == ReleaseGovernanceRuleSeverity.critical) {
      addError(
        'RG_OPTIONAL_CRITICAL',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId}: optional + critical is invalid by default',
        relatedId: rule.ruleId,
      );
    }

    if (rule.requirement == ReleaseGovernanceRuleRequirement.required &&
        !rule.enabled) {
      addError(
        'RG_REQUIRED_DISABLED',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId}: required rule cannot be disabled',
        relatedId: rule.ruleId,
      );
    }

    if (rule.severity == ReleaseGovernanceRuleSeverity.critical &&
        rule.waiverCapability == ReleaseGovernanceWaiverCapability.allowed) {
      addError(
        'RG_CRITICAL_WAIVER_ALLOWED',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId}: critical rules cannot have waiver allowed',
        relatedId: rule.ruleId,
      );
    }

    _validateOperatorAndValue(rule, addError);
    _validateExpectedValue(rule.expectedValue, rule.ruleId, addError);
  }

  void _validateOperatorAndValue(
    ReleaseGovernanceRule rule,
    void Function(String, String, String, {String? relatedId}) addError,
  ) {
    const stateOperators = {
      ReleaseGovernanceRuleOperator.isTrue,
      ReleaseGovernanceRuleOperator.isFalse,
      ReleaseGovernanceRuleOperator.isAvailable,
      ReleaseGovernanceRuleOperator.isUnavailable,
      ReleaseGovernanceRuleOperator.isCompatible,
      ReleaseGovernanceRuleOperator.isIncompatible,
      ReleaseGovernanceRuleOperator.isValid,
      ReleaseGovernanceRuleOperator.isInvalid,
      ReleaseGovernanceRuleOperator.isEligible,
      ReleaseGovernanceRuleOperator.isNotEligible,
      ReleaseGovernanceRuleOperator.isExpired,
      ReleaseGovernanceRuleOperator.isNotExpired,
      ReleaseGovernanceRuleOperator.exists,
      ReleaseGovernanceRuleOperator.doesNotExist,
    };

    if (stateOperators.contains(rule.operator)) {
      if (rule.expectedValue != null) {
        addError(
          'RG_OPERATOR_UNEXPECTED_VALUE',
          'rules.${rule.ruleId}',
          'rule ${rule.ruleId}: operator ${rule.operator.wireName} must not have expectedValue',
          relatedId: rule.ruleId,
        );
      }
      return;
    }

    if (rule.expectedValue == null) {
      addError(
        'RG_OPERATOR_MISSING_VALUE',
        'rules.${rule.ruleId}',
        'rule ${rule.ruleId}: operator ${rule.operator.wireName} requires expectedValue',
        relatedId: rule.ruleId,
      );
      return;
    }

    switch (rule.operator) {
      case ReleaseGovernanceRuleOperator.greaterThan:
      case ReleaseGovernanceRuleOperator.greaterThanOrEqual:
      case ReleaseGovernanceRuleOperator.lessThan:
      case ReleaseGovernanceRuleOperator.lessThanOrEqual:
      case ReleaseGovernanceRuleOperator.betweenInclusive:
      case ReleaseGovernanceRuleOperator.betweenExclusive:
        if (rule.expectedValue is! ReleaseGovernanceDecimalValue &&
            rule.expectedValue is! ReleaseGovernanceIntegerValue &&
            rule.expectedValue is! ReleaseGovernancePercentageValue &&
            rule.expectedValue is! ReleaseGovernanceRangeValue &&
            rule.expectedValue is! ReleaseGovernanceDurationValue) {
          addError(
            'RG_OPERATOR_NUMERIC_VALUE',
            'rules.${rule.ruleId}',
            'rule ${rule.ruleId}: numeric operator requires numeric expectedValue',
            relatedId: rule.ruleId,
          );
        }
        break;
      case ReleaseGovernanceRuleOperator.inSet:
      case ReleaseGovernanceRuleOperator.notInSet:
      case ReleaseGovernanceRuleOperator.containsAny:
      case ReleaseGovernanceRuleOperator.containsAll:
        if (rule.expectedValue is! ReleaseGovernanceSetValue) {
          addError(
            'RG_OPERATOR_SET_VALUE',
            'rules.${rule.ruleId}',
            'rule ${rule.ruleId}: set operator requires ReleaseGovernanceSetValue',
            relatedId: rule.ruleId,
          );
        }
        break;
      default:
        break;
    }
  }

  void _validateExpectedValue(
    ReleaseGovernanceRuleValue? value,
    String ruleId,
    void Function(String, String, String, {String? relatedId}) addError,
  ) {
    if (value == null) return;
    if (value is ReleaseGovernanceDecimalValue) {
      final v = value.value;
      if (v.isNaN || v.isInfinite) {
        addError(
          'RG_NON_FINITE_DECIMAL',
          'rules.$ruleId',
          'rule $ruleId: non-finite decimal value',
          relatedId: ruleId,
        );
      }
    }
    if (value is ReleaseGovernancePercentageValue) {
      if (value.value < 0 || value.value > 100) {
        addError(
          'RG_PERCENTAGE_RANGE',
          'rules.$ruleId',
          'rule $ruleId: percentage must be between 0 and 100',
          relatedId: ruleId,
        );
      }
    }
    if (value is ReleaseGovernanceRangeValue) {
      if (value.lower > value.upper) {
        addError(
          'RG_RANGE_INVERTED',
          'rules.$ruleId',
          'rule $ruleId: range lower must be <= upper',
          relatedId: ruleId,
        );
      }
    }
  }

  void _validateDecisionPolicy(
    ReleaseGovernanceDecisionPolicy policy,
    void Function(String, String, String, {String? relatedId}) addError,
  ) {
    const rejected = {'failed', 'unavailable', 'incompatible', 'error'};
    for (final decision in policy.qualityGateAcceptedDecisions) {
      if (rejected.contains(decision)) {
        addError(
          'RG_QG_ACCEPTED_INVALID',
          'decisionPolicy.qualityGateAcceptedDecisions',
          'qualityGateAcceptedDecisions must not include rejected decisions: $decision',
        );
      }
    }
    for (final coverageField in [
      policy.minimumRuleCoverage,
      policy.minimumApprovalCoverage,
      policy.minimumEvidenceCoverage,
    ]) {
      if (coverageField < 0 || coverageField > 100) {
        addError(
          'RG_COVERAGE_RANGE',
          'decisionPolicy',
          'coverage percentages must be between 0 and 100',
        );
        break;
      }
    }
  }

  void _validatePercentages(
    ReleaseGovernancePolicy policy,
    void Function(String, String, String, {String? relatedId}) addError,
  ) {
    for (final ruleSet in policy.ruleSets) {
      final pct = ruleSet.minimumPassPercentage;
      if (pct != null && (pct < 0 || pct > 100)) {
        addError(
          'RG_RULE_SET_PERCENTAGE',
          'ruleSets.${ruleSet.ruleSetId}',
          'rule set ${ruleSet.ruleSetId}: minimumPassPercentage must be 0-100',
          relatedId: ruleSet.ruleSetId,
        );
      }
    }
  }

  void _validateWaiverPolicy(
    ReleaseWaiverPolicy waiverPolicy,
    void Function(String, String, String, {String? relatedId}) addError,
  ) {
    if (waiverPolicy.maximumActiveWaivers < 0) {
      addError(
        'RG_WAIVER_MAX_ACTIVE',
        'waiverRules.maximumActiveWaivers',
        'maximumActiveWaivers must be >= 0',
      );
    }
    if (waiverPolicy.maximumDuration.isEmpty) {
      addError(
        'RG_WAIVER_DURATION',
        'waiverRules.maximumDuration',
        'waiver maximumDuration is required',
      );
    }
    if (waiverPolicy.allowedAuthorities.isEmpty) {
      addError(
        'RG_WAIVER_AUTHORITY',
        'waiverRules.allowedAuthorities',
        'waiver allowedAuthorities must be defined',
      );
    }
  }
}
