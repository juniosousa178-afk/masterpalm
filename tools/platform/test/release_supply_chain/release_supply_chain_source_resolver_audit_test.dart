import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_source_resolver.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain source resolver audit', () {
    late FakeQualityGateProviderForSupplyChain qgProvider;
    late FakeReleaseGovernanceProviderForSupplyChain rgProvider;
    late FakeReleaseEvidenceProviderForSupplyChain reProvider;
    late ReleaseSupplyChainSourceResolver resolver;

    setUp(() {
      qgProvider = FakeQualityGateProviderForSupplyChain();
      rgProvider = FakeReleaseGovernanceProviderForSupplyChain();
      reProvider = FakeReleaseEvidenceProviderForSupplyChain();
      resolver = ReleaseSupplyChainSourceResolver(
        qualityGateProvider: qgProvider,
        releaseGovernanceProvider: rgProvider,
        releaseEvidenceProvider: reProvider,
      );
    });

    test('injected quality gate wins over byId and latest', () async {
      final injected =
          ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      qgProvider.loaded =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(
        id: 'qg-store',
      );
      qgProvider.latestSnapshot = injected;

      final request = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        qualityGateSnapshot: injected,
        qualityGateSnapshotId: 'qg-store',
        useLatest: true,
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedSupplyChainPolicy: SupplyChainPolicyV1.create(),
        injectedDistributionPolicy: DistributionPolicyV1.create(),
        injectedCompliancePolicy: CompliancePolicyV1.create(),
      );

      expect(qgProvider.loadCalls, 0);
      expect(qgProvider.latestCalls, 0);
      expect(qgProvider.evaluateCalls, 0);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseSupplyChainSourceResolutionMode.injected,
      );
    });

    test('byId resolves when injected absent', () async {
      final stored =
          ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      qgProvider.loaded = stored;

      final request = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        qualityGateSnapshotId: stored.metadata.qualityGateSnapshotId,
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(request);
      expect(qgProvider.loadCalls, 1);
      expect(sources.qualityGateSnapshot.isAvailable, isTrue);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseSupplyChainSourceResolutionMode.byId,
      );
    });

    test('latest only when useLatest is true', () async {
      final latest =
          ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      qgProvider.latestSnapshot = latest;

      final withLatest = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        useLatest: true,
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );
      final withoutLatest = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final resolvedLatest = await resolver.resolveAll(withLatest);
      final resolvedNone = await resolver.resolveAll(withoutLatest);

      expect(qgProvider.latestCalls, 1);
      expect(resolvedLatest.qualityGateSnapshot.isAvailable, isTrue);
      expect(
        resolvedNone.qualityGateSnapshot.state,
        ReleaseSupplyChainSourceState.notRequested,
      );
    });

    test('missing byId does not fall back to latest implicitly', () async {
      qgProvider.latestSnapshot =
          ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();

      final request = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        qualityGateSnapshotId: 'missing-qg',
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(request);
      expect(qgProvider.latestCalls, 0);
      expect(sources.qualityGateSnapshot.isAvailable, isFalse);
    });

    test('resolver never calls origin evaluate', () async {
      await resolver.resolveAll(
        ReleaseSupplyChainTestFixtures.passingRequest(),
        injectedSupplyChainPolicy: SupplyChainPolicyV1.create(),
        injectedDistributionPolicy: DistributionPolicyV1.create(),
        injectedCompliancePolicy: CompliancePolicyV1.create(),
      );
      expect(qgProvider.evaluateCalls, 0);
      expect(rgProvider.evaluateCalls, 0);
      expect(reProvider.evaluateCalls, 0);
    });
  });
}
