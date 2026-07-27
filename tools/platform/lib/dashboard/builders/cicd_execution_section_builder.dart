import '../../models/cicd_integration/pipeline_enums.dart';

import '../../models/dashboard/dashboard_enums.dart';

import '../../models/dashboard/dashboard_snapshot.dart';

import 'dashboard_section_context.dart';

import 'dashboard_widget_helpers.dart';

/// Builds dashboard CI/CD execution section from optional injected snapshot.

///

/// Consumes published snapshot only — never executes evaluate.

class CicdExecutionSectionBuilder implements DashboardSectionBuilder {
  const CicdExecutionSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.cicdExecution;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.cicdIntegration ??
        context.request.cicdIntegrationSnapshot;

    final execution = snapshot?.pipelineExecution;

    if (snapshot == null || execution == null) {
      return buildSection(
        type: sectionType,
        title: 'CI/CD Execution',
        order: 151,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cicdExecution.status', 'CI/CD Execution')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['CI/CD execution snapshot unavailable'],
      );
    }

    final meta = snapshot.metadata;

    final result = snapshot.pipelineExecutionResult;

    return buildSection(
      type: sectionType,
      title: 'CI/CD Execution',
      order: 151,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'cicdExecution.status',
          title: 'Execution Status',
          status: execution.status.wireName,
        ),
        statusWidget(
          widgetId: 'cicdExecution.execution-id',
          title: 'Execution',
          status: execution.executionId,
          order: 1,
        ),
        statusWidget(
          widgetId: 'cicdExecution.definition',
          title: 'Definition ref',
          status: execution.definitionId,
          order: 2,
        ),
        statusWidget(
          widgetId: 'cicdExecution.result-outcome',
          title: 'Result Outcome',
          status: result?.outcome.wireName ?? '-',
          order: 3,
        ),
        scalarWidget(
          widgetId: 'cicdExecution.artifact-count',
          title: 'Artifacts',
          value: execution.artifacts.length.toDouble(),
          order: 4,
        ),
        statusWidget(
          widgetId: 'cicdExecution.policy',
          title: 'Execution Policy',
          status:
              '${meta.pipelineExecutionPolicyId}@${meta.pipelineExecutionPolicyVersion}',
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
