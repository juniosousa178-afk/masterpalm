import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';

/// Validates declarative quality gate policies.
class QualityGatePolicyValidator {
  const QualityGatePolicyValidator();

  QualityGateValidationResult validate(
    QualityGatePolicy policy, {
    bool allowRetired = false,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      errors.add('policyId is required');
    }
    if (metadata.policyName.isEmpty) {
      errors.add('policyName is required');
    }
    if (metadata.owner.isEmpty) {
      errors.add('owner is required');
    }
    if (metadata.rationale.isEmpty) {
      errors.add('rationale is required');
    }
    if (metadata.policyVersion < 1) {
      errors.add('policyVersion must be >= 1');
    }
    if (metadata.status == QualityGatePolicyStatus.retired && !allowRetired) {
      warnings.add(
        'retired policy should only be used with historicalEvaluation',
      );
    }

    final ruleSetIds = <String>{};
    for (final ruleSet in policy.ruleSets) {
      if (!ruleSetIds.add(ruleSet.ruleSetId)) {
        errors.add('duplicate ruleSetId: ${ruleSet.ruleSetId}');
      }
      if (ruleSet.rules.isEmpty) {
        warnings.add('rule set ${ruleSet.ruleSetId} has no rules');
      }
      if (ruleSet.aggregationMode ==
              QualityGateRuleSetAggregationMode.minimumCount &&
          ruleSet.minimumPassCount == null) {
        errors.add(
          'rule set ${ruleSet.ruleSetId} requires minimumPassCount',
        );
      }
      if (ruleSet.aggregationMode ==
              QualityGateRuleSetAggregationMode.minimumPercentage &&
          ruleSet.minimumPassPercentage == null) {
        errors.add(
          'rule set ${ruleSet.ruleSetId} requires minimumPassPercentage',
        );
      }
    }

    final ruleIds = <String>{};
    for (final rule in policy.allRules) {
      if (!ruleIds.add(rule.ruleId)) {
        errors.add('duplicate ruleId: ${rule.ruleId}');
      }
      _validateRule(rule, errors, warnings);
    }

    if (policy.decisionPolicy.minimumCoveragePercentage < 0 ||
        policy.decisionPolicy.minimumCoveragePercentage > 100) {
      errors.add('minimumCoveragePercentage must be between 0 and 100');
    }

    if (policy.requiredSourceTypes.isEmpty) {
      warnings.add('policy has no requiredSourceTypes');
    }

    return QualityGateValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  void _validateRule(
    QualityGateRule rule,
    List<String> errors,
    List<String> warnings,
  ) {
    if (rule.name.isEmpty) {
      errors.add('rule ${rule.ruleId} missing name');
    }
    if (rule.explanationTemplateId.isEmpty) {
      errors.add('rule ${rule.ruleId} missing explanationTemplateId');
    }

    if (rule.requirement == QualityGateRuleRequirement.informational &&
        (rule.severity == QualityGateRuleSeverity.blocking ||
            rule.severity == QualityGateRuleSeverity.critical)) {
      errors.add(
        'rule ${rule.ruleId}: informational rules cannot be blocking or critical',
      );
    }

    if (rule.requirement == QualityGateRuleRequirement.required &&
        !rule.enabled) {
      warnings.add(
        'rule ${rule.ruleId}: required rule is disabled',
      );
    }

    if (rule.requirement == QualityGateRuleRequirement.required &&
        rule.missingDataPolicy == QualityGateMissingDataPolicy.skip) {
      warnings.add(
        'rule ${rule.ruleId}: required rule should not use skip missingDataPolicy',
      );
    }

    _validateOperatorAndValue(rule, errors);
    _validateExpectedValue(rule.expectedValue, rule.ruleId, errors);
  }

  void _validateOperatorAndValue(QualityGateRule rule, List<String> errors) {
    final operator = rule.operator;
    final expected = rule.expectedValue;

    const stateOperators = {
      QualityGateRuleOperator.isTrue,
      QualityGateRuleOperator.isFalse,
      QualityGateRuleOperator.isAvailable,
      QualityGateRuleOperator.isUnavailable,
      QualityGateRuleOperator.isCompatible,
      QualityGateRuleOperator.isIncompatible,
      QualityGateRuleOperator.isEligible,
      QualityGateRuleOperator.isNotEligible,
      QualityGateRuleOperator.isEmpty,
      QualityGateRuleOperator.isNotEmpty,
      QualityGateRuleOperator.exists,
      QualityGateRuleOperator.doesNotExist,
    };

    if (stateOperators.contains(operator)) {
      if (expected != null) {
        errors.add(
          'rule ${rule.ruleId}: operator ${operator.wireName} must not have expectedValue',
        );
      }
      return;
    }

    if (expected == null) {
      errors.add(
        'rule ${rule.ruleId}: operator ${operator.wireName} requires expectedValue',
      );
      return;
    }

    switch (operator) {
      case QualityGateRuleOperator.greaterThan:
      case QualityGateRuleOperator.greaterThanOrEqual:
      case QualityGateRuleOperator.lessThan:
      case QualityGateRuleOperator.lessThanOrEqual:
      case QualityGateRuleOperator.betweenInclusive:
      case QualityGateRuleOperator.betweenExclusive:
      case QualityGateRuleOperator.outsideRange:
        if (expected is! QualityGateDecimalValue &&
            expected is! QualityGateIntegerValue &&
            expected is! QualityGatePercentageValue &&
            expected is! QualityGateRangeValue) {
          errors.add(
            'rule ${rule.ruleId}: numeric operator requires numeric expectedValue',
          );
        }
        break;
      case QualityGateRuleOperator.inSet:
      case QualityGateRuleOperator.notInSet:
      case QualityGateRuleOperator.containsAny:
      case QualityGateRuleOperator.containsAll:
        if (expected is! QualityGateSetValue) {
          errors.add(
            'rule ${rule.ruleId}: set operator requires QualityGateSetValue',
          );
        }
        break;
      case QualityGateRuleOperator.equals:
      case QualityGateRuleOperator.notEquals:
        break;
      default:
        break;
    }
  }

  void _validateExpectedValue(
    QualityGateRuleValue? value,
    String ruleId,
    List<String> errors,
  ) {
    if (value == null) return;

    if (value is QualityGateDecimalValue) {
      if (value.value.isNaN || value.value.isInfinite) {
        errors.add('rule $ruleId: non-finite decimal expectedValue');
      }
    }

    if (value is QualityGatePercentageValue) {
      if (value.value < 0 || value.value > 100) {
        errors.add('rule $ruleId: percentage expectedValue out of range');
      }
    }

    if (value is QualityGateRangeValue) {
      if (value.lower > value.upper) {
        errors.add('rule $ruleId: inverted range expectedValue');
      }
    }

    if (value is QualityGateSetValue && value.values.isEmpty) {
      errors.add('rule $ruleId: empty set expectedValue');
    }
  }
}
