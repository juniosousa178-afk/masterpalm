import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class CoverageSectionBuilder implements DashboardSectionBuilder {
  const CoverageSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.coverage;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final widgets = <DashboardWidget>[];
    final refs = <String>[];
    var order = 0;

    final score = context.sources.score;
    if (score != null) {
      final ref = context.refId(DashboardSourceType.score);
      if (ref != null) refs.add(ref);
      widgets.add(percentageWidget(
        widgetId: 'coverage.score',
        title: 'Score Coverage',
        value: score.coverage.coveragePercentage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: order++,
      ));
    }

    final mes = context.sources.mes;
    if (mes != null) {
      final ref = context.refId(DashboardSourceType.mes);
      if (ref != null) refs.add(ref);
      widgets.add(percentageWidget(
        widgetId: 'coverage.mes.rule',
        title: 'MES Rule Coverage',
        value: mes.coverage.ruleCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: order++,
      ));
      widgets.add(percentageWidget(
        widgetId: 'coverage.mes.dimension',
        title: 'MES Dimension Coverage',
        value: mes.coverage.dimensionCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: order++,
      ));
      widgets.add(percentageWidget(
        widgetId: 'coverage.mes.policy',
        title: 'MES Policy Coverage',
        value: mes.coverage.policyCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: order++,
      ));
      widgets.add(percentageWidget(
        widgetId: 'coverage.mes.evidence',
        title: 'MES Evidence Coverage',
        value: mes.coverage.evidenceCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: order++,
      ));
      if (mes.coverage.missingRequiredMetricIds.isNotEmpty) {
        widgets.add(DashboardWidget(
          widgetId: 'coverage.mes.missingEvidence',
          type: DashboardWidgetType.limitationList,
          title: 'Missing Required Evidence',
          availability: DashboardAvailability.available,
          data: DashboardLimitationListData(
            limitations: mes.coverage.missingRequiredMetricIds,
          ),
          sourceReferenceIds: ref != null ? [ref] : const [],
          order: order++,
        ));
      }
    }

    if (widgets.isEmpty) {
      return buildSection(
        type: sectionType,
        title: 'Coverage',
        order: 70,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('coverage.summary', 'Coverage')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Coverage data unavailable'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Coverage',
      order: 70,
      widgets: widgets,
      sourceReferenceIds: refs,
    );
  }
}
