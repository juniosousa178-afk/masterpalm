import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'artifact_registry_builder.dart';
import 'compliance_engine.dart';
import 'distribution_builder.dart';
import 'release_provenance_builder.dart';
import 'release_supply_chain_canonical_serializer.dart';
import 'release_supply_chain_collector.dart';
import 'release_supply_chain_identity_builder.dart';
import 'resolved_release_supply_chain_sources.dart';
import 'sbom_builder.dart';
import 'supply_chain_graph_builder.dart';

/// Builds [ReleaseSupplyChainSnapshot] from collected supply chain artifacts.
class ReleaseSupplyChainSnapshotBuilder {
  ReleaseSupplyChainSnapshotBuilder({
    ReleaseProvenanceBuilder? provenanceBuilder,
    SupplyChainGraphBuilder? supplyChainGraphBuilder,
    SbomBuilder? sbomBuilder,
    ArtifactRegistryBuilder? artifactRegistryBuilder,
    DistributionBuilder? distributionBuilder,
    ComplianceEngine? complianceEngine,
    ReleaseSupplyChainCanonicalSerializer? serializer,
    ReleaseSupplyChainIdentityBuilder? identityBuilder,
  })  : _provenanceBuilder =
            provenanceBuilder ?? const ReleaseProvenanceBuilder(),
        _supplyChainGraphBuilder =
            supplyChainGraphBuilder ?? const SupplyChainGraphBuilder(),
        _sbomBuilder = sbomBuilder ?? const SbomBuilder(),
        _artifactRegistryBuilder =
            artifactRegistryBuilder ?? const ArtifactRegistryBuilder(),
        _distributionBuilder =
            distributionBuilder ?? const DistributionBuilder(),
        _complianceEngine = complianceEngine ?? const ComplianceEngine(),
        _serializer =
            serializer ?? const ReleaseSupplyChainCanonicalSerializer(),
        _identityBuilder =
            identityBuilder ?? const ReleaseSupplyChainIdentityBuilder();

  final ReleaseProvenanceBuilder _provenanceBuilder;
  final SupplyChainGraphBuilder _supplyChainGraphBuilder;
  final SbomBuilder _sbomBuilder;
  final ArtifactRegistryBuilder _artifactRegistryBuilder;
  final DistributionBuilder _distributionBuilder;
  final ComplianceEngine _complianceEngine;
  final ReleaseSupplyChainCanonicalSerializer _serializer;
  final ReleaseSupplyChainIdentityBuilder _identityBuilder;

  ReleaseSupplyChainSnapshotBuildResult build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    final sources = context.sources;
    final warnings = <String>[];
    final limitations = <String>[
      ...sources.limitations.map((e) => e.description),
      ...context.supplyChainPolicy.metadata.limitations,
      ...context.distributionPolicy.metadata.limitations,
      ...context.compliancePolicy.metadata.limitations,
      'structural-assembly-only',
      'no-cryptographic-verification',
    ];

    final provenance = _provenanceBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );
    final supplyChain = _supplyChainGraphBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );
    final sbom = _sbomBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
    );
    final artifacts = _artifactRegistryBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: evaluatedAt,
      provenanceRecordId: provenance?.metadata.provenanceRecordId,
    );
    final distribution = _distributionBuilder.build(
      context: context,
      collected: collected,
      artifacts: artifacts,
      evaluatedAt: evaluatedAt,
    );
    final compliance = _complianceEngine.evaluate(
      context: context,
      collected: collected,
      provenance: provenance,
      supplyChain: supplyChain,
      sbom: sbom,
      artifacts: artifacts,
      distribution: distribution,
      evaluatedAt: evaluatedAt,
    );

    final supplyChainPolicyFp =
        context.supplyChainPolicy.metadata.fingerprint ??
            _serializer.supplyChainPolicyFingerprint(context.supplyChainPolicy);
    final distributionPolicyFp =
        context.distributionPolicy.metadata.fingerprint ??
            _serializer.distributionPolicyFingerprint(
              context.distributionPolicy,
            );
    final compliancePolicyFp = context.compliancePolicy.metadata.fingerprint ??
        _serializer.compliancePolicyFingerprint(context.compliancePolicy);

    final provenanceFp = _identityBuilder.provenanceFingerprint(provenance);
    final graphFp = _identityBuilder.graphFingerprint(supplyChain);
    final sbomFp = _identityBuilder.sbomFingerprint(sbom);
    final registryFp = _identityBuilder.registryFingerprint(artifacts);
    final distributionFp =
        _identityBuilder.distributionFingerprint(distribution);
    final complianceFp = _identityBuilder.complianceFingerprint(compliance);

    final provisionalMetadata = ReleaseSupplyChainSnapshotMetadata(
      supplyChainSnapshotId: 'provisional',
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
      releaseEvidenceBundleId:
          collected.releaseEvidenceBundle?.metadata.bundleId,
      supplyChainPolicyId: context.supplyChainPolicy.metadata.policyId,
      supplyChainPolicyVersion:
          context.supplyChainPolicy.metadata.policyVersion,
      distributionPolicyId: context.distributionPolicy.metadata.policyId,
      distributionPolicyVersion:
          context.distributionPolicy.metadata.policyVersion,
      compliancePolicyId: context.compliancePolicy.metadata.policyId,
      compliancePolicyVersion: context.compliancePolicy.metadata.policyVersion,
      schemaVersion: ReleaseSupplyChainSnapshotMetadata.currentSchemaVersion,
      canonicalizationVersion:
          ReleaseSupplyChainSnapshotMetadata.currentCanonicalizationVersion,
      createdAt: evaluatedAt,
      evaluatedAt: evaluatedAt,
      fingerprint: 'provisional',
      provenanceFingerprint: provenanceFp.isEmpty ? null : provenanceFp,
      graphFingerprint: graphFp.isEmpty ? null : graphFp,
      sbomFingerprint: sbomFp.isEmpty ? null : sbomFp,
      registryFingerprint: registryFp.isEmpty ? null : registryFp,
      distributionFingerprint: distributionFp.isEmpty ? null : distributionFp,
      complianceFingerprint: complianceFp.isEmpty ? null : complianceFp,
      limitations: limitations,
    );

    final provisionalSnapshot = ReleaseSupplyChainSnapshot(
      metadata: provisionalMetadata,
      fingerprint: 'provisional',
      provenance: provenance,
      supplyChain: supplyChain,
      sbom: sbom,
      artifacts: artifacts,
      distribution: distribution,
      compliance: compliance,
      warnings: warnings,
      limitations: limitations,
    );

    final snapshotFingerprint =
        _identityBuilder.fingerprintForSnapshot(provisionalSnapshot);
    final snapshotId = _identityBuilder.buildSupplyChainId(
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      supplyChainPolicyId: context.supplyChainPolicy.metadata.policyId,
      supplyChainPolicyVersion:
          context.supplyChainPolicy.metadata.policyVersion,
      snapshotFingerprint: snapshotFingerprint,
      schemaVersion: ReleaseSupplyChainSnapshotMetadata.currentSchemaVersion,
    );

    final metadata = provisionalMetadata.copyWith(
      supplyChainSnapshotId: snapshotId,
      fingerprint: snapshotFingerprint,
    );

    final snapshot = provisionalSnapshot.copyWith(
      metadata: metadata,
      fingerprint: snapshotFingerprint,
    );

    return ReleaseSupplyChainSnapshotBuildResult(
      snapshot: snapshot,
      policyReference: ReleaseSupplyChainPolicyReference(
        supplyChainPolicyId: context.supplyChainPolicy.metadata.policyId,
        supplyChainPolicyVersion:
            context.supplyChainPolicy.metadata.policyVersion,
        distributionPolicyId: context.distributionPolicy.metadata.policyId,
        distributionPolicyVersion:
            context.distributionPolicy.metadata.policyVersion,
        compliancePolicyId: context.compliancePolicy.metadata.policyId,
        compliancePolicyVersion:
            context.compliancePolicy.metadata.policyVersion,
        supplyChainPolicyFingerprint: supplyChainPolicyFp,
        distributionPolicyFingerprint: distributionPolicyFp,
        compliancePolicyFingerprint: compliancePolicyFp,
      ),
    );
  }
}

/// Result of building a release supply chain snapshot.
class ReleaseSupplyChainSnapshotBuildResult {
  const ReleaseSupplyChainSnapshotBuildResult({
    required this.snapshot,
    required this.policyReference,
  });

  final ReleaseSupplyChainSnapshot snapshot;
  final ReleaseSupplyChainPolicyReference policyReference;
}
