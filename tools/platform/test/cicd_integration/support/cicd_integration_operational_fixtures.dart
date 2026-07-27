import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_fingerprint.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';

import '../../release_evidence/support/release_evidence_test_fixtures.dart';
import '../../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'pipeline_test_fixtures.dart';

/// Shared fixtures for CI/CD integration operational tests (Part 2).
class CicdIntegrationOperationalFixtures {
  static const projectId = PipelineTestFixtures.projectId;
  static const releaseId = ReleaseSupplyChainTestFixtures.releaseId;
  static const referenceTime = PipelineTestFixtures.referenceTime;
  static const requestId = 'cicd-req-001';

  static PipelineExecution failedExecution() {
    final definition = PipelineTestFixtures.validDefinition();
    final result = PipelineExecutionResult(
      resultId: 'exec-result-failed',
      outcome: PipelineExecutionOutcome.failure,
      status: PipelineStatus.failed,
      summary: 'Build failed',
      artifactIds: const [],
      completedAt: PipelineTestFixtures.completedTime,
    );
    final comparable = {
      'executionId': 'exec-failed-001',
      'definitionId': definition.definitionId,
      'definitionVersion': definition.version,
      'definitionFingerprint': definition.fingerprint,
      'triggerId': 'trigger-push',
      'environmentId': 'env-staging',
      'status': PipelineStatus.failed.wireName,
      'result': result.toComparableJson(),
      'artifacts': const [],
      'schemaVersion': PipelineExecution.currentSchemaVersion,
    };
    final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

    return PipelineExecution(
      executionId: 'exec-failed-001',
      definitionId: definition.definitionId,
      definitionVersion: definition.version,
      definitionFingerprint: definition.fingerprint,
      triggerId: 'trigger-push',
      environmentId: 'env-staging',
      status: PipelineStatus.failed,
      startedAt: referenceTime,
      completedAt: PipelineTestFixtures.completedTime,
      result: result,
      artifacts: const [],
      fingerprint: fingerprint,
    );
  }

  static PipelineExecution wrongDefinitionExecution() {
    final definition = PipelineTestFixtures.validDefinition();
    final comparable = {
      'executionId': 'exec-wrong-def',
      'definitionId': 'def-wrong-999',
      'definitionVersion': definition.version,
      'definitionFingerprint': definition.fingerprint,
      'triggerId': 'trigger-push',
      'environmentId': 'env-staging',
      'status': PipelineStatus.succeeded.wireName,
      'result': PipelineTestFixtures.validExecutionResult().toComparableJson(),
      'artifacts': [PipelineTestFixtures.validArtifact().toComparableJson()],
      'schemaVersion': PipelineExecution.currentSchemaVersion,
    };
    final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

    return PipelineExecution(
      executionId: 'exec-wrong-def',
      definitionId: 'def-wrong-999',
      definitionVersion: definition.version,
      definitionFingerprint: definition.fingerprint,
      triggerId: 'trigger-push',
      environmentId: 'env-staging',
      status: PipelineStatus.succeeded,
      startedAt: referenceTime,
      completedAt: PipelineTestFixtures.completedTime,
      result: PipelineTestFixtures.validExecutionResult(),
      artifacts: [PipelineTestFixtures.validArtifact()],
      fingerprint: fingerprint,
    );
  }

  static ReleaseEvidenceBundle evidenceWithProjectId(String project) {
    final bundle = ReleaseEvidenceTestFixtures.validBundle();
    return bundle.copyWith(
      metadata: bundle.metadata.copyWith(projectId: project),
    );
  }

  static ReleaseSupplyChainSnapshot supplyChainWithReleaseId(String release) {
    final snapshot = ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
    return snapshot.copyWith(
      metadata: snapshot.metadata.copyWith(releaseId: release),
    );
  }

  static CicdIntegrationRequest passingRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
    PipelineDefinition? pipelineDefinition,
    PipelineExecution? pipelineExecution,
    PipelineExecutionResult? pipelineExecutionResult,
    DeploymentPlan? deploymentPlan,
    DeploymentResult? deploymentResult,
    bool publish = false,
  }) {
    return CicdIntegrationRequest(
      requestId: requestId,
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      pipelineDefinitionId: 'def-ci-001',
      pipelineExecutionId: 'exec-001',
      deploymentPlanId: 'plan-001',
      pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
      pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
      deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      pipelineDefinition:
          pipelineDefinition ?? PipelineTestFixtures.validDefinition(),
      pipelineExecution:
          pipelineExecution ?? PipelineTestFixtures.validExecution(),
      pipelineExecutionResult: pipelineExecutionResult ??
          PipelineTestFixtures.validExecutionResult(),
      deploymentPlan:
          deploymentPlan ?? PipelineTestFixtures.validDeploymentPlan(),
      deploymentResult:
          deploymentResult ?? PipelineTestFixtures.validDeploymentResult(),
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      metadata: publish ? const {'publish': 'true'} : const {},
    );
  }

  static CicdIntegrationRequest partialRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  }) {
    return CicdIntegrationRequest(
      requestId: '${requestId}-partial',
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      pipelineDefinitionId: 'def-ci-001',
      pipelineExecutionId: 'exec-001',
      pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
      pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
      deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      pipelineDefinition: PipelineTestFixtures.validDefinition(),
      pipelineExecution: PipelineTestFixtures.validExecution(),
      pipelineExecutionResult: PipelineTestFixtures.validExecutionResult(),
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
    );
  }

  static CicdIntegrationRequest failedExecutionRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  }) {
    return passingRequest(
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      pipelineExecution: failedExecution(),
      pipelineExecutionResult: failedExecution().result,
    ).copyWith(requestId: '${requestId}-failed');
  }

  static CicdIntegrationRequest projectIdMismatchRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  }) {
    return passingRequest(
      releaseEvidenceBundle:
          releaseEvidenceBundle ?? evidenceWithProjectId('other-project'),
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
    ).copyWith(requestId: '${requestId}-project-mismatch');
  }

  static CicdIntegrationRequest releaseIdMismatchRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  }) {
    return passingRequest(
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot ??
          supplyChainWithReleaseId('rel-other-999'),
    ).copyWith(requestId: '${requestId}-release-mismatch');
  }

  static CicdIntegrationRequest wrongDefinitionRefRequest({
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  }) {
    return passingRequest(
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      pipelineExecution: wrongDefinitionExecution(),
    ).copyWith(requestId: '${requestId}-wrong-def');
  }

  static CicdIntegrationRequest missingDefinitionRequest() {
    return CicdIntegrationRequest(
      requestId: '${requestId}-missing-def',
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      pipelineDefinitionId: 'def-missing-999',
      pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
      pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
      deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
    );
  }

  static CicdIntegrationRequest byIdDefinitionRequest() {
    return CicdIntegrationRequest(
      requestId: '${requestId}-by-id',
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      pipelineDefinitionId: 'def-ci-001',
      pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
      pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
      deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
    );
  }
}
