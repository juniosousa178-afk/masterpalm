/// Typed kind of a [MetricValue].
enum MetricValueType {
  integer,
  decimal,
  percentage,
  booleanValue,
  text,
  distribution,
  integerSeries,
  decimalSeries,
}

extension MetricValueTypeX on MetricValueType {
  String get wireName => name;

  static MetricValueType fromWireName(String value) {
    return MetricValueType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MetricValueType: $value'),
    );
  }
}
