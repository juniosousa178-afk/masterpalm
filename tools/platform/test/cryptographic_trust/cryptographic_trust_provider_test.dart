import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/interfaces/cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('PlatformCryptographicTrustProvider', () {
    late CryptographicTrustTestStack stack;
    late CryptographicTrustProvider provider;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      provider = stack.provider;
      await stack.registerTestKeys();
    });

    test('evaluate returns evaluation result without persisting', () async {
      final result = await provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.evaluationId,
          CryptographicTrustOperationalFixtures.evaluationId);
      expect(result.metadata['noReleaseAuthorization'], 'true');
      expect(await stack.store.count(), 0);
    });

    test('evaluateAndPublish persists snapshot once', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final first = await provider.evaluateAndPublish(request);
      expect(first.snapshot, isNotNull);
      expect(await stack.store.count(), 1);

      final second = await provider.evaluateAndPublish(request);
      expect(
        second.snapshot!.metadata.cryptographicTrustSnapshotId,
        first.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
      expect(await stack.store.count(), 1);
    });

    test('publish stores snapshot directly', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await provider.publish(snapshot);
      final loaded = await provider.load(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded?.fingerprint, snapshot.fingerprint);
    });

    test('load returns null for missing snapshot', () async {
      expect(await provider.load('missing-id'), isNull);
    });

    test('latest returns published snapshot', () async {
      await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final latest = await provider.latest(
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
      );
      expect(latest, isNotNull);
    });

    test('invalidate removes snapshot', () async {
      final published = await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final id = published.snapshot!.metadata.cryptographicTrustSnapshotId;
      await provider.invalidate(id);
      expect(await provider.load(id), isNull);
    });

    test('invalidate missing snapshot throws not found', () async {
      expect(
        () => provider.invalidate('missing-id'),
        throwsA(isA<CryptographicTrustNotFoundException>()),
      );
    });

    test('evaluate throws when policy not found', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        policyReference: const CryptographicTrustPolicyReference(
          policyId: 'missing-policy',
          policyVersion: 1,
          status: CryptographicPolicyStatus.active,
          explicitSelection: true,
        ),
      );
      expect(
        () => provider.evaluate(request),
        throwsA(isA<CryptographicTrustPolicyNotFoundException>()),
      );
    });

    test('computeDigest returns computed digest for payload', () async {
      final digest = await provider.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustTestFixtures.validDigest().copyWith(
          value: CryptographicTrustOperationalFixtures.sha256Abc,
        ),
      );
      expect(digest?.value, CryptographicTrustOperationalFixtures.sha256Abc);
    });

    test('verifySignature uses signature verification service', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await provider.verifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result?.status, CryptographicVerificationStatus.verified);
      expect(result?.metadata['noReleaseAuthorization'], 'true');
    });

    test('sign produces envelope when signing configured', () async {
      final signingStack =
          CryptographicTrustOperationalFixtures.createTestStack(
              includeSigner: true);
      await signingStack.registerTestKeys();
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final template = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final digest = await signingStack.provider.computeDigest(
        subjectBytes: payload,
        descriptor: CryptographicTrustTestFixtures.validDigest(),
      );
      final result = await signingStack.provider.sign(
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        digestBytes: payload,
        template: template.copyWith(subjectDigest: digest!),
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
      expect(result.envelope, isNotNull);
    });

    test('evaluate resolves candidate policy with explicit reference',
        () async {
      final result = await provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          policyReference: const CryptographicTrustPolicyReference(
            policyId: ArtifactSignatureTrustPolicyV1.policyId,
            policyVersion: 1,
            status: CryptographicPolicyStatus.candidate,
            explicitSelection: true,
          ),
        ),
      );
      expect(result.policyReference?.explicitSelection, isTrue);
      expect(result.policyReference?.policyId,
          ArtifactSignatureTrustPolicyV1.policyId);
    });
  });
}
