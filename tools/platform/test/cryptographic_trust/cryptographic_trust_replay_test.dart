import 'dart:convert';

import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_identity_builder.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust replay', () {
    late CryptographicTrustTestStack stack;
    const serializer = CryptographicTrustCanonicalSerializer();
    const identity = CryptographicTrustIdentityBuilder();

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
    });

    test('re-evaluate same inputs yields identical snapshot fingerprint',
        () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final first = await stack.provider.evaluate(request);
      final second = await stack.provider.evaluate(request);

      expect(
        first.snapshot!.metadata.cryptographicTrustSnapshotId,
        second.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
      expect(first.snapshot!.fingerprint, second.snapshot!.fingerprint);
    });

    test('replay preserves component fingerprints', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final first = (await stack.provider.evaluate(request)).snapshot!;
      final second = (await stack.provider.evaluate(request)).snapshot!;

      expect(second.metadata.projectId, first.metadata.projectId);
      expect(second.metadata.releaseId, first.metadata.releaseId);
      expect(second.digests.length, first.digests.length);
      expect(second.signatures.length, first.signatures.length);
    });

    test('canonical serializer fingerprints are stable on replay', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final first = (await stack.provider.evaluate(request)).snapshot!;
      final second = (await stack.provider.evaluate(request)).snapshot!;

      expect(
        serializer.snapshotFingerprint(second),
        serializer.snapshotFingerprint(first),
      );
      expect(
        serializer.snapshotContentFingerprint(second),
        serializer.snapshotContentFingerprint(first),
      );
    });

    test('toJson/fromJson round-trip preserves snapshot identity', () async {
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      final restored = CryptographicTrustSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );

      expect(
        restored.metadata.cryptographicTrustSnapshotId,
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(restored.fingerprint, snapshot.fingerprint);
    });

    test('100 cycles json roundtrip preserve fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      final originalFp = serializer.snapshotFingerprint(snapshot);

      for (var i = 0; i < 100; i++) {
        final restored = CryptographicTrustSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(restored), originalFp);
      }
    });

    test('identity builder fingerprint stable across replay', () async {
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      final id1 = identity.buildCryptographicTrustIdFromSnapshot(snapshot);
      final id2 = identity.buildCryptographicTrustIdFromSnapshot(snapshot);
      expect(id1, id2);
      expect(id1, contains(snapshot.fingerprint));
    });

    group('scenario replays', () {
      test('01 verified snapshot scenario', () async {
        final result = await evaluateVerifiedScenario(stack: stack);
        expect(result.snapshot, isNotNull);
        expect(result.snapshot!.signatures, isNotEmpty);
      });

      test('02 partial resolution scenario', () async {
        final result = await evaluatePartialScenario(stack: stack);
        expect(
          result.sourceResolutionSummary?.status,
          CryptographicTrustSourceResolutionStatus.partial,
        );
      });

      test('03 failed verification scenario', () async {
        final result = await evaluateFailedScenario(stack: stack);
        expect(result.verificationResult?.status,
            isNot(CryptographicVerificationStatus.verified));
      });

      test('04 conflicting publish scenario', () async {
        final conflict = await publishConflictingScenario(stack: stack);
        expect(conflict, isNotNull);
      });

      test('05 upstream evidence present scenario', () async {
        final evidence = ReleaseEvidenceTestFixtures.validBundle();
        final result = await stack.provider.evaluate(
          verifiedScenarioRequest(releaseEvidenceBundle: evidence),
        );
        expect(result.sourceResolutionSummary?.resolvedSources, isNotEmpty);
      });

      test('06 upstream absent scenario', () async {
        final result = await stack.provider.evaluate(
          CryptographicTrustOperationalFixtures.evaluationRequest(),
        );
        expect(result.snapshot, isNotNull);
      });

      test('07 injected evidence preferred scenario', () async {
        final injected = ReleaseEvidenceTestFixtures.validBundle();
        final sources = await stack.sourceResolver.resolveAll(
          verifiedScenarioRequest(releaseEvidenceBundle: injected),
          injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
        );
        expect(sources.releaseEvidenceBundle.resolutionMode.name, 'injected');
      });

      test('08 byId evidence without evaluate scenario', () async {
        final bundle = ReleaseEvidenceTestFixtures.validBundle();
        stack.releaseEvidenceProvider.loaded = bundle;
        await stack.sourceResolver.resolveAll(
          CryptographicTrustOperationalFixtures.evaluationRequest(
            metadata: {'releaseEvidenceBundleId': bundle.metadata.bundleId},
          ),
          injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
        );
        expect(stack.releaseEvidenceProvider.loadCalls, 1);
        expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
      });

      test('09 useLatest evidence scenario', () async {
        stack.releaseEvidenceProvider.latestBundle =
            ReleaseEvidenceTestFixtures.validBundle();
        await stack.sourceResolver.resolveAll(
          CryptographicTrustOperationalFixtures.evaluationRequest(
              useLatest: true),
          injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
        );
        expect(stack.releaseEvidenceProvider.latestCalls, 1);
      });

      test('10 supply chain injected scenario', () async {
        final sc = ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
        final sources = await stack.sourceResolver.resolveAll(
          verifiedScenarioRequest(releaseSupplyChainSnapshot: sc),
          injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
        );
        expect(sources.releaseSupplyChainSnapshot.isAvailable, isTrue);
      });

      test('11 valid signature replay scenario', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final result = await stack.provider.verifySignature(
          envelope: envelope,
          subjectBytes: payload,
          projectId: CryptographicTrustOperationalFixtures.projectId,
        );
        expect(result?.status, CryptographicVerificationStatus.verified);
      });

      test('12 tampered signature replay scenario', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            (await CryptographicTrustOperationalFixtures.signedEnvelope(
                    payload))
                .copyWith(signatureValue: 'AAAA');
        final result = await stack.provider.verifySignature(
          envelope: envelope,
          subjectBytes: payload,
          projectId: CryptographicTrustOperationalFixtures.projectId,
        );
        expect(result?.status, isNot(CryptographicVerificationStatus.verified));
      });

      test('13 digest abc vector replay scenario', () async {
        final digest =
            await CryptographicTrustOperationalFixtures.digestForPayload(
          CryptographicTrustOperationalFixtures.payloadAbc,
        );
        expect(digest.value, CryptographicTrustOperationalFixtures.sha256Abc);
      });

      test('14 idempotent publish replay scenario', () async {
        final request =
            CryptographicTrustOperationalFixtures.evaluationRequest();
        await stack.provider.evaluateAndPublish(request);
        await stack.provider.evaluateAndPublish(request);
        expect(await stack.store.count(), 1);
      });

      test('15 no release authorization replay scenario', () async {
        final result = await evaluatePassingSnapshot(stack: stack);
        expect(result.metadata['noReleaseAuthorization'], 'true');
        expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
      });
    });
  });
}
