import 'metric_availability.dart';
import 'metric_definition.dart';
import 'metric_dimension.dart';
import 'metric_value.dart';

/// Single calculated metric within a [MetricsSnapshot].
class MetricRecord {
  const MetricRecord({
    required this.definition,
    required this.availability,
    this.value,
    this.dimensions = const [],
    this.message,
  });

  final MetricDefinition definition;
  final MetricAvailability availability;
  final MetricValue? value;
  final List<MetricDimension> dimensions;
  final String? message;

  Map<String, dynamic> toJson() => {
        'definition': definition.toJson(),
        'availability': availability.wireName,
        if (value != null) 'value': value!.toJson(),
        if (dimensions.isNotEmpty)
          'dimensions': dimensions.map((d) => d.toJson()).toList(),
        if (message != null) 'message': message,
      };

  factory MetricRecord.fromJson(Map<String, dynamic> json) {
    return MetricRecord(
      definition: MetricDefinition.fromJson(
        json['definition'] as Map<String, dynamic>,
      ),
      availability: MetricAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      value: json['value'] == null
          ? null
          : MetricValue.fromJson(json['value'] as Map<String, dynamic>),
      dimensions: (json['dimensions'] as List<dynamic>? ?? [])
          .map((e) => MetricDimension.fromJson(e as Map<String, dynamic>))
          .toList(),
      message: json['message'] as String?,
    );
  }
}
