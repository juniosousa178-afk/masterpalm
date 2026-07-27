import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/release_distribution_models.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Builds [ReleaseDistribution] from collected supply chain artifacts.
class DistributionBuilder {
  const DistributionBuilder();

  ReleaseDistribution? build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required List<ArtifactRecord> artifacts,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    final policy = context.distributionPolicy.policy;
    final bundle = collected.releaseEvidenceBundle;

    if (artifacts.isEmpty) {
      return null;
    }

    final channelType = policy.allowedChannelTypes.first;
    final channel = ReleaseChannel(
      channelId: 'ch-${channelType.wireName}',
      channelType: channelType,
      name: channelType.wireName,
    );
    const target = DistributionTarget(
      targetId: 'target-registry',
      targetType: DistributionTargetType.registry,
      uri: 'registry://releases/masterpalm-app',
    );
    final manifest = DistributionManifest(
      manifestId: 'dist-manifest-${releaseContext.releaseId}',
      artifactRecordIds: artifacts.map((e) => e.metadata.recordId).toList(),
      fingerprint: 'fp-manifest-${releaseContext.releaseId}',
    );

    final comparable = {
      'projectId': releaseContext.projectId,
      'releaseId': releaseContext.releaseId,
      'status': DistributionStatus.published.wireName,
      'channel': channel.toComparableJson(),
      'policy': policy.toComparableJson(),
      'targets': [target.toComparableJson()],
      'manifest': manifest.toComparableJson(),
      'schemaVersion': ReleaseDistribution.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ReleaseDistribution(
      distributionId: 'dist-${releaseContext.releaseId}',
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
      releaseEvidenceBundleId: bundle?.metadata.bundleId,
      status: DistributionStatus.published,
      fingerprint: fingerprint,
      channel: channel,
      policy: policy,
      targets: const [target],
      manifest: manifest,
      schemaVersion: ReleaseDistribution.currentSchemaVersion,
      createdAt: evaluatedAt,
      distributedAt: evaluatedAt,
    );
  }
}
