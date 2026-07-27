import '../../models/cicd_integration/cicd_integration_operational_enums.dart';

import '../../models/dashboard/dashboard_enums.dart';

import '../../models/dashboard/dashboard_snapshot.dart';

import 'dashboard_section_context.dart';

import 'dashboard_widget_helpers.dart';

/// Builds dashboard CI/CD pipeline section from optional injected snapshot.

///

/// Consumes published snapshot only — never executes evaluate.

class CicdPipelineSectionBuilder implements DashboardSectionBuilder {
  const CicdPipelineSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.cicdPipeline;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.cicdIntegration ??
        context.request.cicdIntegrationSnapshot;

    final definition = snapshot?.pipelineDefinition;

    if (snapshot == null || definition == null) {
      return buildSection(
        type: sectionType,
        title: 'CI/CD Pipeline',
        order: 150,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cicdPipeline.status', 'CI/CD Pipeline')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['CI/CD pipeline snapshot unavailable'],
      );
    }

    final meta = snapshot.metadata;

    return buildSection(
      type: sectionType,
      title: 'CI/CD Pipeline',
      order: 150,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'cicdPipeline.status',
          title: 'Snapshot Status',
          status: snapshot.status.wireName,
        ),
        statusWidget(
          widgetId: 'cicdPipeline.definition',
          title: 'Definition',
          status: definition.definitionId,
          order: 1,
        ),
        scalarWidget(
          widgetId: 'cicdPipeline.stage-count',
          title: 'Stages',
          value: definition.stages.length.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'cicdPipeline.job-count',
          title: 'Jobs',
          value: definition.stages
              .fold<int>(0, (sum, stage) => sum + stage.steps.length)
              .toDouble(),
          order: 3,
        ),
        statusWidget(
          widgetId: 'cicdPipeline.policy',
          title: 'Integration Policy',
          status:
              '${meta.pipelineIntegrationPolicyId}@${meta.pipelineIntegrationPolicyVersion}',
          order: 4,
        ),
        statusWidget(
          widgetId: 'cicdPipeline.release',
          title: 'Release',
          status: meta.releaseId ?? '-',
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
