import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class MesSectionBuilder implements DashboardSectionBuilder {
  const MesSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.mes;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final mes = context.sources.mes;
    final ref = context.refId(DashboardSourceType.mes);
    if (mes == null) {
      return buildSection(
        type: sectionType,
        title: 'MES',
        order: 10,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('mes.overall', 'MES')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['MES snapshot unavailable'],
      );
    }

    final widgets = <DashboardWidget>[
      scalarWidget(
        widgetId: 'mes.overall',
        title: 'MES Value',
        value: mes.mesValue.value,
        unit: mes.mesValue.unit,
        sourceReferenceIds: ref != null ? [ref] : const [],
      ),
      statusWidget(
        widgetId: 'mes.status',
        title: 'MES Status',
        status: mes.metadata.status.name,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 1,
      ),
      percentageWidget(
        widgetId: 'mes.policyCoverage',
        title: 'Policy Coverage',
        value: mes.coverage.policyCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 2,
      ),
      percentageWidget(
        widgetId: 'mes.evidenceCoverage',
        title: 'Evidence Coverage',
        value: mes.coverage.evidenceCoverage,
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 3,
      ),
      DashboardWidget(
        widgetId: 'mes.dimensions',
        type: DashboardWidgetType.keyValueList,
        title: 'MES Dimensions',
        availability: DashboardAvailability.available,
        data: DashboardListData(
          items: mes.dimensions
              .map(
                (d) =>
                    '${d.dimensionId}: ${d.normalizedScore?.toStringAsFixed(2) ?? 'n/a'}',
              )
              .toList(),
        ),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 4,
      ),
    ];

    if (mes.limitations.isNotEmpty) {
      widgets.add(DashboardWidget(
        widgetId: 'mes.limitations',
        type: DashboardWidgetType.limitationList,
        title: 'MES Limitations',
        availability: DashboardAvailability.available,
        data: DashboardLimitationListData(
          limitations: mes.limitations.map((l) => l.message).toList(),
        ),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 5,
      ));
    }

    return buildSection(
      type: sectionType,
      title: 'MES',
      order: 10,
      widgets: widgets,
      sourceReferenceIds: ref != null ? [ref] : const [],
    );
  }
}
