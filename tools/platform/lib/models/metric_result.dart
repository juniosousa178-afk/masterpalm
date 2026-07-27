/// Metric collection result for future Metrics Engine integration.
class MetricResult {
  const MetricResult({
    required this.name,
    required this.value,
    this.unit,
    this.tags = const {},
  });

  final String name;
  final num value;
  final String? unit;
  final Map<String, String> tags;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        if (unit != null) 'unit': unit,
        if (tags.isNotEmpty) 'tags': tags,
      };
}
