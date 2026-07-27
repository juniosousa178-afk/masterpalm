import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust source resolver audit', () {
    late CryptographicTrustTestStack stack;

    setUp(() {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
    });

    test('injected release evidence wins over byId and latest', () async {
      final injected = ReleaseEvidenceTestFixtures.validBundle();
      stack.releaseEvidenceProvider.loaded = injected.copyWith(
        metadata: injected.metadata.copyWith(bundleId: 'stored-id'),
      );
      stack.releaseEvidenceProvider.latestBundle = injected;

      final sources = await stack.sourceResolver.resolveAll(
        verifiedScenarioRequest(releaseEvidenceBundle: injected),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );

      expect(
        sources.releaseEvidenceBundle.resolutionMode,
        CryptographicTrustSourceResolutionMode.injected,
      );
      expect(sources.releaseEvidenceBundle.resolvedArtifact, injected);
    });

    test('byId resolves when injected absent', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      stack.releaseEvidenceProvider.loaded = bundle;
      final sources = await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: {'releaseEvidenceBundleId': bundle.metadata.bundleId},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(sources.releaseEvidenceBundle.isAvailable, isTrue);
      expect(
        sources.releaseEvidenceBundle.resolutionMode,
        CryptographicTrustSourceResolutionMode.byId,
      );
    });

    test('latest only when useLatest is true', () async {
      stack.releaseEvidenceProvider.latestBundle =
          ReleaseEvidenceTestFixtures.validBundle();
      final withLatest =
          CryptographicTrustOperationalFixtures.evaluationRequest(
        useLatest: true,
      );
      final withoutLatest = withLatest.copyWith(useLatest: false);

      final resolvedLatest = await stack.sourceResolver.resolveAll(withLatest);
      final resolvedNone = await stack.sourceResolver.resolveAll(withoutLatest);

      expect(stack.releaseEvidenceProvider.latestCalls, 1);
      expect(resolvedLatest.releaseEvidenceBundle.isAvailable, isTrue);
      expect(
        resolvedNone.releaseEvidenceBundle.state,
        CryptographicTrustSourceState.notRequested,
      );
    });

    test('missing byId does not fall back to latest implicitly', () async {
      stack.releaseEvidenceProvider.latestBundle =
          ReleaseEvidenceTestFixtures.validBundle();
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: const {'releaseEvidenceBundleId': 'missing-bundle'},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseEvidenceProvider.latestCalls, 0);
    });

    test('resolver never calls upstream evaluate or publish', () async {
      await stack.sourceResolver.resolveAll(
        verifiedScenarioRequest(
          releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
          releaseSupplyChainSnapshot:
              ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
      expect(stack.releaseEvidenceProvider.evaluateAndPublishCalls, 0);
      expect(stack.releaseEvidenceProvider.publishCalls, 0);
      expect(stack.releaseSupplyChainProvider.evaluateCalls, 0);
      expect(stack.cicdIntegrationProvider.evaluateCalls, 0);
    });

    test('injected upstream artifacts skip provider latest', () async {
      stack.releaseEvidenceProvider.latestBundle =
          ReleaseEvidenceTestFixtures.validBundle();
      await stack.sourceResolver.resolveAll(
        verifiedScenarioRequest(
          releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseEvidenceProvider.latestCalls, 0);
    });
  });
}
