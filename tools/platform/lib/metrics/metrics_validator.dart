import '../models/metrics/metric_availability.dart';
import '../models/metrics/metric_category.dart';
import '../models/metrics/metric_record.dart';
import '../models/metrics/metric_unit.dart';
import '../models/metrics/metric_value.dart';
import '../models/metrics/metric_value_type.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/metrics/metrics_validation_result.dart';
import 'metrics_math.dart';

/// Validates structural integrity of [MetricsSnapshot].
class MetricsValidator {
  const MetricsValidator();

  MetricsValidationResult validate(MetricsSnapshot snapshot) {
    final errors = <String>[];
    final warnings = <String>[];
    final metadata = snapshot.metadata;
    final metricIds = <String>{};
    var availableCount = 0;
    var unavailableCount = 0;
    final categories = <MetricCategory>{};

    if (metadata.snapshotId.isEmpty) errors.add('snapshotId is empty');
    if (metadata.projectId.isEmpty) errors.add('projectId is empty');
    if (metadata.metricsSchemaVersion < 1) {
      errors.add('metricsSchemaVersion is missing or invalid');
    }
    if (metadata.metricsCalculationVersion < 1) {
      errors.add('metricsCalculationVersion is missing or invalid');
    }
    if (metadata.sourceGraphFingerprint.isEmpty) {
      errors.add('sourceGraphFingerprint is empty');
    }

    for (var i = 1; i < snapshot.metrics.length; i++) {
      final prev = snapshot.metrics[i - 1].definition.id;
      final curr = snapshot.metrics[i].definition.id;
      if (prev.compareTo(curr) > 0) {
        warnings.add('Metrics are not in canonical id order');
        break;
      }
    }

    for (final record in snapshot.metrics) {
      categories.add(record.definition.category);
      if (!metricIds.add(record.definition.id)) {
        errors.add('Duplicate metric id: ${record.definition.id}');
      }

      if (!_unitMatches(record)) {
        errors.add(
            'Unit incompatible with valueType for ${record.definition.id}');
      }

      final dimensionNames = <String>{};
      for (final dimension in record.dimensions) {
        if (!dimensionNames.add(dimension.name)) {
          errors.add('Duplicate dimension for ${record.definition.id}');
        }
      }

      switch (record.availability) {
        case MetricAvailability.available:
          availableCount++;
          if (record.value == null) {
            errors
                .add('Available metric without value: ${record.definition.id}');
          } else {
            errors.addAll(_validateValue(record));
          }
        case MetricAvailability.unavailable:
        case MetricAvailability.unsupported:
        case MetricAvailability.invalidSource:
        case MetricAvailability.calculationError:
          unavailableCount++;
      }
    }

    if (metadata.metricCount != snapshot.metrics.length) {
      errors.add('metadata.metricCount incompatible with records');
    }
    if (metadata.unavailableMetricCount != unavailableCount) {
      errors.add('metadata.unavailableMetricCount incompatible');
    }

    return MetricsValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      metricCount: snapshot.metrics.length,
      availableCount: availableCount,
      unavailableCount: unavailableCount,
      categoryCount: categories.length,
    );
  }

  bool _unitMatches(MetricRecord record) {
    final type = record.definition.valueType;
    final unit = record.definition.unit;
    switch (type) {
      case MetricValueType.integer:
      case MetricValueType.integerSeries:
        return unit == MetricUnit.count || unit == MetricUnit.depth;
      case MetricValueType.decimal:
      case MetricValueType.decimalSeries:
        return unit == MetricUnit.count ||
            unit == MetricUnit.ratio ||
            unit == MetricUnit.none;
      case MetricValueType.percentage:
        return unit == MetricUnit.percentage;
      case MetricValueType.booleanValue:
        return unit == MetricUnit.boolean;
      case MetricValueType.text:
        return unit == MetricUnit.text;
      case MetricValueType.distribution:
        return unit == MetricUnit.count;
    }
  }

  List<String> _validateValue(MetricRecord record) {
    final errors = <String>[];
    final value = record.value!;
    switch (value) {
      case IntegerMetricValue(:final value):
        if (value < 0 &&
            !record.definition.id.contains('count') &&
            record.definition.id != 'graph.depth.bounded_max') {
          // counts and depth may be zero; generally non-negative metrics
        }
      case DecimalMetricValue(:final value):
        if (value.isNaN || value.isInfinite) {
          errors.add('NaN/Infinity in ${record.definition.id}');
        }
        try {
          MetricsMath.normalizeDecimal(value);
        } catch (_) {
          errors.add('Invalid decimal in ${record.definition.id}');
        }
      case PercentageMetricValue(:final value):
        if (value.isNaN || value.isInfinite || value < 0 || value > 100) {
          errors.add('Invalid percentage in ${record.definition.id}');
        }
      case DistributionMetricValue(:final distribution):
        final keys = distribution.entries.keys.toList();
        if (keys.toSet().length != keys.length) {
          errors.add('Duplicate distribution keys in ${record.definition.id}');
        }
        for (final entry in distribution.entries.values) {
          if (entry.isNaN || entry.isInfinite || entry < 0) {
            errors.add('Invalid distribution value in ${record.definition.id}');
          }
        }
      case IntegerSeriesMetricValue():
      case DecimalSeriesMetricValue():
        break;
      case BooleanMetricValue():
      case TextMetricValue():
        break;
    }
    return errors;
  }
}
