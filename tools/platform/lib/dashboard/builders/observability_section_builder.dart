import '../../models/observability/telemetry_enums.dart';
import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard observability section from optional telemetry source.
class ObservabilitySectionBuilder implements DashboardSectionBuilder {
  const ObservabilitySectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.observability;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final telemetry = context.sources.telemetry;
    if (telemetry == null) {
      return buildSection(
        type: sectionType,
        title: 'Observability',
        order: 110,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('observability.status', 'Observability')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Telemetry snapshot unavailable'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Observability',
      order: 110,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'observability.operations',
          title: 'Operations',
          value: telemetry.summary.operationCount.toDouble(),
        ),
        scalarWidget(
          widgetId: 'observability.successes',
          title: 'Successes',
          value: telemetry.summary.successCount.toDouble(),
          order: 1,
        ),
        scalarWidget(
          widgetId: 'observability.failures',
          title: 'Failures',
          value: telemetry.summary.failureCount.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'observability.incomplete',
          title: 'Incomplete',
          value: telemetry.coverage.incompleteOperationCount.toDouble(),
          order: 3,
        ),
        scalarWidget(
          widgetId: 'observability.avg-duration',
          title: 'Avg duration (µs)',
          value: telemetry.durationSummary.averageMicroseconds.toDouble(),
          order: 4,
        ),
        percentageWidget(
          widgetId: 'observability.coverage',
          title: 'Event coverage',
          value: telemetry.coverage.eventCoveragePercentage,
          order: 5,
        ),
        statusWidget(
          widgetId: 'observability.compatibility',
          title: 'Compatibility',
          status: telemetry.compatibility.wireName,
          order: 6,
        ),
      ],
    );
  }
}
