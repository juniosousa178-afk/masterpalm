/// Authoritative source of a metric value.
enum MetricSource {
  graph,
  ast,
  guardian,
}

extension MetricSourceX on MetricSource {
  String get wireName => name;

  static MetricSource fromWireName(String value) {
    return MetricSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MetricSource: $value'),
    );
  }
}
