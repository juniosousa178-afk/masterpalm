import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_request.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../dashboard_source_resolver.dart';

/// Context passed to section builders during composition.
class DashboardSectionBuildContext {
  const DashboardSectionBuildContext({
    required this.request,
    required this.sources,
    required this.compatibility,
    required this.freshness,
  });

  final DashboardRequest request;
  final DashboardResolvedSources sources;
  final DashboardCompatibility compatibility;
  final DashboardFreshness freshness;

  bool includeSection(DashboardSectionType type) {
    final requested = request.requestedSections;
    if (requested == null || requested.isEmpty) return true;
    return requested.contains(type);
  }

  bool includeWidget(String widgetId) {
    final requested = request.requestedWidgetIds;
    if (requested == null || requested.isEmpty) return true;
    return requested.contains(widgetId);
  }

  String? refId(DashboardSourceType type) {
    final match = sources.references
        .where(
          (r) =>
              r.sourceType == type &&
              r.availability == DashboardAvailability.available,
        )
        .toList();
    if (match.isEmpty) return null;
    return match.first.referenceId;
  }
}

/// Contract for dashboard section builders.
abstract interface class DashboardSectionBuilder {
  DashboardSectionType get sectionType;

  DashboardSection build(DashboardSectionBuildContext context);
}
