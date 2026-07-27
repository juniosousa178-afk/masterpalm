/// Named dimension for a metric record (e.g. nodeId, nodeType).
class MetricDimension {
  const MetricDimension({
    required this.name,
    required this.value,
  });

  final String name;
  final String value;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
      };

  factory MetricDimension.fromJson(Map<String, dynamic> json) {
    return MetricDimension(
      name: json['name'] as String,
      value: json['value'] as String,
    );
  }
}
