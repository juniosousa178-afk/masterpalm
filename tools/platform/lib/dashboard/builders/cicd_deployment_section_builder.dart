import '../../models/cicd_integration/pipeline_enums.dart';

import '../../models/dashboard/dashboard_enums.dart';

import '../../models/dashboard/dashboard_snapshot.dart';

import 'dashboard_section_context.dart';

import 'dashboard_widget_helpers.dart';

/// Builds dashboard CI/CD deployment section from optional injected snapshot.

///

/// Consumes published snapshot only — never executes evaluate.

class CicdDeploymentSectionBuilder implements DashboardSectionBuilder {
  const CicdDeploymentSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.cicdDeployment;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.cicdIntegration ??
        context.request.cicdIntegrationSnapshot;

    final plan = snapshot?.deploymentPlan;

    if (snapshot == null || plan == null) {
      return buildSection(
        type: sectionType,
        title: 'CI/CD Deployment',
        order: 152,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cicdDeployment.status', 'CI/CD Deployment')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['CI/CD deployment snapshot unavailable'],
      );
    }

    final meta = snapshot.metadata;

    final result = snapshot.deploymentResult;

    return buildSection(
      type: sectionType,
      title: 'CI/CD Deployment',
      order: 152,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'cicdDeployment.plan-id',
          title: 'Plan',
          status: plan.planId,
        ),
        scalarWidget(
          widgetId: 'cicdDeployment.target-count',
          title: 'Targets',
          value: plan.targets.length.toDouble(),
          order: 1,
        ),
        statusWidget(
          widgetId: 'cicdDeployment.result-status',
          title: 'Result Status',
          status: result?.status.wireName ?? '-',
          order: 2,
        ),
        scalarWidget(
          widgetId: 'cicdDeployment.target-result-count',
          title: 'Target Results',
          value: (result?.targetResults.length ?? 0).toDouble(),
          order: 3,
        ),
        statusWidget(
          widgetId: 'cicdDeployment.policy',
          title: 'Deployment Policy',
          status:
              '${meta.deploymentIntegrationPolicyId}@${meta.deploymentIntegrationPolicyVersion}',
          order: 4,
        ),
        statusWidget(
          widgetId: 'cicdDeployment.execution-ref',
          title: 'Execution ref',
          status: meta.pipelineExecutionId ?? plan.pipelineExecutionId ?? '-',
          order: 5,
        ),
      ],
      limitations: [
        ...meta.limitations,
        ...snapshot.limitations,
      ],
    );
  }
}
