import '../models/cicd_integration/deployment_models.dart';
import 'cicd_integration_canonical_serializer.dart';
import 'cicd_integration_collector.dart';
import 'resolved_cicd_integration_sources.dart';

/// Result of building deployment integration artifacts.
class DeploymentPlanBuildResult {
  const DeploymentPlanBuildResult({
    this.plan,
    this.result,
  });

  final DeploymentPlan? plan;
  final DeploymentResult? result;
}

/// Builds [DeploymentPlan] and [DeploymentResult] without mutation.
class DeploymentPlanBuilder {
  const DeploymentPlanBuilder({
    CicdIntegrationCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final CicdIntegrationCanonicalSerializer _serializer;

  DeploymentPlanBuildResult build({
    required CicdIntegrationEvaluationContext context,
    required CicdIntegrationCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final plan = collected.deploymentPlan;
    final deploymentResult = collected.deploymentResult;

    DeploymentPlan? builtPlan;
    if (plan != null) {
      final fingerprint =
          plan.fingerprint ?? _serializer.deploymentPlanFingerprint(plan);
      builtPlan = DeploymentPlan(
        planId: plan.planId,
        name: plan.name,
        strategy: plan.strategy,
        targets: List.unmodifiable(plan.targets),
        approvals: List.unmodifiable(plan.approvals),
        windows: List.unmodifiable(plan.windows),
        environmentId: plan.environmentId,
        pipelineExecutionId: plan.pipelineExecutionId,
        fingerprint: fingerprint,
        metadata: Map.unmodifiable(plan.metadata),
        schemaVersion: plan.schemaVersion,
      );
    }

    DeploymentResult? builtResult;
    if (deploymentResult != null) {
      final fingerprint = deploymentResult.fingerprint ??
          _serializer.deploymentResultFingerprint(deploymentResult);
      builtResult = DeploymentResult(
        resultId: deploymentResult.resultId,
        planId: deploymentResult.planId,
        status: deploymentResult.status,
        startedAt: deploymentResult.startedAt,
        completedAt: deploymentResult.completedAt,
        targetResults: Map.unmodifiable(deploymentResult.targetResults),
        fingerprint: fingerprint,
        metadata: Map.unmodifiable(deploymentResult.metadata),
        schemaVersion: deploymentResult.schemaVersion,
      );
    }

    return DeploymentPlanBuildResult(
      plan: builtPlan,
      result: builtResult,
    );
  }
}
