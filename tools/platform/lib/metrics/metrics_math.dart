/// Normalizes decimal values for canonical serialization.
class MetricsMath {
  const MetricsMath._();

  static const int maxDecimalPlaces = 6;

  static double normalizeDecimal(double value) {
    if (value.isNaN || value.isInfinite) {
      throw ArgumentError('Invalid decimal metric value: $value');
    }
    if (value == 0 || value == -0.0) return 0.0;
    final factor = _pow10(maxDecimalPlaces);
    final rounded = (value * factor).roundToDouble() / factor;
    return rounded == -0.0 ? 0.0 : rounded;
  }

  static double safeRatio(int numerator, int denominator) {
    if (denominator <= 0) return 0.0;
    return normalizeDecimal(numerator / denominator);
  }

  static double directedDensity(int nodeCount, int edgeCount) {
    if (nodeCount < 2) return 0.0;
    final possible = nodeCount * (nodeCount - 1);
    return safeRatio(edgeCount, possible);
  }

  static double _pow10(int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= 10;
    }
    return result;
  }
}
