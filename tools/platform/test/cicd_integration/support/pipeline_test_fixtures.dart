import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_fingerprint.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_integration_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';

/// Shared fixtures for CI/CD integration domain tests.
class PipelineTestFixtures {
  static const projectId = 'masterpalm-demo';
  static const referenceTime = '2026-07-22T12:00:00.000Z';
  static const completedTime = '2026-07-22T12:15:00.000Z';
  static const sha256Placeholder =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  static PipelineStep validBuildStep() {
    return const PipelineStep(
      stepId: 'step-build',
      name: 'Build',
      stepType: PipelineStepType.build,
      order: 0,
    );
  }

  static PipelineStep validTestStep() {
    return const PipelineStep(
      stepId: 'step-test',
      name: 'Test',
      stepType: PipelineStepType.test,
      order: 1,
      dependsOn: ['step-build'],
    );
  }

  static PipelineStage validBuildStage() {
    return PipelineStage(
      stageId: 'stage-build',
      name: 'Build & Test',
      stageType: PipelineStageType.sequential,
      order: 0,
      steps: [validBuildStep(), validTestStep()],
    );
  }

  static PipelineTrigger validTrigger() {
    return const PipelineTrigger(
      triggerId: 'trigger-push',
      triggerType: PipelineTriggerType.push,
      configuration: {'branch': 'main'},
    );
  }

  static PipelineEnvironment validEnvironment() {
    return const PipelineEnvironment(
      environmentId: 'env-staging',
      name: 'Staging',
      environmentType: PipelineEnvironmentType.staging,
      variables: {'REGION': 'us-east-1'},
    );
  }

  static PipelineArtifact validArtifact() {
    return const PipelineArtifact(
      artifactId: 'art-apk',
      name: 'release-apk',
      artifactType: PipelineArtifactType.binary,
      uri: 'artifacts://build/release.apk',
      fingerprint: sha256Placeholder,
    );
  }

  static PipelineDefinition validDefinition() {
    final comparable = {
      'definitionId': 'def-ci-001',
      'name': 'CI Pipeline',
      'version': 1,
      'stages': [validBuildStage().toComparableJson()],
      'triggers': [validTrigger().toComparableJson()],
      'environments': [validEnvironment().toComparableJson()],
      'artifacts': [validArtifact().toComparableJson()],
      'schemaVersion': PipelineDefinition.currentSchemaVersion,
      'canonicalizationVersion':
          PipelineDefinition.currentCanonicalizationVersion,
    };
    final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

    return PipelineDefinition(
      definitionId: 'def-ci-001',
      name: 'CI Pipeline',
      version: 1,
      stages: [validBuildStage()],
      triggers: [validTrigger()],
      environments: [validEnvironment()],
      artifacts: [validArtifact()],
      fingerprint: fingerprint,
      metadata: {'projectId': projectId},
    );
  }

  static PipelineExecutionResult validExecutionResult() {
    return PipelineExecutionResult(
      resultId: 'exec-result-001',
      outcome: PipelineExecutionOutcome.success,
      status: PipelineStatus.succeeded,
      summary: 'All steps passed',
      artifactIds: const ['art-apk'],
      completedAt: completedTime,
    );
  }

  static PipelineExecution validExecution() {
    final definition = validDefinition();
    final comparable = {
      'executionId': 'exec-001',
      'definitionId': definition.definitionId,
      'definitionVersion': definition.version,
      'definitionFingerprint': definition.fingerprint,
      'triggerId': 'trigger-push',
      'environmentId': 'env-staging',
      'status': PipelineStatus.succeeded.wireName,
      'result': validExecutionResult().toComparableJson(),
      'artifacts': [validArtifact().toComparableJson()],
      'schemaVersion': PipelineExecution.currentSchemaVersion,
    };
    final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

    return PipelineExecution(
      executionId: 'exec-001',
      definitionId: definition.definitionId,
      definitionVersion: definition.version,
      definitionFingerprint: definition.fingerprint,
      triggerId: 'trigger-push',
      environmentId: 'env-staging',
      status: PipelineStatus.succeeded,
      startedAt: referenceTime,
      completedAt: completedTime,
      result: validExecutionResult(),
      artifacts: [validArtifact()],
      fingerprint: fingerprint,
    );
  }

  static PipelineReference validReference() {
    return const PipelineReference(
      referenceId: 'ref-gh-001',
      providerType: PipelineProviderType.githubActions,
      externalId: 'workflow-123',
      uri: 'https://example.com/workflow/123',
      projectId: projectId,
      repository: 'org/repo',
      branch: 'main',
    );
  }

  static PipelineCapability validCapability() {
    return const PipelineCapability(
      capabilityId: 'cap-build-001',
      capabilityType: PipelineCapabilityType.build,
      name: 'Build',
      limitations: const ['no-matrix'],
    );
  }

  static PipelineMetadata validMetadata() {
    return PipelineMetadata(
      metadataId: 'meta-001',
      schemaVersion: 1,
      canonicalizationVersion: 1,
      createdAt: referenceTime,
      owner: 'platform-team',
      tags: const ['ci', 'release'],
      fingerprint: sha256Placeholder,
    );
  }

  static DeploymentTarget validDeploymentTarget() {
    return const DeploymentTarget(
      targetId: 'target-k8s-001',
      name: 'Staging Cluster',
      targetType: DeploymentTargetType.kubernetes,
      uri: 'k8s://cluster/staging',
      region: 'us-east-1',
    );
  }

  static DeploymentApproval validDeploymentApproval() {
    return const DeploymentApproval(
      approvalId: 'approval-001',
      status: DeploymentApprovalStatus.approved,
      approver: 'release-manager',
      approvedAt: referenceTime,
    );
  }

  static DeploymentWindow validDeploymentWindow() {
    return const DeploymentWindow(
      windowId: 'window-001',
      startAt: '2026-07-22T10:00:00.000Z',
      endAt: '2026-07-22T18:00:00.000Z',
      timezone: 'UTC',
    );
  }

  static DeploymentPlan validDeploymentPlan() {
    final comparable = {
      'planId': 'plan-001',
      'name': 'Staging Rollout',
      'strategy': DeploymentStrategy.rolling.wireName,
      'targets': [validDeploymentTarget().toComparableJson()],
      'approvals': [validDeploymentApproval().toComparableJson()],
      'windows': [validDeploymentWindow().toComparableJson()],
      'environmentId': 'env-staging',
      'pipelineExecutionId': 'exec-001',
      'schemaVersion': DeploymentPlan.currentSchemaVersion,
    };
    final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

    return DeploymentPlan(
      planId: 'plan-001',
      name: 'Staging Rollout',
      strategy: DeploymentStrategy.rolling,
      targets: [validDeploymentTarget()],
      approvals: [validDeploymentApproval()],
      windows: [validDeploymentWindow()],
      environmentId: 'env-staging',
      pipelineExecutionId: 'exec-001',
      fingerprint: fingerprint,
    );
  }

  static DeploymentResult validDeploymentResult() {
    return DeploymentResult(
      resultId: 'dep-result-001',
      planId: 'plan-001',
      status: DeploymentResultStatus.succeeded,
      startedAt: referenceTime,
      completedAt: completedTime,
      targetResults: const {'target-k8s-001': 'succeeded'},
    );
  }
}
