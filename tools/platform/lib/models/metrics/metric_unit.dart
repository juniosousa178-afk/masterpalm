/// Unit of measurement for a metric value.
enum MetricUnit {
  count,
  ratio,
  percentage,
  depth,
  text,
  boolean,
  none,
}

extension MetricUnitX on MetricUnit {
  String get wireName => name;

  static MetricUnit fromWireName(String value) {
    return MetricUnit.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MetricUnit: $value'),
    );
  }
}
