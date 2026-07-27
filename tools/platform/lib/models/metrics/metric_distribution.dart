/// Distribution map with stable key ordering in serialization.
class MetricDistribution {
  const MetricDistribution(this.entries);

  final Map<String, double> entries;

  Map<String, dynamic> toJson() {
    final keys = entries.keys.toList()..sort();
    return {
      for (final key in keys) key: entries[key],
    };
  }

  factory MetricDistribution.fromJson(Map<String, dynamic> json) {
    return MetricDistribution(
      json.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}
