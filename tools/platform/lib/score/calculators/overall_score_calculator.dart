import '../../models/score/score_enums.dart';
import '../../models/score/score_policy.dart';
import '../../models/score/score_snapshot.dart';
import '../score_aggregator.dart';

/// Calculates overall score from dimension results.
class OverallScoreCalculator {
  const OverallScoreCalculator({ScoreAggregator? aggregator})
      : _aggregator = aggregator ?? const ScoreAggregator();

  final ScoreAggregator _aggregator;

  ScoreValue calculate({
    required ScorePolicy policy,
    required List<ScoreDimensionResult> dimensions,
  }) {
    final available = dimensions
        .where(
          (d) =>
              d.availability != ScoreAvailability.unavailable &&
              d.normalizedScore != null,
        )
        .map((d) => (score: d.normalizedScore!, weight: d.weight))
        .toList();

    if (available.isEmpty) {
      return ScoreValue(
        value: policy.scoreScale.min,
        scaleMin: policy.scoreScale.min,
        scaleMax: policy.scoreScale.max,
      );
    }

    final overall = _aggregator.aggregate(
      method: policy.aggregationMethod,
      items: available,
      precision: policy.scoreScale.precision,
      scaleMin: policy.scoreScale.min,
      scaleMax: policy.scoreScale.max,
    );

    return ScoreValue(
      value: overall,
      scaleMin: policy.scoreScale.min,
      scaleMax: policy.scoreScale.max,
    );
  }
}
