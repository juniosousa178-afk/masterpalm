import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_canonical_serializer.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_identity_builder.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain identity audit', () {
    const serializer = ReleaseSupplyChainCanonicalSerializer();
    const identity = ReleaseSupplyChainIdentityBuilder();

    test('snapshot fingerprint excludes snapshotId and temporal metadata', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final fp1 = serializer.snapshotFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          supplyChainSnapshotId: 'different-id',
          createdAt: '2099-01-01T00:00:00.000Z',
          evaluatedAt: '2099-01-01T00:00:00.000Z',
        ),
      );
      expect(serializer.snapshotFingerprint(mutated), fp1);
    });

    test('snapshot fingerprint changes when normative policy changes', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final fp1 = serializer.snapshotFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          supplyChainPolicyVersion: 99,
        ),
      );
      expect(serializer.snapshotFingerprint(mutated), isNot(fp1));
    });

    test('supplyChainSnapshotId includes normative fingerprint components', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final id = identity.buildSupplyChainIdFromSnapshot(snapshot);
      expect(id, contains(snapshot.metadata.projectId));
      expect(id, contains(snapshot.metadata.releaseId));
      expect(id, contains(snapshot.metadata.supplyChainPolicyId));
      expect(id, contains(snapshot.fingerprint));
    });

    test('graph fingerprint is stable for same normative content', () {
      final record = ReleaseSupplyChainTestFixtures.validSupplyChainRecord();
      final fp1 = serializer.supplyChainFingerprint(record);
      final fp2 = serializer.supplyChainFingerprint(record);
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test('sbom fingerprint excludes sbomId and generatedAt', () {
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final fp1 = serializer.sbomFingerprint(sbom);
      final mutated = sbom.copyWith(
        metadata: sbom.metadata.copyWith(
          sbomId: 'different-sbom-id',
          generatedAt: '2099-01-01T00:00:00.000Z',
          createdAt: '2099-01-01T00:00:00.000Z',
        ),
      );
      expect(serializer.sbomFingerprint(mutated), fp1);
    });

    test('compliance fingerprint excludes resultId and evaluatedAt', () {
      final compliance = ReleaseSupplyChainTestFixtures.validComplianceResult();
      final fp1 = serializer.complianceFingerprint(compliance);
      final mutated = compliance.copyWith(
        resultId: 'different-result-id',
        evaluatedAt: '2099-01-01T00:00:00.000Z',
      );
      expect(serializer.complianceFingerprint(mutated), fp1);
    });

    test('identity builder fingerprintForSnapshot matches serializer', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      expect(
        identity.fingerprintForSnapshot(snapshot),
        serializer.snapshotFingerprint(snapshot),
      );
    });

    test('component fingerprints match identity builder helpers', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      expect(
        identity.graphFingerprint(snapshot.supplyChain),
        serializer.supplyChainFingerprint(snapshot.supplyChain!),
      );
      expect(
        identity.sbomFingerprint(snapshot.sbom),
        serializer.sbomFingerprint(snapshot.sbom!),
      );
      expect(
        identity.registryFingerprint(snapshot.artifacts),
        serializer.registryFingerprint(snapshot.artifacts),
      );
      expect(
        identity.distributionFingerprint(snapshot.distribution),
        serializer.distributionFingerprint(snapshot.distribution!),
      );
      expect(
        identity.complianceFingerprint(snapshot.compliance),
        serializer.complianceFingerprint(snapshot.compliance!),
      );
    });
  });
}
