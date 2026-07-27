import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/release_governance/release_governance_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard release governance section from optional injected snapshot.
///
/// Consumes published snapshot only — never executes evaluate.
class ReleaseGovernanceSectionBuilder implements DashboardSectionBuilder {
  const ReleaseGovernanceSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.releaseGovernance;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.releaseGovernance ??
        context.request.releaseDecisionSnapshot;
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Release Governance',
        order: 125,
        widgets: context.request.includeUnavailable
            ? [
                unavailableWidget(
                    'releaseGovernance.status', 'Release Governance')
              ]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Release Governance snapshot unavailable'],
      );
    }

    final pendingApprovals = snapshot.approvalEvaluations
        .where(
          (a) =>
              a.status == ReleaseApprovalEvaluationStatus.missing ||
              a.status == ReleaseApprovalEvaluationStatus.partiallySatisfied ||
              a.status == ReleaseApprovalEvaluationStatus.expired,
        )
        .length;
    final activeWaivers = snapshot.waiverEvaluations
        .where(
          (w) =>
              w.status == ReleaseWaiverStatus.active ||
              w.status == ReleaseWaiverStatus.approved,
        )
        .length;
    final openConditions = snapshot.conditions
        .where((c) => c.status == ReleaseConditionStatus.open)
        .length;

    return buildSection(
      type: sectionType,
      title: 'Release Governance',
      order: 125,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'releaseGovernance.decision',
          title: 'Decision',
          status: snapshot.decision.wireName,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.release',
          title: 'Release',
          status:
              '${snapshot.metadata.releaseId}@${snapshot.metadata.releaseVersion}',
          order: 1,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.environment',
          title: 'Environment',
          status: snapshot.metadata.environment.wireName,
          order: 2,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.releaseType',
          title: 'Release type',
          status: snapshot.metadata.releaseType.wireName,
          order: 3,
        ),
        scalarWidget(
          widgetId: 'releaseGovernance.policy-version',
          title: 'Policy version',
          value: snapshot.metadata.policyVersion.toDouble(),
          order: 4,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.qualityGate',
          title: 'Quality Gate ref',
          status: snapshot.metadata.qualityGateSnapshotId,
          order: 5,
        ),
        scalarWidget(
          widgetId: 'releaseGovernance.pending-approvals',
          title: 'Pending approvals',
          value: pendingApprovals.toDouble(),
          order: 6,
        ),
        scalarWidget(
          widgetId: 'releaseGovernance.active-waivers',
          title: 'Active waivers',
          value: activeWaivers.toDouble(),
          order: 7,
        ),
        scalarWidget(
          widgetId: 'releaseGovernance.open-conditions',
          title: 'Open conditions',
          value: openConditions.toDouble(),
          order: 8,
        ),
        percentageWidget(
          widgetId: 'releaseGovernance.coverage',
          title: 'Required coverage',
          value: snapshot.coverage.requiredRuleCoveragePercentage,
          order: 9,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.compatibility',
          title: 'Compatibility',
          status: snapshot.compatibility.status.wireName,
          order: 10,
        ),
        statusWidget(
          widgetId: 'releaseGovernance.eligibility',
          title: 'Eligibility',
          status: snapshot.eligibility.status.wireName,
          order: 11,
        ),
      ],
      limitations: snapshot.limitations.map((l) => l.description).toList(),
    );
  }
}
