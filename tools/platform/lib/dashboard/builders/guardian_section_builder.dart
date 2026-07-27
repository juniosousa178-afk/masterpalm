import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

class GuardianSectionBuilder implements DashboardSectionBuilder {
  const GuardianSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.guardian;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final guardian = context.sources.guardianAnalysis;
    final ref = context.refId(DashboardSourceType.guardian);

    if (guardian == null) {
      final metrics = context.sources.metrics;
      if (metrics != null) {
        final decisionMetric = metrics.metrics
            .where((m) => m.definition.id.contains('guardian'))
            .toList();
        if (decisionMetric.isNotEmpty) {
          return buildSection(
            type: sectionType,
            title: 'Guardian',
            order: 50,
            widgets: [
              statusWidget(
                widgetId: 'guardian.metrics',
                title: 'Guardian Metrics Available',
                status: 'metrics-only',
                sourceReferenceIds:
                    context.refId(DashboardSourceType.metrics) != null
                        ? [context.refId(DashboardSourceType.metrics)!]
                        : const [],
              ),
            ],
            description:
                'Guardian metrics from MetricsSnapshot (no decision derived)',
          );
        }
      }
      return buildSection(
        type: sectionType,
        title: 'Guardian',
        order: 50,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('guardian.decision', 'Guardian Decision')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Guardian result unavailable'],
      );
    }

    final violations = (guardian['violations'] as List<dynamic>? ?? []).length;
    final risk =
        (guardian['risk'] as Map<String, dynamic>?)?['overall']?.toString() ??
            'unknown';

    return buildSection(
      type: sectionType,
      title: 'Guardian',
      order: 50,
      widgets: [
        statusWidget(
          widgetId: 'guardian.decision',
          title: 'Decision',
          status: (guardian['decision'] ?? 'unknown').toString(),
          sourceReferenceIds: ref != null ? [ref] : const [],
        ),
        statusWidget(
          widgetId: 'guardian.risk',
          title: 'Risk Level',
          status: risk,
          sourceReferenceIds: ref != null ? [ref] : const [],
          order: 1,
        ),
        scalarWidget(
          widgetId: 'guardian.violations',
          title: 'Violation Count',
          value: violations.toDouble(),
          sourceReferenceIds: ref != null ? [ref] : const [],
          order: 2,
        ),
      ],
      sourceReferenceIds: ref != null ? [ref] : const [],
    );
  }
}
