import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class OverviewSectionBuilder implements DashboardSectionBuilder {
  const OverviewSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.overview;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    if (!context.includeSection(sectionType)) {
      return buildSection(
          type: sectionType, title: 'Overview', order: 0, widgets: []);
    }

    final widgets = <DashboardWidget>[];
    var order = 0;
    final mes = context.sources.mes;
    final mesRef = context.refId(DashboardSourceType.mes);

    if (mes != null) {
      if (context.includeWidget('mes.overall')) {
        widgets.add(scalarWidget(
          widgetId: 'overview.mes.overall',
          title: 'MasterPalm Engineering Score',
          value: mes.mesValue.value,
          unit: mes.mesValue.unit,
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
      if (context.includeWidget('mes.status')) {
        widgets.add(statusWidget(
          widgetId: 'overview.mes.status',
          title: 'MES Status',
          status: mes.metadata.status.name,
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
      if (context.includeWidget('mes.band') && mes.band != null) {
        widgets.add(DashboardWidget(
          widgetId: 'overview.mes.band',
          type: DashboardWidgetType.band,
          title: 'MES Band',
          availability: DashboardAvailability.available,
          data: DashboardBandData(bandId: mes.band!.bandId),
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
      if (context.includeWidget('mes.eligibility')) {
        widgets.add(statusWidget(
          widgetId: 'overview.mes.eligibility',
          title: 'MES Eligibility',
          status: mes.eligibility.status.name,
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
      if (context.includeWidget('mes.confidence')) {
        widgets.add(statusWidget(
          widgetId: 'overview.mes.confidence',
          title: 'MES Confidence',
          status: mes.confidence.name,
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
      if (context.includeWidget('mes.coverage')) {
        widgets.add(percentageWidget(
          widgetId: 'overview.mes.coverage',
          title: 'MES Policy Coverage',
          value: mes.coverage.policyCoverage,
          sourceReferenceIds: mesRef != null ? [mesRef] : const [],
          order: order++,
        ));
      }
    } else if (context.request.includeUnavailable) {
      widgets.add(unavailableWidget(
          'overview.mes.overall', 'MasterPalm Engineering Score',
          order: order++));
    }

    final score = context.sources.score;
    final scoreRef = context.refId(DashboardSourceType.score);
    if (score != null && context.includeWidget('score.overall')) {
      widgets.add(scalarWidget(
        widgetId: 'overview.score.overall',
        title: 'Engineering Score',
        value: score.overallScore.value,
        sourceReferenceIds: scoreRef != null ? [scoreRef] : const [],
        order: order++,
      ));
    }

    final metrics = context.sources.metrics;
    final metricsRef = context.refId(DashboardSourceType.metrics);
    if (metrics != null && context.includeWidget('metrics.status')) {
      widgets.add(statusWidget(
        widgetId: 'overview.metrics.status',
        title: 'Metrics Status',
        status: 'available',
        sourceReferenceIds: metricsRef != null ? [metricsRef] : const [],
        order: order++,
      ));
    }

    final guardian = context.sources.guardianAnalysis;
    final guardianRef = context.refId(DashboardSourceType.guardian);
    if (guardian != null && context.includeWidget('guardian.decision')) {
      widgets.add(statusWidget(
        widgetId: 'overview.guardian.decision',
        title: 'Guardian Decision',
        status: (guardian['decision'] ?? 'unknown').toString(),
        sourceReferenceIds: guardianRef != null ? [guardianRef] : const [],
        order: order++,
      ));
    }

    final history = context.sources.history;
    if (history != null && context.includeWidget('history.latest')) {
      widgets.add(DashboardWidget(
        widgetId: 'overview.history.latest',
        type: DashboardWidgetType.textSummary,
        title: 'Latest History',
        availability: DashboardAvailability.available,
        data: DashboardTextData(text: history.metadata.createdAt),
        sourceReferenceIds: context.refId(DashboardSourceType.history) != null
            ? [context.refId(DashboardSourceType.history)!]
            : const [],
        order: order++,
      ));
    }

    if (context.includeWidget('dashboard.freshness')) {
      widgets.add(statusWidget(
        widgetId: 'overview.dashboard.freshness',
        title: 'Source Freshness',
        status: context.freshness.wireName,
        order: order++,
      ));
    }

    return buildSection(
      type: sectionType,
      title: 'Overview',
      order: 0,
      widgets: widgets,
      availability:
          widgets.any((w) => w.availability == DashboardAvailability.available)
              ? DashboardAvailability.available
              : DashboardAvailability.unavailable,
      sourceReferenceIds:
          context.sources.references.map((r) => r.referenceId).toList(),
    );
  }
}
