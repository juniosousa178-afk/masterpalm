import 'metric_category.dart';
import 'metric_source.dart';
import 'metric_unit.dart';
import 'metric_value_type.dart';

/// Stable definition for a platform metric.
class MetricDefinition {
  const MetricDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.valueType,
    required this.unit,
    required this.source,
    required this.description,
    required this.calculationVersion,
  });

  final String id;
  final String name;
  final MetricCategory category;
  final MetricValueType valueType;
  final MetricUnit unit;
  final MetricSource source;
  final String description;
  final int calculationVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.wireName,
        'valueType': valueType.wireName,
        'unit': unit.wireName,
        'source': source.wireName,
        'description': description,
        'calculationVersion': calculationVersion,
      };

  factory MetricDefinition.fromJson(Map<String, dynamic> json) {
    return MetricDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      category: MetricCategoryX.fromWireName(json['category'] as String),
      valueType: MetricValueTypeX.fromWireName(json['valueType'] as String),
      unit: MetricUnitX.fromWireName(json['unit'] as String),
      source: MetricSourceX.fromWireName(json['source'] as String),
      description: json['description'] as String,
      calculationVersion: json['calculationVersion'] as int? ?? 1,
    );
  }
}
