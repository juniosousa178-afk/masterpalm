/// Validation result for [MetricsSnapshot].
class MetricsValidationResult {
  const MetricsValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.metricCount,
    required this.availableCount,
    required this.unavailableCount,
    required this.categoryCount,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final int metricCount;
  final int availableCount;
  final int unavailableCount;
  final int categoryCount;
}
