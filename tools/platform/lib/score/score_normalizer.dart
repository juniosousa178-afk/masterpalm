import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';
import 'score_canonical_serializer.dart';

/// Applies declared normalization formulas to raw values.
class ScoreNormalizer {
  const ScoreNormalizer({ScoreCanonicalSerializer? serializer})
      : _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _serializer;

  double normalize({
    required ScoreNormalization config,
    required ScoreScale scale,
    double? numericValue,
    String? textValue,
    bool? booleanValue,
    double? ruleOutcomeScore,
  }) {
    switch (config.method) {
      case ScoreNormalizationMethod.direct:
        final value = ruleOutcomeScore ?? numericValue ?? 0;
        return _clampToScale(value, config, scale);
      case ScoreNormalizationMethod.inverse:
        final domainMin = config.domainMin ?? 0;
        final domainMax = config.domainMax ?? scale.max;
        final value = numericValue ?? 0;
        if (domainMax == domainMin) {
          return _clampToScale(scale.min, config, scale);
        }
        final inverted = scale.min +
            ((domainMax - value) / (domainMax - domainMin)) *
                (scale.max - scale.min);
        return _clampToScale(inverted, config, scale);
      case ScoreNormalizationMethod.linearRange:
        final min = config.domainMin ?? scale.min;
        final max = config.domainMax ?? scale.max;
        final value = numericValue ?? 0;
        if (max == min) return scale.min;
        final normalized =
            scale.min + ((value - min) / (max - min)) * (scale.max - scale.min);
        return _clampToScale(normalized, config, scale);
      case ScoreNormalizationMethod.cappedLinear:
        final min = config.domainMin ?? scale.min;
        final max = config.domainMax ?? scale.max;
        final value = (numericValue ?? 0).clamp(min, max);
        if (max == min) return scale.min;
        final normalized =
            scale.min + ((value - min) / (max - min)) * (scale.max - scale.min);
        return _clampToScale(normalized, config, scale);
      case ScoreNormalizationMethod.booleanMapping:
        final boolVal = booleanValue ?? false;
        final mapped = boolVal
            ? (config.booleanTrueScore ?? scale.max)
            : (config.booleanFalseScore ?? scale.min);
        return _serializer.roundScore(mapped, scale.precision);
      case ScoreNormalizationMethod.thresholdBands:
        final value = numericValue ?? 0;
        for (final band in config.bands) {
          if (value >= band.min && value <= band.max) {
            return _serializer.roundScore(band.score, scale.precision);
          }
        }
        return _clampToScale(ruleOutcomeScore ?? scale.min, config, scale);
    }
  }

  double _clampToScale(
    double value,
    ScoreNormalization config,
    ScoreScale scale,
  ) {
    var result = value;
    if (config.clamp) {
      result = result.clamp(scale.min, scale.max);
    }
    return _serializer.roundScore(result, scale.precision);
  }
}
