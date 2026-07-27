import '../models/metrics/metric_category.dart';
import '../models/metrics/metric_definition.dart';
import 'calculators/ast_import_metrics_calculator.dart';
import 'calculators/graph_metrics_calculator.dart';
import 'calculators/guardian_import_metrics_calculator.dart';
import 'metric_calculator.dart';
import 'metrics_definitions.dart';
import 'metrics_exceptions.dart';

/// Registry of metric definitions and calculators.
class MetricsRegistry {
  MetricsRegistry({List<MetricCalculator>? calculators})
      : _calculators = calculators ?? defaultCalculators {
    for (final calculator in _calculators) {
      for (final id in calculator.metricIds) {
        if (_calculatorByMetric.containsKey(id)) {
          throw MetricsException(
            'Duplicate metric id registration: $id',
            code: 'duplicate_metric_id',
          );
        }
        _calculatorByMetric[id] = calculator;
      }
    }
  }

  static final defaultCalculators = <MetricCalculator>[
    const GraphMetricsCalculator(),
    const GuardianImportMetricsCalculator(),
    const AstImportMetricsCalculator(),
  ];

  final List<MetricCalculator> _calculators;
  final Map<String, MetricCalculator> _calculatorByMetric = {};

  Set<String> get supportedMetricIds => MetricsDefinitions.all.keys.toSet();

  MetricDefinition? definitionFor(String metricId) =>
      MetricsDefinitions.all[metricId];

  List<MetricCalculator> get calculators => List.unmodifiable(_calculators);

  Set<String> resolveRequestedMetricIds({
    Set<String>? metricIds,
    Set<MetricCategory>? categories,
  }) {
    if (metricIds != null && metricIds.isNotEmpty) {
      for (final id in metricIds) {
        if (!supportedMetricIds.contains(id)) {
          throw MetricsUnknownMetricException(id);
        }
      }
      return Set<String>.from(metricIds);
    }

    if (categories != null && categories.isNotEmpty) {
      return MetricsDefinitions.all.values
          .where((d) => categories.contains(d.category))
          .map((d) => d.id)
          .toSet();
    }

    return Set<String>.from(MetricsDefinitions.defaultMetricIds);
  }

  List<MetricCalculator> calculatorsFor(Set<String> requestedIds) {
    final selected = <MetricCalculator>{};
    for (final id in requestedIds) {
      final calculator = _calculatorByMetric[id];
      if (calculator != null) selected.add(calculator);
    }
    final ordered = selected.toList()
      ..sort((a, b) => a.metricIds.first.compareTo(b.metricIds.first));
    return ordered;
  }
}
