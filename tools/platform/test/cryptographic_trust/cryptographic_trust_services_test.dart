import 'package:masterpalm_platform/cryptographic_trust/cryptographic_attestation_verification_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_verification_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signing_service.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust services', () {
    late CryptographicTrustTestStack stack;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack(
        includeSigner: true,
      );
      await stack.registerTestKeys();
    });

    group('CryptographicDigestService', () {
      late CryptographicDigestService service;

      setUp(() {
        service = CryptographicDigestService(
          algorithmRegistry: stack.algorithmRegistry,
        );
      });

      test('computeDigest returns valid outcome for abc payload', () {
        final declared = CryptographicTrustTestFixtures.validDigest().copyWith(
          value: CryptographicTrustOperationalFixtures.sha256Abc,
        );
        final result = service.computeDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          declaredDigest: declared,
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.valid);
        expect(result.computedDigest!.value,
            CryptographicTrustOperationalFixtures.sha256Abc);
      });

      test('compareDigest detects mismatch', () {
        final declared = CryptographicTrustTestFixtures.validDigest().copyWith(
          value: 'deadbeef' * 8,
        );
        final result = service.compareDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          declaredDigest: declared,
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.invalid);
        expect(
          result.issues.any((i) => i.code == 'CT_DIGEST_VALUE_MISMATCH'),
          isTrue,
        );
      });

      test('computeDigest rejects empty payload bytes', () {
        final result = service.computeDigest(
          subjectBytes: const [],
          declaredDigest: CryptographicTrustTestFixtures.validDigest(),
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.malformed);
      });

      test('computeDigest returns unsupported for unknown algorithm', () {
        final result = service.computeDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          declaredDigest: CryptographicTrustTestFixtures.validDigest().copyWith(
            descriptor: const CryptographicDigestDescriptor(
              algorithm: CryptographicDigestAlgorithm.sha256,
              algorithmId: 'unknown-v1',
              outputSizeBits: 256,
            ),
          ),
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.unsupported);
      });
    });

    group('CryptographicSigningService', () {
      late CryptographicSigningService service;

      setUp(() {
        service = CryptographicSigningService(
          algorithmRegistry: stack.algorithmRegistry,
          signingKeyProvider: stack.signingKeyProvider,
        );
      });

      test('signDigest produces valid envelope', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final subject =
            await CryptographicTrustOperationalFixtures.signedSubject(payload);
        final digest = subject.digest!;
        final result = await service.signDigest(
          digestBytes: payload,
          subjectDigest: digest,
          subject: subject,
          signatureDescriptor:
              CryptographicTrustTestFixtures.validSignatureDescriptor(),
          keyReference:
              await CryptographicTrustOperationalFixtures.signingKeyReference(),
          signatureId: 'sig-service-001',
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.valid);
        expect(result.envelope, isNotNull);
      });

      test('signDigest unavailable without signing key provider', () async {
        final serviceWithoutKeys = CryptographicSigningService(
          algorithmRegistry: stack.algorithmRegistry,
        );
        final result = await serviceWithoutKeys.signDigest(
          digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          subjectDigest: CryptographicTrustTestFixtures.validDigest(),
          subject: CryptographicTrustTestFixtures.validSubject(),
          signatureDescriptor:
              CryptographicTrustTestFixtures.validSignatureDescriptor(),
          keyReference: CryptographicTrustTestFixtures.validKeyReference(),
          signatureId: 'sig-unavailable',
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.unavailable);
      });
    });

    group('CryptographicSignatureVerificationService', () {
      late CryptographicSignatureVerificationService service;

      setUp(() {
        service = CryptographicSignatureVerificationService(
          algorithmRegistry: stack.algorithmRegistry,
          publicKeyResolver: stack.publicKeyResolver,
        );
      });

      test('verifySignature succeeds for valid signed envelope', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final result = await service.verifySignature(
          subjectBytes: payload,
          envelope: envelope,
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.valid);
        expect(result.trustLevel, CryptographicTrustLevel.none);
        expect(
          service.mapOutcomeToVerificationStatus(result.outcome),
          CryptographicVerificationStatus.verified,
        );
      });

      test('verifySignature fails for tampered payload', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final result = await service.verifySignature(
          subjectBytes: const [1, 2, 3],
          envelope: envelope,
        );
        expect(result.outcome, isNot(CryptographicPrimitiveOutcome.valid));
      });

      test('verifySignature rejects revoked key', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final result = await service.verifySignature(
          subjectBytes: payload,
          envelope: envelope,
          revocations: [CryptographicTrustTestFixtures.validRevocationRecord()],
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.revoked);
      });

      test('verifySignature unavailable without public key resolver', () async {
        final serviceWithoutResolver =
            CryptographicSignatureVerificationService(
          algorithmRegistry: stack.algorithmRegistry,
        );
        final result = await serviceWithoutResolver.verifySignature(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          envelope: CryptographicTrustTestFixtures.validSignatureEnvelope(),
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.unavailable);
      });
    });

    group('CryptographicAttestationVerificationService', () {
      late CryptographicAttestationVerificationService service;

      setUp(() {
        service = CryptographicAttestationVerificationService(
          signatureVerificationService:
              CryptographicSignatureVerificationService(
            algorithmRegistry: stack.algorithmRegistry,
            publicKeyResolver: stack.publicKeyResolver,
          ),
        );
      });

      test('verifyAttestation validates structure without executing claims',
          () async {
        final attestation =
            CryptographicTrustTestFixtures.validAttestationStatement();
        final result =
            await service.verifyAttestation(attestation: attestation);
        expect(result.structuralOutcome, CryptographicPrimitiveOutcome.valid);
        expect(result.trustLevel, CryptographicTrustLevel.none);
      });

      test('verifyAttestation fails structural validation for empty subjects',
          () async {
        final attestation =
            CryptographicTrustTestFixtures.validAttestationStatement().copyWith(
          subjects: const [],
        );
        final result =
            await service.verifyAttestation(attestation: attestation);
        expect(result.structuralOutcome,
            isNot(CryptographicPrimitiveOutcome.valid));
      });
    });
  });
}
