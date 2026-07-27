import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class HistorySectionBuilder implements DashboardSectionBuilder {
  const HistorySectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.history;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final history = context.sources.history;
    final diff = context.sources.historyDiff;
    final ref = context.refId(DashboardSourceType.history);

    if (history == null && diff == null) {
      return buildSection(
        type: sectionType,
        title: 'History',
        order: 40,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('history.current', 'Current Snapshot')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['History unavailable'],
      );
    }

    final widgets = <DashboardWidget>[];
    if (history != null) {
      widgets.add(DashboardWidget(
        widgetId: 'history.current',
        type: DashboardWidgetType.textSummary,
        title: 'Current Snapshot',
        availability: DashboardAvailability.available,
        data: DashboardTextData(text: history.metadata.historySnapshotId),
        sourceReferenceIds: ref != null ? [ref] : const [],
      ));
      widgets.add(scalarWidget(
        widgetId: 'history.artifactCount',
        title: 'Artifact Count',
        value: history.metadata.artifactCount.toDouble(),
        sourceReferenceIds: ref != null ? [ref] : const [],
        order: 1,
      ));
    }

    if (diff != null) {
      widgets.add(scalarWidget(
        widgetId: 'history.diff.total',
        title: 'Total Changes',
        value: diff.summary.totalChanges.toDouble(),
        order: 2,
      ));
      widgets.add(scalarWidget(
        widgetId: 'history.diff.added',
        title: 'Added',
        value: diff.summary.addedCount.toDouble(),
        order: 3,
      ));
      widgets.add(scalarWidget(
        widgetId: 'history.diff.removed',
        title: 'Removed',
        value: diff.summary.removedCount.toDouble(),
        order: 4,
      ));
      widgets.add(scalarWidget(
        widgetId: 'history.diff.changed',
        title: 'Changed',
        value: diff.summary.changedCount.toDouble(),
        order: 5,
      ));
    }

    return buildSection(
      type: sectionType,
      title: 'History',
      order: 40,
      widgets: widgets,
      sourceReferenceIds: ref != null ? [ref] : const [],
    );
  }
}
