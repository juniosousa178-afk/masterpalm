import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard compliance section from optional injected snapshot.
///
/// Consumes published snapshot only — never executes evaluate.
class ComplianceSectionBuilder implements DashboardSectionBuilder {
  const ComplianceSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.compliance;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.releaseSupplyChain ??
        context.request.releaseSupplyChainSnapshot;
    final compliance = snapshot?.compliance;
    if (snapshot == null || compliance == null) {
      return buildSection(
        type: sectionType,
        title: 'Compliance',
        order: 160,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('compliance.status', 'Compliance')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Compliance result unavailable in snapshot'],
      );
    }

    final meta = snapshot.metadata;
    return buildSection(
      type: sectionType,
      title: 'Compliance',
      order: 160,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'compliance.status',
          title: 'Status',
          status: compliance.status.wireName,
        ),
        scalarWidget(
          widgetId: 'compliance.check-count',
          title: 'Checks',
          value: compliance.checks.length.toDouble(),
          order: 1,
        ),
        scalarWidget(
          widgetId: 'compliance.violation-count',
          title: 'Violations',
          value: compliance.violations.length.toDouble(),
          order: 2,
        ),
        statusWidget(
          widgetId: 'compliance.policy',
          title: 'Policy',
          status: '${meta.compliancePolicyId}@${meta.compliancePolicyVersion}',
          order: 3,
        ),
        statusWidget(
          widgetId: 'compliance.result-id',
          title: 'Result ID',
          status: compliance.resultId,
          order: 4,
        ),
      ],
      limitations: [
        ...meta.limitations,
        ...compliance.limitations,
        ...snapshot.limitations,
      ],
    );
  }
}
