import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_source_resolver.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('CryptographicTrustSourceResolver', () {
    late FakeReleaseEvidenceProviderForCryptographicTrust reProvider;
    late FakeReleaseSupplyChainProviderForCryptographicTrust rscProvider;
    late FakeCicdIntegrationProviderForCryptographicTrust cicdProvider;
    late CryptographicTrustSourceResolver resolver;

    setUp(() {
      reProvider = FakeReleaseEvidenceProviderForCryptographicTrust();
      rscProvider = FakeReleaseSupplyChainProviderForCryptographicTrust();
      cicdProvider = FakeCicdIntegrationProviderForCryptographicTrust();
      resolver = CryptographicTrustSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        cicdIntegrationProvider: cicdProvider,
        trustPolicyRegistry:
            CryptographicTrustOperationalFixtures.createPolicyRegistry(
          freeze: true,
        ),
      );
    });

    test('injected release evidence wins over byId and latest', () async {
      final injected = ReleaseEvidenceTestFixtures.validBundle();
      reProvider.loaded = ReleaseEvidenceTestFixtures.validBundle().copyWith(
        metadata: injected.metadata.copyWith(bundleId: 'stored-only'),
      );
      reProvider.latestBundle =
          ReleaseEvidenceTestFixtures.validBundle().copyWith(
        metadata: injected.metadata.copyWith(bundleId: 'latest-only'),
      );

      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        releaseEvidenceBundle: injected,
        useLatest: true,
        metadata: const {'releaseEvidenceBundleId': 'stored-only'},
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.releaseEvidenceBundle.resolutionMode,
        CryptographicTrustSourceResolutionMode.injected,
      );
      expect(
        sources.releaseEvidenceBundle.resolvedArtifact!.metadata.bundleId,
        injected.metadata.bundleId,
      );
      expect(reProvider.loadCalls, 0);
      expect(reProvider.latestCalls, 0);
      expect(reProvider.evaluateCalls, 0);
      expect(reProvider.evaluateAndPublishCalls, 0);
      expect(reProvider.publishCalls, 0);
    });

    test('byId resolves when injected absent', () async {
      final stored = ReleaseEvidenceTestFixtures.validBundle();
      reProvider.loaded = stored;

      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        metadata: {'releaseEvidenceBundleId': stored.metadata.bundleId},
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.releaseEvidenceBundle.resolutionMode,
        CryptographicTrustSourceResolutionMode.byId,
      );
      expect(reProvider.loadCalls, 1);
      expect(reProvider.latestCalls, 0);
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('latest resolves only when useLatest is true', () async {
      final latest = ReleaseEvidenceTestFixtures.validBundle();
      reProvider.latestBundle = latest;

      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        useLatest: true,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.releaseEvidenceBundle.resolutionMode,
        CryptographicTrustSourceResolutionMode.latest,
      );
      expect(reProvider.latestCalls, 1);
      expect(reProvider.loadCalls, 0);
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('useLatest false does not call latest on upstream providers',
        () async {
      reProvider.latestBundle = ReleaseEvidenceTestFixtures.validBundle();
      rscProvider.latestSnapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      cicdProvider.latestSnapshot = null;

      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        useLatest: false,
      );

      await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(reProvider.latestCalls, 0);
      expect(rscProvider.latestCalls, 0);
      expect(cicdProvider.latestCalls, 0);
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('injected supply chain snapshot wins over byId', () async {
      final injected =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      rscProvider.loaded =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot().copyWith(
        metadata: injected.metadata.copyWith(
          supplyChainSnapshotId: 'stored-only',
        ),
      );

      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        releaseSupplyChainSnapshot: injected,
        metadata: const {'releaseSupplyChainSnapshotId': 'stored-only'},
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.releaseSupplyChainSnapshot.resolutionMode,
        CryptographicTrustSourceResolutionMode.injected,
      );
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('missing byId source marks unresolved without evaluate', () async {
      reProvider.loaded = null;
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        metadata: const {'releaseEvidenceBundleId': 'missing-bundle'},
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(sources.releaseEvidenceBundle.isAvailable, isFalse);
      expect(
        sources.resolutionSummary.unresolvedSources,
        contains('releaseEvidence'),
      );
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('verification request is always injected from evaluation request',
        () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(sources.verificationRequest.isAvailable, isTrue);
      expect(
        sources.verificationRequest.resolutionMode,
        CryptographicTrustSourceResolutionMode.injected,
      );
      expect(
        sources.verificationRequest.resolvedArtifact!.requestId,
        request.verificationRequest.requestId,
      );
    });

    test('injected trust policy wins over registry lookup', () async {
      final injected = ArtifactSignatureTrustPolicyV1.create().copyWith(
        description: 'injected-policy',
      );
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: injected,
      );

      expect(sources.trustPolicy.isAvailable, isTrue);
      expect(
        sources.trustPolicy.resolutionMode,
        CryptographicTrustSourceResolutionMode.injected,
      );
      expect(
        sources.trustPolicy.resolvedArtifact!.description,
        'injected-policy',
      );
    });

    test('project mismatch adds compatibility hint without evaluate', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle().copyWith(
        metadata: ReleaseEvidenceTestFixtures.validBundle()
            .metadata
            .copyWith(projectId: 'other-project'),
      );
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        releaseEvidenceBundle: bundle,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.compatibilityHints.any((h) => h.contains('Project mismatch')),
        isTrue,
      );
      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });

    test('partial resolution summary when some sources unresolved', () async {
      reProvider.loaded = null;
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        metadata: const {'releaseEvidenceBundleId': 'missing'},
      );

      final sources = await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.resolutionSummary.status,
        CryptographicTrustSourceResolutionStatus.partial,
      );
    });

    test('resolver never calls upstream evaluate or publish', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
        releaseSupplyChainSnapshot:
            ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
        useLatest: true,
        metadata: const {
          'releaseEvidenceBundleId': 'id-1',
          'releaseSupplyChainSnapshotId': 'id-2',
          'cicdIntegrationSnapshotId': 'id-3',
        },
      );

      await resolver.resolveAll(
        request,
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expectUpstreamCountersZero(reProvider, rscProvider, cicdProvider);
    });
  });
}

void expectUpstreamCountersZero(
  FakeReleaseEvidenceProviderForCryptographicTrust reProvider,
  FakeReleaseSupplyChainProviderForCryptographicTrust rscProvider,
  FakeCicdIntegrationProviderForCryptographicTrust cicdProvider,
) {
  expect(reProvider.evaluateCalls, 0);
  expect(reProvider.evaluateAndPublishCalls, 0);
  expect(reProvider.publishCalls, 0);
  expect(rscProvider.evaluateCalls, 0);
  expect(rscProvider.evaluateAndPublishCalls, 0);
  expect(rscProvider.publishCalls, 0);
  expect(cicdProvider.evaluateCalls, 0);
  expect(cicdProvider.evaluateAndPublishCalls, 0);
  expect(cicdProvider.publishCalls, 0);
}
