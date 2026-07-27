import '../models/metrics/metric_record.dart';
import '../models/metrics/metric_source.dart';
import 'metrics_graph_context.dart';

/// Context passed to metric calculators.
class MetricsCalculationContext {
  const MetricsCalculationContext({
    required this.graphContext,
    this.guardianAnalysis,
    this.astReport,
    required this.depthLimit,
    required this.requestedMetricIds,
  });

  final MetricsGraphContext graphContext;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? astReport;
  final int depthLimit;
  final Set<String> requestedMetricIds;

  bool wants(String metricId) => requestedMetricIds.contains(metricId);
}

/// Pure calculator for a set of related metrics.
abstract class MetricCalculator {
  Set<String> get metricIds;
  Set<MetricSource> get requiredSources;

  List<MetricRecord> calculate(MetricsCalculationContext context);
}
