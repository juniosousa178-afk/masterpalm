import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import '../models/release_supply_chain/supply_chain_models.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Builds [SupplyChainRecord] from collected supply chain artifacts.
class SupplyChainGraphBuilder {
  const SupplyChainGraphBuilder();

  SupplyChainRecord? build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    final policy = context.supplyChainPolicy.policy;
    final bundle = collected.releaseEvidenceBundle;
    final qg = collected.qualityGateSnapshot;

    if (collected.artifacts.isEmpty) {
      return null;
    }

    const actor = SupplyChainActor(
      actorId: 'actor-ci',
      actorType: SupplyChainActorType.pipeline,
      name: 'CI Pipeline',
    );

    final stages = <SupplyChainStage>[];
    final nodes = <SupplyChainNode>[];
    final evidence = <SupplyChainEvidence>[];

    for (final stageType in policy.requiredStageTypes) {
      final stageId = 'stage-${stageType.wireName}';
      final artifactId = 'art-${stageType.wireName}-001';
      stages.add(
        SupplyChainStage(
          stageId: stageId,
          stageType: stageType,
          name: stageType.wireName,
          actorId: actor.actorId,
          outputArtifactIds: [artifactId],
        ),
      );
      nodes.add(
        SupplyChainNode(
          nodeId: 'node-${stageType.wireName}',
          stageId: stageId,
          artifactId: artifactId,
          fingerprint: 'fp-${stageType.wireName}-001',
        ),
      );
    }

    if (qg != null) {
      evidence.add(
        SupplyChainEvidence(
          evidenceId: 'ev-qg',
          artifactId: 'art-qg-${qg.metadata.qualityGateSnapshotId}',
          fingerprint: qg.metadata.qualityGateFingerprint,
          evidenceType: 'qualityGateSnapshot',
          snapshotId: qg.metadata.qualityGateSnapshotId,
        ),
      );
    }

    final comparable = {
      'projectId': releaseContext.projectId,
      'releaseId': releaseContext.releaseId,
      'status': SupplyChainStatus.active.wireName,
      'policy': policy.toComparableJson(),
      'schemaVersion': SupplyChainRecord.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return SupplyChainRecord(
      recordId: 'sc-record-${releaseContext.releaseId}',
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
      releaseEvidenceBundleId: bundle?.metadata.bundleId,
      status: SupplyChainStatus.active,
      fingerprint: fingerprint,
      policy: policy,
      actors: const [actor],
      stages: stages,
      nodes: nodes,
      edges: const [],
      evidence: evidence,
      schemaVersion: SupplyChainRecord.currentSchemaVersion,
      createdAt: evaluatedAt,
      recordedAt: evaluatedAt,
    );
  }
}
