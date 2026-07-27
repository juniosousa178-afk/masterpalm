import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class ScoreSectionBuilder implements DashboardSectionBuilder {
  const ScoreSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.score;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final score = context.sources.score;
    final ref = context.refId(DashboardSourceType.score);
    if (score == null) {
      return buildSection(
        type: sectionType,
        title: 'Score',
        order: 20,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('score.overall', 'Engineering Score')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Score snapshot unavailable'],
      );
    }

    final widgets = <DashboardWidget>[
      scalarWidget(
        widgetId: 'score.overall',
        title: 'Overall Score',
        value: score.overallScore.value,
        sourceReferenceIds: ref != null ? [ref] : const [],
      ),
      statusWidget(
        widgetId: 'score.policy',
        title: 'Policy',
        status: score.metadata.policyId,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 1,
      ),
      statusWidget(
        widgetId: 'score.status',
        title: 'Status',
        status: score.metadata.status.name,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 2,
      ),
      percentageWidget(
        widgetId: 'score.coverage',
        title: 'Coverage',
        value: score.coverage.coveragePercentage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 3,
      ),
      statusWidget(
        widgetId: 'score.confidence',
        title: 'Confidence',
        status: score.metadata.confidence.name,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 4,
      ),
      DashboardWidget(
        widgetId: 'score.dimensions',
        type: DashboardWidgetType.keyValueList,
        title: 'Dimensions',
        availability: DashboardAvailability.available,
        data: DashboardListData(
          items: score.dimensions
              .map(
                (d) =>
                    '${d.dimensionId}: ${d.normalizedScore?.toStringAsFixed(2) ?? 'n/a'}',
              )
              .toList(),
        ),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 5,
      ),
    ];

    return buildSection(
      type: sectionType,
      title: 'Score',
      order: 20,
      widgets: widgets,
      sourceReferenceIds: ref != null ? [ref] : const [],
      warnings: score.warnings.map((w) => w.message).toList(),
    );
  }
}
