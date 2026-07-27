import '../../models/metrics/metric_availability.dart';
import '../../models/metrics/metric_distribution.dart';
import '../../models/metrics/metric_record.dart';
import '../../models/metrics/metric_source.dart';
import '../../models/metrics/metric_value.dart';
import '../metric_calculator.dart';
import '../metrics_definitions.dart';

/// Imports Guardian metrics without recalculation.
class GuardianImportMetricsCalculator implements MetricCalculator {
  const GuardianImportMetricsCalculator();

  @override
  Set<String> get metricIds => MetricsDefinitions.guardianMetricIds;

  @override
  Set<MetricSource> get requiredSources => {MetricSource.guardian};

  @override
  List<MetricRecord> calculate(MetricsCalculationContext context) {
    final records = <MetricRecord>[];
    final defs = MetricsDefinitions.all;
    final guardian = context.guardianAnalysis;

    MetricRecord unavailable(String id) => MetricRecord(
          definition: defs[id]!,
          availability: MetricAvailability.unavailable,
          message: 'Guardian analysis was not provided',
        );

    if (guardian == null || guardian.isEmpty) {
      for (final id in metricIds) {
        if (!context.wants(id)) continue;
        records.add(unavailable(id));
      }
      return records;
    }

    final violations = guardian['violations'] as List<dynamic>? ?? [];
    final tests = guardian['tests'] as Map<String, dynamic>? ?? {};
    final risk = guardian['risk'] as Map<String, dynamic>? ?? {};

    if (context.wants('guardian.violation.count')) {
      records.add(MetricRecord(
        definition: defs['guardian.violation.count']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(violations.length),
      ));
    }

    if (context.wants('guardian.violation.count.by_severity')) {
      final bySeverity = <String, double>{};
      for (final item in violations) {
        if (item is! Map) continue;
        final severity = item['severity']?.toString() ?? 'unknown';
        bySeverity[severity] = (bySeverity[severity] ?? 0) + 1;
      }
      records.add(MetricRecord(
        definition: defs['guardian.violation.count.by_severity']!,
        availability: MetricAvailability.available,
        value: DistributionMetricValue(MetricDistribution(bySeverity)),
      ));
    }

    if (context.wants('guardian.required_test.count')) {
      final required = tests['required'] as List<dynamic>? ?? [];
      records.add(MetricRecord(
        definition: defs['guardian.required_test.count']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(required.length),
      ));
    }

    if (context.wants('guardian.decision')) {
      records.add(MetricRecord(
        definition: defs['guardian.decision']!,
        availability: MetricAvailability.available,
        value: TextMetricValue(guardian['decision']?.toString() ?? ''),
      ));
    }

    if (context.wants('guardian.risk.level')) {
      records.add(MetricRecord(
        definition: defs['guardian.risk.level']!,
        availability: MetricAvailability.available,
        value: TextMetricValue(risk['overall']?.toString() ?? ''),
      ));
    }

    return records;
  }
}
