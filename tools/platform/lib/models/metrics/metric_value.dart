import 'metric_distribution.dart';
import 'metric_series.dart';
import 'metric_value_type.dart';

/// Discriminated union for typed metric values.
sealed class MetricValue {
  const MetricValue();

  MetricValueType get valueType;

  Map<String, dynamic> toJson();

  factory MetricValue.fromJson(Map<String, dynamic> json) {
    switch (json['valueType'] as String) {
      case 'integer':
        return IntegerMetricValue.fromJson(json);
      case 'decimal':
        return DecimalMetricValue.fromJson(json);
      case 'percentage':
        return PercentageMetricValue.fromJson(json);
      case 'booleanValue':
        return BooleanMetricValue.fromJson(json);
      case 'text':
        return TextMetricValue.fromJson(json);
      case 'distribution':
        return DistributionMetricValue.fromJson(json);
      case 'integerSeries':
        return IntegerSeriesMetricValue.fromJson(json);
      case 'decimalSeries':
        return DecimalSeriesMetricValue.fromJson(json);
      default:
        throw FormatException('Unknown MetricValue type: ${json['valueType']}');
    }
  }
}

class IntegerMetricValue extends MetricValue {
  const IntegerMetricValue(this.value);

  final int value;

  @override
  MetricValueType get valueType => MetricValueType.integer;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'value': value,
      };

  factory IntegerMetricValue.fromJson(Map<String, dynamic> json) {
    return IntegerMetricValue(json['value'] as int);
  }
}

class DecimalMetricValue extends MetricValue {
  const DecimalMetricValue(this.value);

  final double value;

  @override
  MetricValueType get valueType => MetricValueType.decimal;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'value': value,
      };

  factory DecimalMetricValue.fromJson(Map<String, dynamic> json) {
    return DecimalMetricValue((json['value'] as num).toDouble());
  }
}

class PercentageMetricValue extends MetricValue {
  const PercentageMetricValue(this.value);

  /// Value between 0 and 100.
  final double value;

  @override
  MetricValueType get valueType => MetricValueType.percentage;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'value': value,
      };

  factory PercentageMetricValue.fromJson(Map<String, dynamic> json) {
    return PercentageMetricValue((json['value'] as num).toDouble());
  }
}

class BooleanMetricValue extends MetricValue {
  const BooleanMetricValue(this.value);

  final bool value;

  @override
  MetricValueType get valueType => MetricValueType.booleanValue;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'value': value,
      };

  factory BooleanMetricValue.fromJson(Map<String, dynamic> json) {
    return BooleanMetricValue(json['value'] as bool);
  }
}

class TextMetricValue extends MetricValue {
  const TextMetricValue(this.value);

  final String value;

  @override
  MetricValueType get valueType => MetricValueType.text;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'value': value,
      };

  factory TextMetricValue.fromJson(Map<String, dynamic> json) {
    return TextMetricValue(json['value'] as String);
  }
}

class DistributionMetricValue extends MetricValue {
  const DistributionMetricValue(this.distribution);

  final MetricDistribution distribution;

  @override
  MetricValueType get valueType => MetricValueType.distribution;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'distribution': distribution.toJson(),
      };

  factory DistributionMetricValue.fromJson(Map<String, dynamic> json) {
    return DistributionMetricValue(
      MetricDistribution.fromJson(
        json['distribution'] as Map<String, dynamic>,
      ),
    );
  }
}

class IntegerSeriesMetricValue extends MetricValue {
  const IntegerSeriesMetricValue(this.series);

  final MetricSeries<int> series;

  @override
  MetricValueType get valueType => MetricValueType.integerSeries;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'series': series.toJson(),
      };

  factory IntegerSeriesMetricValue.fromJson(Map<String, dynamic> json) {
    return IntegerSeriesMetricValue(
      MetricSeries<int>.fromJson(json['series'] as Map<String, dynamic>),
    );
  }
}

class DecimalSeriesMetricValue extends MetricValue {
  const DecimalSeriesMetricValue(this.series);

  final MetricSeries<double> series;

  @override
  MetricValueType get valueType => MetricValueType.decimalSeries;

  @override
  Map<String, dynamic> toJson() => {
        'valueType': valueType.wireName,
        'series': series.toJson(),
      };

  factory DecimalSeriesMetricValue.fromJson(Map<String, dynamic> json) {
    return DecimalSeriesMetricValue(
      MetricSeries<double>.fromJson(json['series'] as Map<String, dynamic>),
    );
  }
}
