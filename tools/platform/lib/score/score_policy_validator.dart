import '../metrics/metrics_definitions.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';

/// Validates score policy structural integrity.
class ScorePolicyValidator {
  const ScorePolicyValidator();

  ScorePolicyValidationResult validate(ScorePolicy policy) {
    final errors = <String>[];
    final warnings = <String>[];

    if (policy.policyId.isEmpty) errors.add('policyId is empty');
    if (policy.policyVersion <= 0) errors.add('policyVersion is invalid');
    if (policy.policySchemaVersion <= 0) {
      errors.add('policySchemaVersion is invalid');
    }
    if (policy.dimensions.isEmpty) errors.add('policy has no dimensions');

    final dimIds = <String>{};
    for (final dim in policy.dimensions) {
      if (dim.dimensionId.isEmpty) {
        errors.add('dimensionId is empty');
      }
      if (!dimIds.add(dim.dimensionId)) {
        errors.add('duplicate dimensionId: ${dim.dimensionId}');
      }
      if (dim.weight.value.isNaN || dim.weight.value.isInfinite) {
        errors.add('dimension weight is not finite: ${dim.dimensionId}');
      }
      if (dim.weight.value < 0) {
        errors.add('negative dimension weight: ${dim.dimensionId}');
      }
      if (dim.rules.isEmpty) {
        errors.add('dimension without rules: ${dim.dimensionId}');
      }

      final ruleIds = <String>{};
      for (final rule in dim.rules) {
        if (rule.ruleId.isEmpty) errors.add('ruleId is empty');
        if (!ruleIds.add(rule.ruleId)) {
          errors.add('duplicate ruleId: ${rule.ruleId}');
        }
        if (rule.metricId.isEmpty) errors.add('metricId is empty');
        if (rule.weight.value < 0) {
          errors.add('negative rule weight: ${rule.ruleId}');
        }
        if (rule.weight.value.isNaN || rule.weight.value.isInfinite) {
          errors.add('rule weight is not finite: ${rule.ruleId}');
        }
        if (!_knownMetric(rule.metricId) &&
            !rule.metricId.startsWith('history.')) {
          warnings.add('unknown metric reference: ${rule.metricId}');
        }
        if (!_operatorCompatible(rule)) {
          errors.add('operator incompatible with rule: ${rule.ruleId}');
        }
        if (_invalidThresholds(rule)) {
          errors.add('invalid thresholds for rule: ${rule.ruleId}');
        }
        if (_invalidNormalization(rule.normalization, policy.scoreScale)) {
          errors.add('invalid normalization for rule: ${rule.ruleId}');
        }
      }
    }

    if (policy.minimumEvidenceCoverage < 0 ||
        policy.minimumEvidenceCoverage > 100) {
      errors.add('minimumEvidenceCoverage out of range');
    }
    if (policy.scoreScale.min >= policy.scoreScale.max) {
      errors.add('invalid score scale');
    }
    if (policy.metadata.experimental) {
      warnings.add('policy is marked experimental');
    }

    return ScorePolicyValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  bool _knownMetric(String metricId) {
    return MetricsDefinitions.all.containsKey(metricId) ||
        metricId.startsWith('history.');
  }

  bool _operatorCompatible(ScoreRule rule) {
    final op = rule.condition.operator;
    if (op == ScoreRuleOperator.exists ||
        op == ScoreRuleOperator.unavailable ||
        op == ScoreRuleOperator.changed ||
        op == ScoreRuleOperator.increased ||
        op == ScoreRuleOperator.decreased) {
      return true;
    }
    if (rule.metricId == 'guardian.decision' ||
        rule.metricId.startsWith('history.')) {
      return op == ScoreRuleOperator.equals ||
          op == ScoreRuleOperator.notEquals ||
          op == ScoreRuleOperator.changed;
    }
    return true;
  }

  bool _invalidThresholds(ScoreRule rule) {
    final op = rule.condition.operator;
    if (op == ScoreRuleOperator.betweenInclusive ||
        op == ScoreRuleOperator.betweenExclusive) {
      final min = rule.condition.threshold;
      final max = rule.condition.thresholdMax;
      if (min == null || max == null) return true;
      return min > max;
    }
    return false;
  }

  bool _invalidNormalization(ScoreNormalization norm, ScoreScale scale) {
    if (norm.method == ScoreNormalizationMethod.linearRange ||
        norm.method == ScoreNormalizationMethod.cappedLinear) {
      final min = norm.domainMin ?? scale.min;
      final max = norm.domainMax ?? scale.max;
      if (min > max) return true;
    }
    if (norm.method == ScoreNormalizationMethod.thresholdBands &&
        norm.bands.isEmpty) {
      return true;
    }
    return false;
  }
}
