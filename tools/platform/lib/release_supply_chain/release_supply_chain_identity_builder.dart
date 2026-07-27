import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/compliance_models.dart';
import '../models/release_supply_chain/release_distribution_models.dart';
import '../models/release_supply_chain/release_provenance_record.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/release_supply_chain/sbom_models.dart';
import '../models/release_supply_chain/supply_chain_models.dart';
import 'release_supply_chain_canonical_serializer.dart';

/// Builds deterministic release supply chain identities and fingerprints.
class ReleaseSupplyChainIdentityBuilder {
  const ReleaseSupplyChainIdentityBuilder({
    ReleaseSupplyChainCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const ReleaseSupplyChainCanonicalSerializer();

  final ReleaseSupplyChainCanonicalSerializer _serializer;

  String buildSupplyChainId({
    required String projectId,
    required String releaseId,
    required String supplyChainPolicyId,
    required int supplyChainPolicyVersion,
    required String snapshotFingerprint,
    required int schemaVersion,
  }) {
    return 'release-supply-chain:$projectId:$releaseId:$supplyChainPolicyId:$supplyChainPolicyVersion:$snapshotFingerprint:$schemaVersion';
  }

  String buildSupplyChainIdFromSnapshot(ReleaseSupplyChainSnapshot snapshot) {
    return buildSupplyChainId(
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId ?? 'unknown',
      supplyChainPolicyId: snapshot.metadata.supplyChainPolicyId,
      supplyChainPolicyVersion: snapshot.metadata.supplyChainPolicyVersion,
      snapshotFingerprint: snapshot.fingerprint,
      schemaVersion: snapshot.metadata.schemaVersion,
    );
  }

  String fingerprintForSnapshot(ReleaseSupplyChainSnapshot snapshot) {
    return _serializer.snapshotFingerprint(snapshot);
  }

  String graphFingerprint(SupplyChainRecord? record) {
    if (record == null) return '';
    return _serializer.supplyChainFingerprint(record);
  }

  String sbomFingerprint(SoftwareBillOfMaterials? sbom) {
    if (sbom == null) return '';
    return _serializer.sbomFingerprint(sbom);
  }

  String registryFingerprint(List<ArtifactRecord> artifacts) {
    if (artifacts.isEmpty) return '';
    return _serializer.registryFingerprint(artifacts);
  }

  String distributionFingerprint(ReleaseDistribution? distribution) {
    if (distribution == null) return '';
    return _serializer.distributionFingerprint(distribution);
  }

  String complianceFingerprint(ComplianceResult? compliance) {
    if (compliance == null) return '';
    return _serializer.complianceFingerprint(compliance);
  }

  String provenanceFingerprint(ReleaseProvenanceRecord? provenance) {
    if (provenance == null) return '';
    return _serializer.provenanceFingerprint(provenance);
  }
}
