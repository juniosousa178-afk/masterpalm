import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class PersistentArtifactsSummarySectionBuilder
    implements DashboardSectionBuilder {
  const PersistentArtifactsSummarySectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.persistentArtifactsSummary;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    return buildSection(
      type: sectionType,
      title: 'Persistent Artifacts',
      order: 167,
      availability: DashboardAvailability.unavailable,
      widgets: context.request.includeUnavailable
          ? [
              unavailableWidget(
                'persistentArtifacts.summary',
                'Persistent Artifacts',
              ),
            ]
          : const [],
      limitations: const [
        'declarative-boundaries-only',
        'requires explicit persistent artifact dashboard source',
      ],
    );
  }
}
