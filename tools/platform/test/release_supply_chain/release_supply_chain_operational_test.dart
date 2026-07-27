import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_canonical_serializer.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_exceptions.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_identity_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_policy_registry.dart';
import 'package:masterpalm_platform/release_supply_chain/stores/in_memory_release_supply_chain_store.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('SupplyChainPolicyRegistry', () {
    test('registers candidate policy and resolves without implicit latest', () {
      final registry = SupplyChainPolicyRegistry();
      registry.register(SupplyChainPolicyV1.create());
      registry.freeze();

      expect(registry.candidate(SupplyChainPolicyV1.policyId), isNotNull);
      expect(registry.active(SupplyChainPolicyV1.policyId), isNull);
      expect(
        registry.resolve(
          policyId: SupplyChainPolicyV1.policyId,
          allowCandidate: true,
        ),
        isNotNull,
      );
      expect(
        registry.resolve(
          policyId: SupplyChainPolicyV1.policyId,
          allowCandidate: false,
        ),
        isNull,
      );
    });

    test('getLatestVersion is opt-in and distinct from resolve', () {
      final registry = SupplyChainPolicyRegistry();
      registry.register(SupplyChainPolicyV1.create());
      registry.freeze();

      expect(
          registry.getLatestVersion(SupplyChainPolicyV1.policyId), isNotNull);
      expect(registry.get(SupplyChainPolicyV1.policyId, 1), isNotNull);
    });

    test('frozen registry rejects registration', () {
      final registry = SupplyChainPolicyRegistry();
      registry.register(SupplyChainPolicyV1.create());
      registry.freeze();

      expect(
        () => registry.register(SupplyChainPolicyV1.create()),
        throwsA(isA<ReleaseSupplyChainRegistryFrozenException>()),
      );
    });
  });

  group('DistributionPolicyRegistry', () {
    test('registers distribution policy v1', () {
      final registry = DistributionPolicyRegistry();
      registry.register(DistributionPolicyV1.create());
      registry.freeze();

      expect(registry.contains(DistributionPolicyV1.policyId, 1), isTrue);
    });
  });

  group('CompliancePolicyRegistry', () {
    test('registers compliance policy v1', () {
      final registry = CompliancePolicyRegistry();
      registry.register(CompliancePolicyV1.create());
      registry.freeze();

      expect(registry.contains(CompliancePolicyV1.policyId, 1), isTrue);
    });
  });

  group('ReleaseSupplyChainCanonicalSerializer', () {
    const serializer = ReleaseSupplyChainCanonicalSerializer();

    test('snapshot fingerprint is deterministic', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final first = serializer.snapshotFingerprint(snapshot);
      final second = serializer.snapshotFingerprint(snapshot);
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('compliance fingerprint is deterministic', () {
      final compliance = ReleaseSupplyChainTestFixtures.validComplianceResult();
      final first = serializer.complianceFingerprint(compliance);
      final second = serializer.complianceFingerprint(compliance);
      expect(first, second);
    });
  });

  group('ReleaseSupplyChainIdentityBuilder', () {
    const identity = ReleaseSupplyChainIdentityBuilder();

    test('builds stable supply chain id from normative fields', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final id = identity.buildSupplyChainIdFromSnapshot(snapshot);
      expect(id, contains(snapshot.metadata.projectId));
      expect(id, contains(snapshot.fingerprint));
    });

    test('component fingerprints are stable', () {
      final supplyChain =
          ReleaseSupplyChainTestFixtures.validSupplyChainRecord();
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final graphFp = identity.graphFingerprint(supplyChain);
      final sbomFp = identity.sbomFingerprint(sbom);
      expect(graphFp, identity.graphFingerprint(supplyChain));
      expect(sbomFp, identity.sbomFingerprint(sbom));
    });
  });

  group('InMemoryReleaseSupplyChainStore', () {
    test('save is idempotent for same fingerprint', () async {
      final store = InMemoryReleaseSupplyChainStore();
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();

      await store.save(snapshot);
      await store.save(snapshot);

      final loaded = await store.load(snapshot.metadata.supplyChainSnapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('query filters by projectId', () async {
      final store = InMemoryReleaseSupplyChainStore();
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      await store.save(snapshot);

      final results = await store.query(
        const ReleaseSupplyChainQuery(
          projectId: ReleaseSupplyChainTestFixtures.projectId,
        ),
      );
      expect(results, isNotEmpty);
    });
  });
}
