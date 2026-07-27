import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import 'cicd_integration_canonical_serializer.dart';
import 'cicd_integration_collector.dart';
import 'cicd_integration_engine.dart';
import 'cicd_integration_identity_builder.dart';
import 'deployment_plan_builder.dart';
import 'pipeline_execution_builder.dart';
import 'pipeline_snapshot_builder.dart';
import 'resolved_cicd_integration_sources.dart';

/// Builds [CicdIntegrationSnapshot] from collected CI/CD integration artifacts.
class CicdIntegrationSnapshotBuilder {
  CicdIntegrationSnapshotBuilder({
    PipelineSnapshotBuilder? pipelineSnapshotBuilder,
    PipelineExecutionBuilder? pipelineExecutionBuilder,
    DeploymentPlanBuilder? deploymentPlanBuilder,
    CicdIntegrationEngine? engine,
    CicdIntegrationCanonicalSerializer? serializer,
    CicdIntegrationIdentityBuilder? identityBuilder,
  })  : _pipelineSnapshotBuilder =
            pipelineSnapshotBuilder ?? const PipelineSnapshotBuilder(),
        _pipelineExecutionBuilder =
            pipelineExecutionBuilder ?? const PipelineExecutionBuilder(),
        _deploymentPlanBuilder =
            deploymentPlanBuilder ?? const DeploymentPlanBuilder(),
        _engine = engine ?? const CicdIntegrationEngine(),
        _serializer = serializer ?? const CicdIntegrationCanonicalSerializer(),
        _identityBuilder =
            identityBuilder ?? const CicdIntegrationIdentityBuilder();

  final PipelineSnapshotBuilder _pipelineSnapshotBuilder;
  final PipelineExecutionBuilder _pipelineExecutionBuilder;
  final DeploymentPlanBuilder _deploymentPlanBuilder;
  final CicdIntegrationEngine _engine;
  final CicdIntegrationCanonicalSerializer _serializer;
  final CicdIntegrationIdentityBuilder _identityBuilder;

  CicdIntegrationSnapshotBuildResult build({
    required CicdIntegrationEvaluationContext context,
    required CicdIntegrationCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final request = context.request;
    final sources = context.sources;
    final warnings = <String>[];
    final limitations = <String>[
      ...sources.limitations.map((e) => e.description),
      ...context.pipelineIntegrationPolicy.metadata.limitations,
      ...context.pipelineExecutionPolicy.metadata.limitations,
      ...context.deploymentIntegrationPolicy.metadata.limitations,
      'structural-assembly-only',
      'no-pipeline-execution',
    ];

    final pipelineDefinition = _pipelineSnapshotBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );
    final executionBuild = _pipelineExecutionBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );
    final deploymentBuild = _deploymentPlanBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );

    final engineMessages = _engine.evaluate(
      context: context,
      collected: collected,
      pipelineDefinition: pipelineDefinition,
      pipelineExecution: executionBuild.execution,
      pipelineExecutionResult: executionBuild.result,
      deploymentPlan: deploymentBuild.plan,
      deploymentResult: deploymentBuild.result,
    );

    for (final message in engineMessages) {
      if (message.severity == CicdIntegrationMessageSeverity.warning ||
          message.severity == CicdIntegrationMessageSeverity.info) {
        warnings.add(message.message);
      }
    }

    final integrationPolicyFp =
        context.pipelineIntegrationPolicy.metadata.fingerprint ??
            _serializer.pipelineIntegrationPolicyFingerprint(
              context.pipelineIntegrationPolicy,
            );
    final executionPolicyFp =
        context.pipelineExecutionPolicy.metadata.fingerprint ??
            _serializer.pipelineExecutionPolicyFingerprint(
              context.pipelineExecutionPolicy,
            );
    final deploymentPolicyFp =
        context.deploymentIntegrationPolicy.metadata.fingerprint ??
            _serializer.deploymentIntegrationPolicyFingerprint(
              context.deploymentIntegrationPolicy,
            );

    final pipelineFp = _identityBuilder.pipelineFingerprint(pipelineDefinition);
    final executionFp = _identityBuilder.executionFingerprint(
      executionBuild.execution,
    );
    final executionResultFp = _identityBuilder.executionResultFingerprint(
      executionBuild.result,
    );
    final deploymentPlanFp = _identityBuilder.deploymentPlanFingerprint(
      deploymentBuild.plan,
    );
    final deploymentResultFp = _identityBuilder.deploymentResultFingerprint(
      deploymentBuild.result,
    );

    final hasCriticalData = pipelineDefinition != null;
    final status = hasCriticalData
        ? (executionBuild.execution == null || deploymentBuild.plan == null)
            ? CicdIntegrationSnapshotStatus.partial
            : CicdIntegrationSnapshotStatus.complete
        : CicdIntegrationSnapshotStatus.invalid;

    final provisionalMetadata = CicdIntegrationSnapshotMetadata(
      cicdIntegrationSnapshotId: 'provisional',
      projectId: request.projectId,
      releaseId: request.releaseId,
      pipelineDefinitionId: pipelineDefinition?.definitionId,
      pipelineDefinitionVersion: pipelineDefinition?.version,
      pipelineExecutionId: executionBuild.execution?.executionId,
      deploymentPlanId: deploymentBuild.plan?.planId,
      releaseEvidenceBundleId:
          collected.releaseEvidenceBundle?.metadata.bundleId,
      releaseSupplyChainSnapshotId:
          collected.releaseSupplyChainSnapshot?.metadata.supplyChainSnapshotId,
      pipelineIntegrationPolicyId:
          context.pipelineIntegrationPolicy.metadata.policyId,
      pipelineIntegrationPolicyVersion:
          context.pipelineIntegrationPolicy.metadata.policyVersion,
      pipelineExecutionPolicyId:
          context.pipelineExecutionPolicy.metadata.policyId,
      pipelineExecutionPolicyVersion:
          context.pipelineExecutionPolicy.metadata.policyVersion,
      deploymentIntegrationPolicyId:
          context.deploymentIntegrationPolicy.metadata.policyId,
      deploymentIntegrationPolicyVersion:
          context.deploymentIntegrationPolicy.metadata.policyVersion,
      schemaVersion: CicdIntegrationSnapshotMetadata.currentSchemaVersion,
      canonicalizationVersion:
          CicdIntegrationSnapshotMetadata.currentCanonicalizationVersion,
      createdAt: evaluatedAt,
      evaluatedAt: evaluatedAt,
      fingerprint: 'provisional',
      status: status,
      pipelineFingerprint: pipelineFp.isEmpty ? null : pipelineFp,
      executionFingerprint: executionFp.isEmpty ? null : executionFp,
      executionResultFingerprint:
          executionResultFp.isEmpty ? null : executionResultFp,
      deploymentPlanFingerprint:
          deploymentPlanFp.isEmpty ? null : deploymentPlanFp,
      deploymentResultFingerprint:
          deploymentResultFp.isEmpty ? null : deploymentResultFp,
      limitations: limitations,
    );

    final provisionalIdentity = _identityBuilder.buildIdentity(
      cicdIntegrationId: 'provisional',
      pipelineDefinition: pipelineDefinition,
      pipelineExecution: executionBuild.execution,
      pipelineExecutionResult: executionBuild.result,
      deploymentPlan: deploymentBuild.plan,
      deploymentResult: deploymentBuild.result,
      snapshotFingerprint: 'provisional',
    );

    final provisionalSnapshot = CicdIntegrationSnapshot(
      metadata: provisionalMetadata,
      fingerprint: 'provisional',
      status: status,
      pipelineDefinition: pipelineDefinition,
      pipelineExecution: executionBuild.execution,
      pipelineExecutionResult: executionBuild.result,
      deploymentPlan: deploymentBuild.plan,
      deploymentResult: deploymentBuild.result,
      sourceReferences: List.unmodifiable(sources.sourceReferences),
      identity: provisionalIdentity,
      warnings: warnings,
      limitations: limitations,
    );

    final snapshotFingerprint =
        _identityBuilder.fingerprintForSnapshot(provisionalSnapshot);
    final snapshotId = _identityBuilder.buildCicdIntegrationId(
      projectId: request.projectId,
      releaseId: request.releaseId,
      pipelineIntegrationPolicyId:
          context.pipelineIntegrationPolicy.metadata.policyId,
      pipelineIntegrationPolicyVersion:
          context.pipelineIntegrationPolicy.metadata.policyVersion,
      snapshotFingerprint: snapshotFingerprint,
      schemaVersion: CicdIntegrationSnapshotMetadata.currentSchemaVersion,
    );

    final identity = provisionalIdentity.copyWith(
      cicdIntegrationId: snapshotId,
      snapshotFingerprint: snapshotFingerprint,
    );

    final metadata = provisionalMetadata.copyWith(
      cicdIntegrationSnapshotId: snapshotId,
      fingerprint: snapshotFingerprint,
    );

    final snapshot = provisionalSnapshot.copyWith(
      metadata: metadata,
      fingerprint: snapshotFingerprint,
      identity: identity,
      policyReference: CicdIntegrationPolicyReference(
        pipelineIntegrationPolicyId:
            context.pipelineIntegrationPolicy.metadata.policyId,
        pipelineIntegrationPolicyVersion:
            context.pipelineIntegrationPolicy.metadata.policyVersion,
        pipelineExecutionPolicyId:
            context.pipelineExecutionPolicy.metadata.policyId,
        pipelineExecutionPolicyVersion:
            context.pipelineExecutionPolicy.metadata.policyVersion,
        deploymentIntegrationPolicyId:
            context.deploymentIntegrationPolicy.metadata.policyId,
        deploymentIntegrationPolicyVersion:
            context.deploymentIntegrationPolicy.metadata.policyVersion,
        pipelineIntegrationPolicyFingerprint: integrationPolicyFp,
        pipelineExecutionPolicyFingerprint: executionPolicyFp,
        deploymentIntegrationPolicyFingerprint: deploymentPolicyFp,
      ),
    );

    return CicdIntegrationSnapshotBuildResult(
      snapshot: snapshot,
      policyReference: snapshot.policyReference!,
      messages: engineMessages,
    );
  }
}

/// Result of building a CI/CD integration snapshot.
class CicdIntegrationSnapshotBuildResult {
  const CicdIntegrationSnapshotBuildResult({
    required this.snapshot,
    required this.policyReference,
    this.messages = const [],
  });

  final CicdIntegrationSnapshot snapshot;
  final CicdIntegrationPolicyReference policyReference;
  final List<CicdIntegrationMessage> messages;
}
