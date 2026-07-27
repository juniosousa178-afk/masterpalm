import 'package:masterpalm_platform/cryptographic_trust/cryptographic_attestation_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_attestation_verification_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_verification_service.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust attestation audit', () {
    late CryptographicTrustTestStack stack;
    late CryptographicAttestationVerificationService attestationService;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      attestationService = CryptographicAttestationVerificationService(
        signatureVerificationService: CryptographicSignatureVerificationService(
          algorithmRegistry: stack.algorithmRegistry,
          publicKeyResolver: stack.publicKeyResolver,
        ),
      );
    });

    test('attestation validator accepts valid statement', () {
      const validator = CryptographicAttestationValidator();
      final statement =
          CryptographicTrustTestFixtures.validAttestationStatement();
      expect(validator.validate(statement).isValid, isTrue);
    });

    test('attestation validator rejects empty attestationId', () {
      const validator = CryptographicAttestationValidator();
      final statement =
          CryptographicTrustTestFixtures.validAttestationStatement().copyWith(
        attestationId: '',
      );
      expect(validator.validate(statement).isValid, isFalse);
    });

    test('attestation verification service validates structural statement',
        () async {
      final statement =
          CryptographicTrustTestFixtures.validAttestationStatement();
      final result = await attestationService.verifyAttestation(
        attestation: statement,
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(
        result.structuralOutcome,
        isNot(CryptographicPrimitiveOutcome.malformed),
      );
    });

    test('snapshot includes attestations after evaluation', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot?.attestations, isNotEmpty);
    });

    test('attestation comparable excludes issuedAt timestamp', () {
      final statement =
          CryptographicTrustTestFixtures.validAttestationStatement();
      expect(statement.toComparableJson().containsKey('issuedAt'), isFalse);
    });
  });
}
