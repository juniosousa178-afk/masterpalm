import '../models/score/score_enums.dart';
import 'score_canonical_serializer.dart';
import 'score_exceptions.dart';

/// Aggregates dimension and overall scores.
class ScoreAggregator {
  const ScoreAggregator({ScoreCanonicalSerializer? serializer})
      : _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _serializer;

  double aggregate({
    required ScoreAggregationMethod method,
    required List<({double score, double weight})> items,
    required int precision,
    required double scaleMin,
    required double scaleMax,
  }) {
    final available =
        items.where((e) => e.weight > 0 && e.score.isFinite).toList();
    if (available.isEmpty) {
      throw ScoreValidationException('No available scores to aggregate');
    }

    double result;
    switch (method) {
      case ScoreAggregationMethod.weightedAverage:
        var weightedSum = 0.0;
        var weightSum = 0.0;
        for (final item in available) {
          weightedSum += item.score * item.weight;
          weightSum += item.weight;
        }
        if (weightSum == 0) {
          throw ScoreValidationException('Total weight is zero');
        }
        result = weightedSum / weightSum;
      case ScoreAggregationMethod.arithmeticMean:
        result = available.map((e) => e.score).reduce((a, b) => a + b) /
            available.length;
      case ScoreAggregationMethod.minimum:
        result = available.map((e) => e.score).reduce((a, b) => a < b ? a : b);
      case ScoreAggregationMethod.maximum:
        result = available.map((e) => e.score).reduce((a, b) => a > b ? a : b);
    }
    return _serializer.roundScore(
      result.clamp(scaleMin, scaleMax),
      precision,
    );
  }
}
