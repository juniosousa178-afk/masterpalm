import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_models.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'resolved_cicd_integration_sources.dart';

/// Located artifact reference from resolved CI/CD integration sources.
class CicdIntegrationCollectedArtifact {
  const CicdIntegrationCollectedArtifact({
    required this.artifactId,
    required this.artifactType,
    required this.sourceType,
    this.fingerprint,
    this.snapshotId,
    this.collectedAt,
  });

  final String artifactId;
  final String artifactType;
  final String sourceType;
  final String? fingerprint;
  final String? snapshotId;
  final String? collectedAt;
}

/// Collected artifacts located from resolved sources without rebuilding snapshots.
class CicdIntegrationCollectedArtifacts {
  const CicdIntegrationCollectedArtifacts({
    this.pipelineDefinition,
    this.pipelineExecution,
    this.pipelineExecutionResult,
    this.deploymentPlan,
    this.deploymentResult,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.artifacts = const [],
  });

  final PipelineDefinition? pipelineDefinition;
  final PipelineExecution? pipelineExecution;
  final PipelineExecutionResult? pipelineExecutionResult;
  final DeploymentPlan? deploymentPlan;
  final DeploymentResult? deploymentResult;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot;
  final List<CicdIntegrationCollectedArtifact> artifacts;
}

/// Locates CI/CD integration artifacts from resolved sources.
class CicdIntegrationCollector {
  const CicdIntegrationCollector();

  CicdIntegrationCollectedArtifacts collect(
    CicdIntegrationEvaluationContext context,
  ) {
    final sources = context.sources;
    final referenceTime = context.request.requestedAt;
    final collected = <CicdIntegrationCollectedArtifact>[];
    final seenArtifactIds = <String>{};

    void addArtifact(CicdIntegrationCollectedArtifact artifact) {
      if (!seenArtifactIds.add(artifact.artifactId)) return;
      collected.add(artifact);
    }

    final definition = sources.pipelineDefinition.isAvailable
        ? sources.pipelineDefinition.resolvedArtifact
        : null;
    final execution = sources.pipelineExecution.isAvailable
        ? sources.pipelineExecution.resolvedArtifact
        : null;
    final executionResult = sources.pipelineExecutionResult.isAvailable
        ? sources.pipelineExecutionResult.resolvedArtifact
        : null;
    final plan = sources.deploymentPlan.isAvailable
        ? sources.deploymentPlan.resolvedArtifact
        : null;
    final deploymentResult = sources.deploymentResult.isAvailable
        ? sources.deploymentResult.resolvedArtifact
        : null;
    final evidence = sources.releaseEvidenceBundle.isAvailable
        ? sources.releaseEvidenceBundle.resolvedArtifact
        : null;
    final supplyChain = sources.releaseSupplyChainSnapshot.isAvailable
        ? sources.releaseSupplyChainSnapshot.resolvedArtifact
        : null;

    if (definition != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: definition.definitionId,
          artifactType: 'pipelineDefinition',
          sourceType: 'pipelineDefinition',
          fingerprint: definition.fingerprint,
          snapshotId: definition.definitionId,
          collectedAt: referenceTime,
        ),
      );
      for (final stage in definition.stages) {
        for (final step in stage.steps) {
          addArtifact(
            CicdIntegrationCollectedArtifact(
              artifactId: step.stepId,
              artifactType: 'pipelineStep',
              sourceType: 'pipelineDefinition',
              fingerprint: definition.fingerprint,
              snapshotId: definition.definitionId,
              collectedAt: referenceTime,
            ),
          );
        }
      }
    }

    if (execution != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: execution.executionId,
          artifactType: 'pipelineExecution',
          sourceType: 'pipelineExecution',
          fingerprint: execution.fingerprint,
          snapshotId: execution.executionId,
          collectedAt: referenceTime,
        ),
      );
      for (final artifact in execution.artifacts) {
        addArtifact(
          CicdIntegrationCollectedArtifact(
            artifactId: artifact.artifactId,
            artifactType: artifact.artifactType.wireName,
            sourceType: 'pipelineExecution',
            fingerprint: artifact.fingerprint,
            snapshotId: execution.executionId,
            collectedAt: referenceTime,
          ),
        );
      }
    }

    if (executionResult != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: executionResult.resultId,
          artifactType: 'pipelineExecutionResult',
          sourceType: 'pipelineExecutionResult',
          fingerprint: executionResult.fingerprint,
          snapshotId: executionResult.resultId,
          collectedAt: referenceTime,
        ),
      );
    }

    if (plan != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: plan.planId,
          artifactType: 'deploymentPlan',
          sourceType: 'deploymentPlan',
          fingerprint: plan.fingerprint,
          snapshotId: plan.planId,
          collectedAt: referenceTime,
        ),
      );
      for (final target in plan.targets) {
        addArtifact(
          CicdIntegrationCollectedArtifact(
            artifactId: target.targetId,
            artifactType: 'deploymentTarget',
            sourceType: 'deploymentPlan',
            fingerprint: plan.fingerprint,
            snapshotId: plan.planId,
            collectedAt: referenceTime,
          ),
        );
      }
    }

    if (deploymentResult != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: deploymentResult.resultId,
          artifactType: 'deploymentResult',
          sourceType: 'deploymentResult',
          fingerprint: deploymentResult.fingerprint,
          snapshotId: deploymentResult.resultId,
          collectedAt: referenceTime,
        ),
      );
    }

    if (evidence != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: evidence.metadata.bundleId,
          artifactType: 'releaseEvidenceBundle',
          sourceType: 'releaseEvidenceBundle',
          fingerprint: evidence.fingerprint,
          snapshotId: evidence.metadata.bundleId,
          collectedAt: referenceTime,
        ),
      );
    }

    if (supplyChain != null) {
      addArtifact(
        CicdIntegrationCollectedArtifact(
          artifactId: supplyChain.metadata.supplyChainSnapshotId,
          artifactType: 'releaseSupplyChainSnapshot',
          sourceType: 'releaseSupplyChainSnapshot',
          fingerprint: supplyChain.fingerprint,
          snapshotId: supplyChain.metadata.supplyChainSnapshotId,
          collectedAt: referenceTime,
        ),
      );
    }

    collected.sort((a, b) => a.artifactId.compareTo(b.artifactId));

    return CicdIntegrationCollectedArtifacts(
      pipelineDefinition: definition,
      pipelineExecution: execution,
      pipelineExecutionResult: executionResult,
      deploymentPlan: plan,
      deploymentResult: deploymentResult,
      releaseEvidenceBundle: evidence,
      releaseSupplyChainSnapshot: supplyChain,
      artifacts: collected,
    );
  }
}
