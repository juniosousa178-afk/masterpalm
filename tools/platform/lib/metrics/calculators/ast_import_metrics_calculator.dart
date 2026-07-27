import '../../models/metrics/metric_availability.dart';
import '../../models/metrics/metric_record.dart';
import '../../models/metrics/metric_source.dart';
import '../../models/metrics/metric_value.dart';
import '../metric_calculator.dart';
import '../metrics_definitions.dart';

/// Imports AST report metrics without recalculation.
class AstImportMetricsCalculator implements MetricCalculator {
  const AstImportMetricsCalculator();

  @override
  Set<String> get metricIds => MetricsDefinitions.astMetricIds;

  @override
  Set<MetricSource> get requiredSources => {MetricSource.ast};

  @override
  List<MetricRecord> calculate(MetricsCalculationContext context) {
    final records = <MetricRecord>[];
    final defs = MetricsDefinitions.all;
    final ast = context.astReport;

    MetricRecord unavailable(String id) => MetricRecord(
          definition: defs[id]!,
          availability: MetricAvailability.unavailable,
          message: 'AST report was not provided',
        );

    if (ast == null || ast.isEmpty) {
      for (final id in metricIds) {
        if (!context.wants(id)) continue;
        records.add(unavailable(id));
      }
      return records;
    }

    final meta = ast['meta'] as Map<String, dynamic>? ?? {};
    final metrics = ast['metrics'] as Map<String, dynamic>? ?? {};

    if (context.wants('ast.file.count')) {
      records.add(MetricRecord(
        definition: defs['ast.file.count']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(meta['files_analyzed'] as int? ?? 0),
      ));
    }

    if (context.wants('ast.class.count')) {
      records.add(MetricRecord(
        definition: defs['ast.class.count']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(metrics['total_classes'] as int? ?? 0),
      ));
    }

    if (context.wants('ast.method.count')) {
      records.add(MetricRecord(
        definition: defs['ast.method.count']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(metrics['total_methods'] as int? ?? 0),
      ));
    }

    return records;
  }
}
