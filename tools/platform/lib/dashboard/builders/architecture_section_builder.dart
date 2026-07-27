import '../../models/metrics/metric_value.dart';
import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class ArchitectureSectionBuilder implements DashboardSectionBuilder {
  const ArchitectureSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.architecture;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final metrics = context.sources.metrics;
    final graph = context.sources.graph;
    final widgets = <DashboardWidget>[];
    final refs = <String>[];

    if (metrics != null) {
      final metricsRef = context.refId(DashboardSourceType.metrics);
      if (metricsRef != null) refs.add(metricsRef);
      for (final record in metrics.metrics) {
        final id = record.definition.id;
        if (id.startsWith('graph.')) {
          final numeric = _metricNumeric(record.value);
          if (numeric == null) continue;
          widgets.add(scalarWidget(
            widgetId: 'architecture.$id',
            title: id,
            value: numeric,
            sourceReferenceIds: metricsRef != null ? [metricsRef] : const [],
            order: widgets.length,
          ));
        }
      }
    }

    if (graph != null && widgets.isEmpty) {
      final graphRef = context.refId(DashboardSourceType.graph);
      if (graphRef != null) refs.add(graphRef);
      widgets.addAll([
        scalarWidget(
          widgetId: 'architecture.nodeCount',
          title: 'Node Count',
          value: graph.nodes.length.toDouble(),
          sourceReferenceIds: graphRef != null ? [graphRef] : const [],
        ),
        scalarWidget(
          widgetId: 'architecture.edgeCount',
          title: 'Edge Count',
          value: graph.edges.length.toDouble(),
          sourceReferenceIds: graphRef != null ? [graphRef] : const [],
          order: 1,
        ),
      ]);
    }

    if (widgets.isEmpty) {
      return buildSection(
        type: sectionType,
        title: 'Architecture',
        order: 60,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('architecture.summary', 'Architecture')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Architecture data unavailable'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Architecture',
      order: 60,
      widgets: widgets,
      sourceReferenceIds: refs,
    );
  }

  double? _metricNumeric(MetricValue? value) {
    if (value == null) return null;
    return switch (value) {
      IntegerMetricValue(:final value) => value.toDouble(),
      DecimalMetricValue(:final value) => value,
      PercentageMetricValue(:final value) => value,
      _ => null,
    };
  }
}
