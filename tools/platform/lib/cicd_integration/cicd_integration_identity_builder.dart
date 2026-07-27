import '../models/cicd_integration/cicd_integration_identity.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_models.dart';
import 'cicd_integration_canonical_serializer.dart';

/// Builds deterministic CI/CD integration identities and fingerprints.
class CicdIntegrationIdentityBuilder {
  const CicdIntegrationIdentityBuilder({
    CicdIntegrationCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final CicdIntegrationCanonicalSerializer _serializer;

  String buildCicdIntegrationId({
    required String projectId,
    required String? releaseId,
    required String pipelineIntegrationPolicyId,
    required int pipelineIntegrationPolicyVersion,
    required String snapshotFingerprint,
    required int schemaVersion,
  }) {
    return 'cicd-integration:$projectId:${releaseId ?? 'unknown'}:'
        '$pipelineIntegrationPolicyId:$pipelineIntegrationPolicyVersion:'
        '$snapshotFingerprint:$schemaVersion';
  }

  String buildCicdIntegrationIdFromSnapshot(CicdIntegrationSnapshot snapshot) {
    return buildCicdIntegrationId(
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId,
      pipelineIntegrationPolicyId:
          snapshot.metadata.pipelineIntegrationPolicyId,
      pipelineIntegrationPolicyVersion:
          snapshot.metadata.pipelineIntegrationPolicyVersion,
      snapshotFingerprint: snapshot.fingerprint,
      schemaVersion: snapshot.metadata.schemaVersion,
    );
  }

  String fingerprintForSnapshot(CicdIntegrationSnapshot snapshot) {
    return _serializer.snapshotFingerprint(snapshot);
  }

  String pipelineFingerprint(PipelineDefinition? definition) {
    if (definition == null) return '';
    return _serializer.pipelineDefinitionFingerprint(definition);
  }

  String executionFingerprint(PipelineExecution? execution) {
    if (execution == null) return '';
    return _serializer.pipelineExecutionFingerprint(execution);
  }

  String executionResultFingerprint(PipelineExecutionResult? result) {
    if (result == null) return '';
    return _serializer.pipelineExecutionResultFingerprint(result);
  }

  String deploymentPlanFingerprint(DeploymentPlan? plan) {
    if (plan == null) return '';
    return _serializer.deploymentPlanFingerprint(plan);
  }

  String deploymentResultFingerprint(DeploymentResult? result) {
    if (result == null) return '';
    return _serializer.deploymentResultFingerprint(result);
  }

  CicdIntegrationIdentity buildIdentity({
    required String cicdIntegrationId,
    PipelineDefinition? pipelineDefinition,
    PipelineExecution? pipelineExecution,
    PipelineExecutionResult? pipelineExecutionResult,
    DeploymentPlan? deploymentPlan,
    DeploymentResult? deploymentResult,
    required String snapshotFingerprint,
  }) {
    return CicdIntegrationIdentity(
      cicdIntegrationId: cicdIntegrationId,
      pipelineFingerprint: pipelineFingerprint(pipelineDefinition).isEmpty
          ? null
          : pipelineFingerprint(pipelineDefinition),
      executionFingerprint: executionFingerprint(pipelineExecution).isEmpty
          ? null
          : executionFingerprint(pipelineExecution),
      executionResultFingerprint:
          executionResultFingerprint(pipelineExecutionResult).isEmpty
              ? null
              : executionResultFingerprint(pipelineExecutionResult),
      deploymentPlanFingerprint:
          deploymentPlanFingerprint(deploymentPlan).isEmpty
              ? null
              : deploymentPlanFingerprint(deploymentPlan),
      deploymentResultFingerprint:
          deploymentResultFingerprint(deploymentResult).isEmpty
              ? null
              : deploymentResultFingerprint(deploymentResult),
      snapshotFingerprint: snapshotFingerprint,
    );
  }
}
