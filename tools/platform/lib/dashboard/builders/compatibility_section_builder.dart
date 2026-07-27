import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class CompatibilitySectionBuilder implements DashboardSectionBuilder {
  const CompatibilitySectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.compatibility;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    return buildSection(
      type: sectionType,
      title: 'Compatibility',
      order: 80,
      widgets: [
        statusWidget(
          widgetId: 'compatibility.status',
          title: 'Compatibility Status',
          status: context.compatibility.wireName,
        ),
      ],
      sourceReferenceIds:
          context.sources.references.map((r) => r.referenceId).toList(),
    );
  }
}

class SourcesSectionBuilder implements DashboardSectionBuilder {
  const SourcesSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.sources;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final refs = context.sources.references;
    if (refs.isEmpty) {
      return buildSection(
        type: sectionType,
        title: 'Sources',
        order: 90,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('sources.list', 'Sources')]
            : [],
        limitations: const ['No sources resolved'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Sources',
      order: 90,
      widgets: [
        DashboardWidget(
          widgetId: 'sources.list',
          type: DashboardWidgetType.sourceList,
          title: 'Source References',
          availability: DashboardAvailability.available,
          data: DashboardSourceListData(
            sourceIds: refs.map((r) => r.referenceId).toList(),
          ),
          sourceReferenceIds: refs.map((r) => r.referenceId).toList(),
        ),
      ],
      sourceReferenceIds: refs.map((r) => r.referenceId).toList(),
    );
  }
}

class LimitationsSectionBuilder implements DashboardSectionBuilder {
  const LimitationsSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.limitations;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final limitations = [
      ...context.sources.limitations,
      ...context.sources.references.expand((r) => r.limitations).toList(),
    ];
    if (limitations.isEmpty && !context.request.includeLimitations) {
      return buildSection(
          type: sectionType, title: 'Limitations', order: 100, widgets: []);
    }

    return buildSection(
      type: sectionType,
      title: 'Limitations',
      order: 100,
      widgets: limitations.isEmpty
          ? []
          : [
              DashboardWidget(
                widgetId: 'limitations.list',
                type: DashboardWidgetType.limitationList,
                title: 'Limitations',
                availability: DashboardAvailability.available,
                data: DashboardLimitationListData(limitations: limitations),
              ),
            ],
      limitations: limitations,
    );
  }
}
