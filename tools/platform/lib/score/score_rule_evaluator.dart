import '../models/history/history_change_type.dart';
import '../models/history/history_diff.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';
import '../models/score/score_snapshot.dart';
import 'score_input.dart';
import 'score_normalizer.dart';

/// Evaluates typed score rules against resolved evidence.
class ScoreRuleEvaluator {
  const ScoreRuleEvaluator({ScoreNormalizer? normalizer})
      : _normalizer = normalizer ?? const ScoreNormalizer();

  final ScoreNormalizer _normalizer;

  ScoreRuleResult evaluate({
    required ScoreRule rule,
    required ScoreScale scale,
    required MetricEvidenceValue? evidence,
    required HistoryDiff? historyDiff,
    required bool hasGuardian,
  }) {
    if (rule.requiresHistoryDiff && historyDiff == null) {
      return _unavailable(
        rule,
        'HistoryDiff required but not provided',
      );
    }
    if (rule.requiresGuardian && !hasGuardian) {
      return _unavailable(rule, 'Guardian analysis required but not provided');
    }

    if (_isHistoryOperator(rule.condition.operator)) {
      return _evaluateHistoryRule(rule, scale, historyDiff);
    }

    if (evidence == null ||
        evidence.availability == ScoreAvailability.unavailable) {
      if (rule.condition.operator == ScoreRuleOperator.unavailable) {
        final score = _normalizer.normalize(
          config: rule.normalization,
          scale: scale,
          ruleOutcomeScore: rule.outcome.score,
        );
        return ScoreRuleResult(
          ruleId: rule.ruleId,
          metricId: rule.metricId,
          availability: ScoreAvailability.available,
          matched: true,
          rawScore: rule.outcome.score,
          normalizedScore: score,
          contribution: score * rule.weight.value,
          explanation: 'Metric unavailable; unavailable rule matched',
        );
      }
      return _unavailable(
        rule,
        evidence?.message ?? 'Metric evidence unavailable',
      );
    }

    if (rule.condition.operator == ScoreRuleOperator.exists) {
      final score = _normalizer.normalize(
        config: rule.normalization,
        scale: scale,
        numericValue: evidence.numericValue,
        textValue: evidence.textValue,
        booleanValue: evidence.booleanValue,
        ruleOutcomeScore: rule.outcome.score,
      );
      return ScoreRuleResult(
        ruleId: rule.ruleId,
        metricId: rule.metricId,
        availability: ScoreAvailability.available,
        matched: true,
        rawScore: evidence.numericValue ?? rule.outcome.score,
        normalizedScore: score,
        contribution: score * rule.weight.value,
        evidence: ScoreEvidence(
          evidenceId: '${rule.metricId}:exists',
          sourceType: 'metrics',
          metricId: rule.metricId,
          observedValue: evidence.numericValue,
          observedText: evidence.textValue,
          availability: evidence.availability,
          unit: evidence.unit,
          calculationVersion: evidence.calculationVersion,
        ),
        explanation: rule.outcome.explanation ?? 'Metric exists',
      );
    }

    final matched = _matchesCondition(rule.condition, evidence, historyDiff);
    if (!matched) {
      return ScoreRuleResult(
        ruleId: rule.ruleId,
        metricId: rule.metricId,
        availability: evidence.availability,
        matched: false,
        evidence: ScoreEvidence(
          evidenceId: rule.ruleId,
          sourceType: 'metrics',
          metricId: rule.metricId,
          observedValue: evidence.numericValue,
          observedText: evidence.textValue,
          availability: evidence.availability,
          unit: evidence.unit,
          calculationVersion: evidence.calculationVersion,
        ),
      );
    }

    final normalized = _normalizer.normalize(
      config: rule.normalization,
      scale: scale,
      numericValue: evidence.numericValue,
      textValue: evidence.textValue,
      booleanValue: evidence.booleanValue,
      ruleOutcomeScore: rule.outcome.score,
    );

    return ScoreRuleResult(
      ruleId: rule.ruleId,
      metricId: rule.metricId,
      availability: evidence.availability,
      matched: true,
      rawScore: evidence.numericValue ?? rule.outcome.score,
      normalizedScore: normalized,
      contribution: normalized * rule.weight.value,
      evidence: ScoreEvidence(
        evidenceId: rule.ruleId,
        sourceType: 'metrics',
        metricId: rule.metricId,
        observedValue: evidence.numericValue,
        observedText: evidence.textValue,
        availability: evidence.availability,
        unit: evidence.unit,
        calculationVersion: evidence.calculationVersion,
      ),
      explanation: rule.outcome.explanation ?? rule.description,
    );
  }

  bool _matchesCondition(
    ScoreRuleCondition condition,
    MetricEvidenceValue evidence,
    HistoryDiff? historyDiff,
  ) {
    switch (condition.operator) {
      case ScoreRuleOperator.equals:
        if (evidence.textValue != null) {
          return evidence.textValue == condition.expectedText;
        }
        return evidence.numericValue == condition.threshold;
      case ScoreRuleOperator.notEquals:
        if (evidence.textValue != null) {
          return evidence.textValue != condition.expectedText;
        }
        return evidence.numericValue != condition.threshold;
      case ScoreRuleOperator.greaterThan:
        return (evidence.numericValue ?? 0) > (condition.threshold ?? 0);
      case ScoreRuleOperator.greaterThanOrEqual:
        return (evidence.numericValue ?? 0) >= (condition.threshold ?? 0);
      case ScoreRuleOperator.lessThan:
        return (evidence.numericValue ?? 0) < (condition.threshold ?? 0);
      case ScoreRuleOperator.lessThanOrEqual:
        return (evidence.numericValue ?? 0) <= (condition.threshold ?? 0);
      case ScoreRuleOperator.betweenInclusive:
        final v = evidence.numericValue ?? 0;
        return v >= (condition.threshold ?? 0) &&
            v <= (condition.thresholdMax ?? 0);
      case ScoreRuleOperator.betweenExclusive:
        final v = evidence.numericValue ?? 0;
        return v > (condition.threshold ?? 0) &&
            v < (condition.thresholdMax ?? 0);
      case ScoreRuleOperator.exists:
      case ScoreRuleOperator.unavailable:
        return true;
      case ScoreRuleOperator.changed:
      case ScoreRuleOperator.increased:
      case ScoreRuleOperator.decreased:
        return _historyMatches(condition, historyDiff);
    }
  }

  ScoreRuleResult _evaluateHistoryRule(
    ScoreRule rule,
    ScoreScale scale,
    HistoryDiff? historyDiff,
  ) {
    final matched = _historyMatches(rule.condition, historyDiff);
    if (!matched) {
      return ScoreRuleResult(
        ruleId: rule.ruleId,
        metricId: rule.metricId,
        availability: ScoreAvailability.available,
        matched: false,
      );
    }
    final score = _normalizer.normalize(
      config: rule.normalization,
      scale: scale,
      ruleOutcomeScore: rule.outcome.score,
    );
    return ScoreRuleResult(
      ruleId: rule.ruleId,
      metricId: rule.metricId,
      availability: ScoreAvailability.available,
      matched: true,
      rawScore: rule.outcome.score,
      normalizedScore: score,
      contribution: score * rule.weight.value,
      evidence: ScoreEvidence(
        evidenceId: '${rule.ruleId}:history',
        sourceType: 'history',
        metricId: rule.metricId,
        availability: ScoreAvailability.available,
      ),
      explanation: rule.outcome.explanation ?? 'History condition matched',
    );
  }

  bool _historyMatches(ScoreRuleCondition condition, HistoryDiff? diff) {
    if (diff == null) return false;
    final changeType = condition.historyChangeType;
    if (changeType != null) {
      return diff.changes.any((c) => c.changeType.wireName == changeType);
    }
    switch (condition.operator) {
      case ScoreRuleOperator.changed:
        return diff.changes.isNotEmpty;
      case ScoreRuleOperator.increased:
        return diff.changes.any(
          (c) =>
              c.changeType == HistoryChangeType.metricValueChanged &&
              (c.absoluteDelta ?? 0) > 0,
        );
      case ScoreRuleOperator.decreased:
        return diff.changes.any(
          (c) =>
              c.changeType == HistoryChangeType.metricValueChanged &&
              (c.absoluteDelta ?? 0) < 0,
        );
      default:
        return false;
    }
  }

  bool _isHistoryOperator(ScoreRuleOperator op) {
    return op == ScoreRuleOperator.changed ||
        op == ScoreRuleOperator.increased ||
        op == ScoreRuleOperator.decreased;
  }

  ScoreRuleResult _unavailable(ScoreRule rule, String message) {
    return ScoreRuleResult(
      ruleId: rule.ruleId,
      metricId: rule.metricId,
      availability: ScoreAvailability.unavailable,
      matched: false,
      explanation: message,
      warnings: [message],
    );
  }
}
