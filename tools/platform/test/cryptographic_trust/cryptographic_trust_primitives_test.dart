import 'dart:convert';

import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signer.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signature_verifier.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/sha256_digest_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/key_material/opaque_cryptographic_signing_key_handle.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust primitives', () {
    const provider = Sha256DigestProvider();

    test('SHA-256 empty string known vector', () {
      final digest = provider.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadEmpty,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'empty',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Empty);
    });

    test('SHA-256 abc known vector', () {
      final digest = provider.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'abc',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Abc);
    });

    test('SHA-256 long known vector', () {
      final payload = utf8.encode(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      );
      final digest = provider.computeDigest(
        subjectBytes: payload,
        descriptor: CryptographicTrustOperationalFixtures.sha256Descriptor(),
        subjectId: 'long',
      );
      expect(digest.value, CryptographicTrustOperationalFixtures.sha256Long);
    });

    test('SHA-256 rejects unsupported algorithm id', () {
      expect(
        () => provider.computeDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          descriptor: const CryptographicDigestDescriptor(
            algorithm: CryptographicDigestAlgorithm.sha256,
            algorithmId: 'sha512-v1',
            outputSizeBits: 512,
          ),
          subjectId: 'abc',
        ),
        throwsUnsupportedError,
      );
    });

    group('Ed25519 sign/verify', () {
      late InMemoryEd25519SigningKeyProvider keyProvider;
      late InMemoryEd25519SigningKeyHandle handle;
      late Ed25519Signer signer;
      late Ed25519SignatureVerifier verifier;

      setUp(() async {
        await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
        keyProvider = InMemoryEd25519SigningKeyProvider()
          ..registerKeyPair(
            CryptographicTrustOperationalFixtures.signingKeyId,
            await CryptographicTrustOperationalFixtures.testKeyPair(),
          );
        final resolution = keyProvider.resolveSigningHandle(
          await CryptographicTrustOperationalFixtures.signingKeyReference(),
        );
        handle = resolution.handle! as InMemoryEd25519SigningKeyHandle;
        signer = Ed25519Signer();
        verifier = Ed25519SignatureVerifier();
      });

      test('sign then verify succeeds with same payload bytes', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final signed = await signer.signDigest(
          digestBytes: payload,
          signingKeyHandle: handle,
          descriptor: CryptographicTrustTestFixtures.validSignatureDescriptor(),
          signatureId: 'sig-primitive-001',
          subjectId: 'subject-art-001',
        );
        expect(signed.outcome, CryptographicPrimitiveOutcome.valid);
        final envelope =
            (await CryptographicTrustOperationalFixtures.signedEnvelope(
                    payload))
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

      test('tampered payload fails verification', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final material =
            await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
        final verified = await verifier.verifySignature(
          subjectBytes: utf8.encode('abcd'),
          envelope: envelope,
          publicKeyMaterial: material,
        );
        expect(verified.outcome, CryptographicPrimitiveOutcome.invalid);
      });

      test('tampered signature fails verification', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final tampered = envelope.copyWith(
          signatureValue: base64Encode(List<int>.filled(64, 0xAB)),
        );
        final material =
            await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
        final verified = await verifier.verifySignature(
          subjectBytes: payload,
          envelope: tampered,
          publicKeyMaterial: material,
        );
        expect(verified.outcome, CryptographicPrimitiveOutcome.invalid);
      });

      test('wrong public key fails verification', () async {
        final payload = CryptographicTrustOperationalFixtures.payloadAbc;
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
        final otherKey = await InMemoryEd25519SigningKeyProvider()
            .generateKeyPair('other-key');
        final wrongMaterial = await publicKeyMaterialFromKeyPair(
          keyId: 'other-key',
          keyPair: otherKey,
        );
        final verified = await verifier.verifySignature(
          subjectBytes: payload,
          envelope: envelope,
          publicKeyMaterial: wrongMaterial,
        );
        expect(verified.outcome, CryptographicPrimitiveOutcome.invalid);
      });

      test('unsupported algorithm descriptor returns algorithmMismatch on sign',
          () async {
        final signed = await signer.signDigest(
          digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          signingKeyHandle: handle,
          descriptor: const CryptographicSignatureDescriptor(
            algorithm: CryptographicSignatureAlgorithm.rsaPss,
            algorithmId: 'rsa-pss-v1',
            keyType: CryptographicKeyType.rsa,
            format: CryptographicSignatureFormat.raw,
          ),
          signatureId: 'sig-unsupported',
          subjectId: 'subject-art-001',
        );
        expect(signed.outcome, CryptographicPrimitiveOutcome.algorithmMismatch);
      });

      test(
          'unsupported algorithm descriptor returns algorithmMismatch on verify',
          () async {
        final envelope =
            await CryptographicTrustOperationalFixtures.signedEnvelope(
          CryptographicTrustOperationalFixtures.payloadAbc,
        ).then(
          (e) => e.copyWith(
            signatureDescriptor: const CryptographicSignatureDescriptor(
              algorithm: CryptographicSignatureAlgorithm.rsaPss,
              algorithmId: 'rsa-pss-v1',
              keyType: CryptographicKeyType.rsa,
              format: CryptographicSignatureFormat.raw,
            ),
          ),
        );
        final material =
            await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
        final verified = await verifier.verifySignature(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          envelope: envelope,
          publicKeyMaterial: material,
        );
        expect(
            verified.outcome, CryptographicPrimitiveOutcome.algorithmMismatch);
      });

      test('opaque signing handle toString does not expose key bytes', () {
        final text = handle.toString();
        expect(text, contains('OpaqueCryptographicSigningKeyHandle'));
        expect(text, isNot(contains('SimpleKeyPair')));
      });
    });
  });
}
