import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signer.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signature_verifier.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/sha256_digest_provider.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

/// RFC 8032 / NIST SHA-256 vectors with independent verification paths.
void main() {
  group('Cryptographic Trust primitives audit', () {
    final sha256 = Sha256DigestProvider();
    final signer = Ed25519Signer();
    final verifier = Ed25519SignatureVerifier();

    test('NIST SHA-256 empty string vector', () {
      final digest = sha256.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadEmpty,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'nist-empty',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Empty);
    });

    test('NIST SHA-256 abc vector', () {
      final digest = sha256.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'nist-abc',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Abc);
    });

    test('NIST SHA-256 448-bit block vector', () {
      final payload = utf8.encode(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      );
      final digest = sha256.computeDigest(
        subjectBytes: payload,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'nist-long',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Long);
    });

    test('independent sha256 via crypto package matches provider', () {
      final digest = sha256.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'cross-check',
      );
      final independent = crypto.sha256.convert(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      expect(digest.value, independent.toString());
    });

    test('Ed25519 sign/verify independent roundtrip', () async {
      await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
      final keyPair = await CryptographicTrustOperationalFixtures.testKeyPair();
      final handle = InMemoryEd25519SigningKeyHandle(
        keyId: 'audit-key',
        keyPair: keyPair,
      );
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final signed = await signer.signDigest(
        digestBytes: payload,
        signingKeyHandle: handle,
        descriptor: CryptographicTrustTestFixtures.validSignatureDescriptor(),
        signatureId: 'audit-sig',
        subjectId: 'audit-subject',
      );
      expect(signed.outcome, CryptographicPrimitiveOutcome.valid);

      final envelope =
          (await CryptographicTrustOperationalFixtures.signedEnvelope(payload))
              .copyWith(signatureValue: base64Encode(signed.signatureBytes!));
      final material =
          await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
      final verified = await verifier.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        publicKeyMaterial: material,
      );
      expect(verified.outcome, CryptographicPrimitiveOutcome.valid);
    });

    test('Ed25519 tampered payload fails independent verification', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final material =
          await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
      final verified = await verifier.verifySignature(
        subjectBytes: utf8.encode('tampered'),
        envelope: envelope,
        publicKeyMaterial: material,
      );
      expect(verified.outcome, isNot(CryptographicPrimitiveOutcome.valid));
    });

    test('Ed25519 wrong public key fails verification', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final otherKey = await InMemoryEd25519SigningKeyProvider()
          .generateKeyPair('wrong-key');
      final wrongMaterial = await publicKeyMaterialFromKeyPair(
        keyId: 'wrong-key',
        keyPair: otherKey,
      );
      final verified = await verifier.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        publicKeyMaterial: wrongMaterial,
      );
      expect(verified.outcome, CryptographicPrimitiveOutcome.invalid);
    });

    test('SHA-256 rejects unsupported algorithm id', () {
      expect(
        () => sha256.computeDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          descriptor: const CryptographicDigestDescriptor(
            algorithm: CryptographicDigestAlgorithm.sha256,
            algorithmId: 'sha512-v1',
            outputSizeBits: 512,
          ),
          subjectId: 'bad-alg',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
