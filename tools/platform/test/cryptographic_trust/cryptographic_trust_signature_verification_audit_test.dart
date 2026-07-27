import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_verification_service.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust signature verification audit', () {
    late CryptographicTrustTestStack stack;
    late CryptographicSignatureVerificationService service;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      service = CryptographicSignatureVerificationService(
        algorithmRegistry: stack.algorithmRegistry,
        publicKeyResolver: stack.publicKeyResolver,
      );
    });

    test('valid signature verifies with verified status mapping', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await service.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
      expect(
        service.mapOutcomeToVerificationStatus(result.outcome),
        CryptographicVerificationStatus.verified,
      );
    });

    test('tampered signature fails verification', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          (await CryptographicTrustOperationalFixtures.signedEnvelope(payload))
              .copyWith(signatureValue: 'AAAA');
      final result = await service.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
      );
      expect(result.outcome, isNot(CryptographicPrimitiveOutcome.valid));
    });

    test('revoked key returns revoked outcome', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await service.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        revocations: [CryptographicTrustTestFixtures.validRevocationRecord()],
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.revoked);
    });

    test('provider verifySignature never sets releaseAuthorized', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await stack.provider.verifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result?.toJson().containsKey('releaseAuthorized'), isFalse);
      expect(result?.metadata['noReleaseAuthorization'], 'true');
    });

    test('missing public key returns keyNotFound outcome', () async {
      final emptyStack =
          CryptographicTrustOperationalFixtures.createTestStack();
      final emptyService = CryptographicSignatureVerificationService(
        algorithmRegistry: emptyStack.algorithmRegistry,
        publicKeyResolver: emptyStack.publicKeyResolver,
      );
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await emptyService.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.keyNotFound);
    });
  });
}
