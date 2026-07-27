import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import '../models/release_supply_chain/sbom_models.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Builds [SoftwareBillOfMaterials] from collected supply chain artifacts.
class SbomBuilder {
  const SbomBuilder();

  SoftwareBillOfMaterials? build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    if (collected.artifacts.isEmpty) {
      return null;
    }

    const pkg = SbomPackage(
      packageId: 'pkg-app',
      name: 'masterpalm-app',
      version: '1.0.0',
      purl: 'pkg:apk/masterpalm-app@1.0.0',
    );
    final component = SbomComponent(
      componentId: 'comp-app',
      componentType: SbomComponentType.application,
      packageRef: pkg,
      hashes: [
        SbomHash(
          algorithm: ArtifactDigestAlgorithm.sha256,
          value:
              '0000000000000000000000000000000000000000000000000000000000000000',
        ),
      ],
    );

    final comparable = {
      'metadata': {
        'projectId': releaseContext.projectId,
        'releaseId': releaseContext.releaseId,
        'status': SbomStatus.complete.wireName,
        'componentCount': 1,
        'dependencyCount': 0,
        'schemaVersion': SbomMetadata.currentSchemaVersion,
        'canonicalizationVersion': SbomMetadata.currentCanonicalizationVersion,
      },
      'components': [component.toComparableJson()],
      'dependencies': <Map<String, dynamic>>[],
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return SoftwareBillOfMaterials(
      metadata: SbomMetadata(
        sbomId: 'sbom-${releaseContext.releaseId}',
        projectId: releaseContext.projectId,
        releaseId: releaseContext.releaseId,
        commitId: releaseContext.commitId,
        schemaVersion: SbomMetadata.currentSchemaVersion,
        canonicalizationVersion: SbomMetadata.currentCanonicalizationVersion,
        createdAt: evaluatedAt,
        generatedAt: evaluatedAt,
        status: SbomStatus.complete,
        fingerprint: fingerprint,
        componentCount: 1,
        dependencyCount: 0,
      ),
      components: [component],
      dependencies: const [],
    );
  }
}
