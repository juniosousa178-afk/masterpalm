/// Availability status for a calculated metric.
enum MetricAvailability {
  available,
  unavailable,
  unsupported,
  invalidSource,
  calculationError,
}

extension MetricAvailabilityX on MetricAvailability {
  String get wireName => name;

  static MetricAvailability fromWireName(String value) {
    return MetricAvailability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MetricAvailability: $value'),
    );
  }
}
