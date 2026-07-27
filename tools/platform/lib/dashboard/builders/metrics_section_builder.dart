import '../../models/dashboard/dashboard_enums.dart';
import '../../models/metrics/metric_availability.dart';
import '../../models/metrics/metric_value.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class MetricsSectionBuilder implements DashboardSectionBuilder {
  const MetricsSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.metrics;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final metrics = context.sources.metrics;
    final ref = context.refId(DashboardSourceType.metrics);
    if (metrics == null) {
      return buildSection(
        type: sectionType,
        title: 'Metrics',
        order: 30,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('metrics.count', 'Metric Count')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Metrics snapshot unavailable'],
      );
    }

    final available = metrics.metrics
        .where((m) => m.availability == MetricAvailability.available)
        .length;
    final unavailable = metrics.metrics.length - available;

    final widgets = <DashboardWidget>[
      scalarWidget(
        widgetId: 'metrics.count',
        title: 'Metric Count',
        value: metrics.metrics.length.toDouble(),
        sourceReferenceIds: ref != null ? [ref] : const [],
      ),
      scalarWidget(
        widgetId: 'metrics.available',
        title: 'Available Metrics',
        value: available.toDouble(),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 1,
      ),
      scalarWidget(
        widgetId: 'metrics.unavailable',
        title: 'Unavailable Metrics',
        value: unavailable.toDouble(),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 2,
      ),
      DashboardWidget(
        widgetId: 'metrics.table',
        type: DashboardWidgetType.table,
        title: 'Metrics',
        availability: DashboardAvailability.available,
        data: DashboardTableData(
          headers: const ['metricId', 'value', 'unit'],
          rows: metrics.metrics
              .map(
                (m) => [
                  m.definition.id,
                  _metricValueText(m.value),
                  m.definition.unit.name,
                ],
              )
              .toList(),
        ),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 3,
      ),
    ];

    return buildSection(
      type: sectionType,
      title: 'Metrics',
      order: 30,
      widgets: widgets,
      sourceReferenceIds: ref != null ? [ref] : const [],
    );
  }

  String _metricValueText(MetricValue? value) {
    if (value == null) return 'n/a';
    return switch (value) {
      IntegerMetricValue(:final value) => value.toString(),
      DecimalMetricValue(:final value) => value.toString(),
      PercentageMetricValue(:final value) => value.toString(),
      BooleanMetricValue(:final value) => value.toString(),
      TextMetricValue(:final value) => value,
      DistributionMetricValue() => 'distribution',
      IntegerSeriesMetricValue() => 'series',
      DecimalSeriesMetricValue() => 'series',
    };
  }
}
