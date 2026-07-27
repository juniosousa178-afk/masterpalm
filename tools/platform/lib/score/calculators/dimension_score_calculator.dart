import '../../models/score/score_enums.dart';
import '../../models/score/score_policy.dart';
import '../../models/score/score_snapshot.dart';
import '../score_aggregator.dart';
import '../score_input.dart';
import '../score_rule_evaluator.dart';

/// Calculates dimension-level scores.
class DimensionScoreCalculator {
  const DimensionScoreCalculator({
    ScoreRuleEvaluator? evaluator,
    ScoreAggregator? aggregator,
  })  : _evaluator = evaluator ?? const ScoreRuleEvaluator(),
        _aggregator = aggregator ?? const ScoreAggregator();

  final ScoreRuleEvaluator _evaluator;
  final ScoreAggregator _aggregator;

  ScoreDimensionResult calculate({
    required ScoreDimensionPolicy dimension,
    required ScorePolicy policy,
    required ScoreInput input,
    required ScoreMissingDataPolicy missingPolicy,
  }) {
    final dimMissingPolicy = dimension.missingDataPolicy ?? missingPolicy;
    final ruleResults = <ScoreRuleResult>[];
    final warnings = <String>[];
    var requested = 0;
    var available = 0;
    var unavailable = 0;
    var used = 0;
    final missingMetricIds = <String>[];

    final sortedRules = dimension.rules.toList()
      ..sort((a, b) => a.ruleId.compareTo(b.ruleId));

    for (final rule in sortedRules) {
      if (input.requestedRuleIds != null &&
          !input.requestedRuleIds!.contains(rule.ruleId)) {
        continue;
      }
      requested++;
      MetricEvidenceValue? evidence;
      if (!rule.metricId.startsWith('history.')) {
        final record = input.metricsById[rule.metricId];
        evidence =
            record == null ? null : MetricEvidenceValue.fromRecord(record);
        if (evidence == null ||
            evidence.availability == ScoreAvailability.unavailable) {
          unavailable++;
          missingMetricIds.add(rule.metricId);
        } else {
          available++;
        }
      }

      final result = _evaluator.evaluate(
        rule: rule,
        scale: policy.scoreScale,
        evidence: evidence,
        historyDiff: input.historyDiff,
        hasGuardian: input.hasGuardian(),
      );
      ruleResults.add(result);
      if (result.matched && result.normalizedScore != null) used++;
      warnings.addAll(result.warnings);
    }

    final matchedScores = ruleResults
        .where((r) => r.matched && r.normalizedScore != null)
        .map((r) {
      final rule = sortedRules.firstWhere((x) => x.ruleId == r.ruleId);
      return (score: r.normalizedScore!, weight: rule.weight.value);
    }).toList();

    ScoreAvailability availability = ScoreAvailability.available;
    double? normalizedScore;
    double? weightedContribution;

    if (matchedScores.isEmpty) {
      switch (dimMissingPolicy) {
        case ScoreMissingDataPolicy.fail:
          availability = ScoreAvailability.unavailable;
        case ScoreMissingDataPolicy.markUnavailable:
          availability = ScoreAvailability.unavailable;
        case ScoreMissingDataPolicy.excludeAndReweight:
          availability = ScoreAvailability.partial;
          warnings.add('Dimension ${dimension.dimensionId}: no matched rules');
        case ScoreMissingDataPolicy.useNeutralValue:
          normalizedScore = (policy.scoreScale.min + policy.scoreScale.max) / 2;
          availability = ScoreAvailability.partial;
        case ScoreMissingDataPolicy.useConfiguredFallback:
          normalizedScore = dimension.fallbackScore;
          availability = ScoreAvailability.partial;
      }
    } else {
      try {
        normalizedScore = _aggregator.aggregate(
          method: dimension.aggregationMethod,
          items: matchedScores,
          precision: policy.scoreScale.precision,
          scaleMin: policy.scoreScale.min,
          scaleMax: policy.scoreScale.max,
        );
      } catch (_) {
        availability = ScoreAvailability.unavailable;
      }
    }

    final totalWeight = dimension.weight.value;
    if (normalizedScore != null &&
        availability != ScoreAvailability.unavailable) {
      weightedContribution = normalizedScore * totalWeight;
    }

    final coverage = ScoreCoverage(
      requestedEvidenceCount: requested,
      availableEvidenceCount: available,
      unavailableEvidenceCount: unavailable,
      usedEvidenceCount: used,
      coveragePercentage: requested == 0 ? 0 : (used / requested) * 100,
      totalConfiguredWeight: totalWeight,
      appliedWeight: matchedScores.isEmpty ? 0 : totalWeight,
      excludedWeight: matchedScores.isEmpty ? totalWeight : 0,
      missingMetricIds: missingMetricIds,
    );

    return ScoreDimensionResult(
      dimensionId: dimension.dimensionId,
      name: dimension.name,
      availability: availability,
      weight: totalWeight,
      rules: ruleResults,
      coverage: coverage,
      normalizedScore: normalizedScore,
      weightedContribution: weightedContribution,
      warnings: warnings,
      contributions: matchedScores
          .map(
            (m) => ScoreContribution(
              subjectId: dimension.dimensionId,
              weight: m.weight,
              score: m.score,
              weightedContribution: m.score * m.weight,
            ),
          )
          .toList(),
    );
  }
}
