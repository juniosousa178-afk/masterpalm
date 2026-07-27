import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signing_service.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust signing audit', () {
    late CryptographicTrustTestStack stack;
    late CryptographicSigningService service;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack(
        includeSigner: true,
      );
      await stack.registerTestKeys();
      service = CryptographicSigningService(
        algorithmRegistry: stack.algorithmRegistry,
        signingKeyProvider: stack.signingKeyProvider,
      );
    });

    test('signDigest produces valid envelope for abc payload', () async {
      final subject = await CryptographicTrustOperationalFixtures.signedSubject(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      final result = await service.signDigest(
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        subjectDigest: subject.digest!,
        subject: subject,
        signatureDescriptor:
            CryptographicTrustTestFixtures.validSignatureDescriptor(),
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        signatureId: 'audit-sign-001',
        signedAt: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
      expect(result.envelope?.signatureValue, isNotEmpty);
    });

    test('signDigest rejects unknown key reference', () async {
      final subject = await CryptographicTrustOperationalFixtures.signedSubject(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      final result = await service.signDigest(
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        subjectDigest: subject.digest!,
        subject: subject,
        signatureDescriptor:
            CryptographicTrustTestFixtures.validSignatureDescriptor(),
        keyReference: CryptographicTrustTestFixtures.validKeyReference(
          keyId: 'missing-key',
        ),
        signatureId: 'audit-sign-002',
        signedAt: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.outcome, isNot(CryptographicPrimitiveOutcome.valid));
    });

    test('signed envelope json excludes private key material', () async {
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      expect(envelope.toJson().containsKey('privateKey'), isFalse);
      expect(envelope.toJson().containsKey('seed'), isFalse);
    });

    test('provider sign delegates to signing service', () async {
      final template = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final result = await stack.provider.sign(
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        template: template,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
    });

    test('signing without configured key provider returns unavailable',
        () async {
      final noSignerStack =
          CryptographicTrustOperationalFixtures.createTestStack();
      final result = await noSignerStack.provider.sign(
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        template: CryptographicTrustTestFixtures.validSignatureEnvelope(),
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.unavailable);
    });
  });
}
