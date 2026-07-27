import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import 'builders/dashboard_section_context.dart';
import 'dashboard_registry.dart';
import 'dashboard_source_resolver.dart';

/// Composes dashboard sections from resolved sources.
class DashboardComposer {
  const DashboardComposer({required DashboardRegistry registry})
      : _registry = registry;

  final DashboardRegistry _registry;

  List<DashboardSection> compose({
    required DashboardRequest request,
    required DashboardResolvedSources sources,
    required DashboardCompatibility compatibility,
    required DashboardFreshness freshness,
  }) {
    final context = DashboardSectionBuildContext(
      request: request,
      sources: sources,
      compatibility: compatibility,
      freshness: freshness,
    );

    final sections = <DashboardSection>[];
    for (final builder in _registry.builders) {
      if (!context.includeSection(builder.sectionType)) continue;
      final section = builder.build(context);
      if (!request.includeUnavailable &&
          section.availability == DashboardAvailability.unavailable) {
        continue;
      }
      sections.add(section);
    }

    sections.sort((a, b) => a.order.compareTo(b.order));
    return sections;
  }
}
