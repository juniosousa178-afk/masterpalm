import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/quality_gate/quality_gate_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard quality gate section from optional injected snapshot.
class QualityGateSectionBuilder implements DashboardSectionBuilder {
  const QualityGateSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.qualityGate;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final gate =
        context.sources.qualityGate ?? context.request.qualityGateSnapshot;
    if (gate == null) {
      return buildSection(
        type: sectionType,
        title: 'Quality Gate',
        order: 120,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('qualityGate.status', 'Quality Gate')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Quality Gate snapshot unavailable'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Quality Gate',
      order: 120,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'qualityGate.decision',
          title: 'Decision',
          status: gate.decision.wireName,
        ),
        scalarWidget(
          widgetId: 'qualityGate.policy-version',
          title: 'Policy version',
          value: gate.metadata.policyVersion.toDouble(),
          order: 1,
        ),
        scalarWidget(
          widgetId: 'qualityGate.evaluated-rules',
          title: 'Evaluated rules',
          value: gate.metadata.evaluatedRuleCount.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'qualityGate.failed-rules',
          title: 'Failed rules',
          value: gate.metadata.failedRuleCount.toDouble(),
          order: 3,
        ),
        scalarWidget(
          widgetId: 'qualityGate.blocking-failures',
          title: 'Blocking failures',
          value: gate.metadata.blockingFailureCount.toDouble(),
          order: 4,
        ),
        percentageWidget(
          widgetId: 'qualityGate.coverage',
          title: 'Required coverage',
          value: gate.coverage.requiredRuleCoveragePercentage,
          order: 5,
        ),
        statusWidget(
          widgetId: 'qualityGate.eligibility',
          title: 'Eligibility',
          status: gate.eligibility.status.wireName,
          order: 6,
        ),
        statusWidget(
          widgetId: 'qualityGate.compatibility',
          title: 'Compatibility',
          status: gate.compatibility.status.wireName,
          order: 7,
        ),
      ],
      limitations: gate.limitations.map((l) => l.description).toList(),
    );
  }
}
