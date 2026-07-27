/// Ordered series of numeric values keyed by label.
class MetricSeries<T extends num> {
  const MetricSeries(this.entries);

  final Map<String, T> entries;

  Map<String, dynamic> toJson() {
    final keys = entries.keys.toList()..sort();
    return {
      for (final key in keys) key: entries[key],
    };
  }

  factory MetricSeries.fromJson(Map<String, dynamic> json) {
    return MetricSeries(
      json.map((k, v) => MapEntry(k, (v as num) as T)),
    );
  }
}
