import '../../models/cicd_integration/cicd_integration_operational_enums.dart';

import '../../models/cicd_integration/cicd_integration_snapshot.dart';

import '../../models/cicd_integration/pipeline_enums.dart';

import '../report_input.dart';

/// Converts [CicdIntegrationSnapshot] into report input data.

///

/// Consumes an existing snapshot only — never executes CI/CD integration engines.

class CicdIntegrationReportSource {
  const CicdIntegrationReportSource();

  CicdIntegrationReportInputData fromSnapshot(
      CicdIntegrationSnapshot snapshot) {
    final meta = snapshot.metadata;

    final sourceSummaries = snapshot.sourceReferences
        .map(
          (r) =>
              '${r.sourceType}:${r.resolvedId ?? r.requestedId}@${r.resolutionMode}',
        )
        .toList();

    final stageSummaries = snapshot.pipelineDefinition?.stages
            .map((s) => '${s.stageId}:${s.stageType.wireName}')
            .toList() ??
        const [];

    final targetSummaries = snapshot.deploymentPlan?.targets
            .map((t) => '${t.targetId}:${t.targetType.wireName}')
            .toList() ??
        const [];

    return CicdIntegrationReportInputData(
      snapshotId: meta.cicdIntegrationSnapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: meta.projectId,
      releaseId: meta.releaseId ?? '',
      pipelineDefinitionId: meta.pipelineDefinitionId ?? '',
      pipelineExecutionId: meta.pipelineExecutionId ?? '',
      deploymentPlanId: meta.deploymentPlanId ?? '',
      releaseEvidenceBundleId: meta.releaseEvidenceBundleId ?? '',
      releaseSupplyChainSnapshotId: meta.releaseSupplyChainSnapshotId ?? '',
      pipelineIntegrationPolicyId: meta.pipelineIntegrationPolicyId,
      pipelineIntegrationPolicyVersion: meta.pipelineIntegrationPolicyVersion,
      pipelineExecutionPolicyId: meta.pipelineExecutionPolicyId,
      pipelineExecutionPolicyVersion: meta.pipelineExecutionPolicyVersion,
      deploymentIntegrationPolicyId: meta.deploymentIntegrationPolicyId,
      deploymentIntegrationPolicyVersion:
          meta.deploymentIntegrationPolicyVersion,
      snapshotStatus: snapshot.status.wireName,
      pipelineStageCount: snapshot.pipelineDefinition?.stages.length ?? 0,
      pipelineExecutionStatus:
          snapshot.pipelineExecution?.status.wireName ?? 'unavailable',
      executionResultOutcome:
          snapshot.pipelineExecutionResult?.outcome.wireName ?? 'unavailable',
      deploymentPlanTargetCount: snapshot.deploymentPlan?.targets.length ?? 0,
      deploymentResultStatus:
          snapshot.deploymentResult?.status.wireName ?? 'unavailable',
      sourceReferenceCount: snapshot.sourceReferences.length,
      sourceSummaries: sourceSummaries,
      stageSummaries: stageSummaries,
      targetSummaries: targetSummaries,
      limitations: [
        ...meta.limitations,
        ...snapshot.limitations,
      ],
      warnings: snapshot.warnings,
    );
  }

  CicdIntegrationReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(CicdIntegrationSnapshot.fromJson(json));
  }
}
