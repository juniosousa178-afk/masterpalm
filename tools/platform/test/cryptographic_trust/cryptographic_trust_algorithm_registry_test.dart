import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signer.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signature_verifier.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/sha256_digest_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_algorithm_registry.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('CryptographicAlgorithmRegistry', () {
    test('register stores digest provider', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry(
        freeze: false,
      );
      expect(
        registry.contains(
          operation: CryptographicPrimitiveOperation.computeDigest,
          algorithmId: Sha256DigestProvider.defaultAlgorithmId,
        ),
        isTrue,
      );
    });

    test('register stores signature verifier with key type and format', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry(
        freeze: false,
      );
      expect(
        registry.resolveSignatureVerifier(
          algorithmId: Ed25519SignatureVerifier.defaultAlgorithmId,
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
        ),
        isNotNull,
      );
    });

    test('register rejects duplicate algorithm key', () {
      final registry = CryptographicAlgorithmRegistry();
      registry.register(
        CryptographicAlgorithmRegistration(
          algorithmId: Sha256DigestProvider.defaultAlgorithmId,
          operation: CryptographicPrimitiveOperation.computeDigest,
          capabilities: const {CryptographicProviderCapability.digest},
          digestProvider: const Sha256DigestProvider(),
        ),
      );
      expect(
        () => registry.register(
          CryptographicAlgorithmRegistration(
            algorithmId: Sha256DigestProvider.defaultAlgorithmId,
            operation: CryptographicPrimitiveOperation.computeDigest,
            capabilities: const {CryptographicProviderCapability.digest},
            digestProvider: const Sha256DigestProvider(),
          ),
        ),
        throwsA(isA<CryptographicTrustAlgorithmConflictException>()),
      );
    });

    test('freeze prevents further registration', () {
      final registry = CryptographicAlgorithmRegistry()
        ..register(
          CryptographicAlgorithmRegistration(
            algorithmId: Sha256DigestProvider.defaultAlgorithmId,
            operation: CryptographicPrimitiveOperation.computeDigest,
            capabilities: const {CryptographicProviderCapability.digest},
            digestProvider: const Sha256DigestProvider(),
          ),
        )
        ..freeze();
      expect(
        () => registry.register(
          CryptographicAlgorithmRegistration(
            algorithmId: Ed25519Signer.defaultAlgorithmId,
            operation: CryptographicPrimitiveOperation.sign,
            capabilities: const {CryptographicProviderCapability.signing},
            signer: Ed25519Signer(),
          ),
        ),
        throwsA(isA<CryptographicTrustRegistryFrozenException>()),
      );
    });

    test('resolveDigestProvider returns registered provider', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.resolveDigestProvider(Sha256DigestProvider.defaultAlgorithmId),
        isA<Sha256DigestProvider>(),
      );
    });

    test('resolveSigner returns null when signer not registered', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.resolveSigner(
          algorithmId: Ed25519Signer.defaultAlgorithmId,
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
        ),
        isNull,
      );
    });

    test('resolveSigner returns signer when registered', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry(
        includeSigner: true,
      );
      expect(
        registry.resolveSigner(
          algorithmId: Ed25519Signer.defaultAlgorithmId,
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
        ),
        isA<Ed25519Signer>(),
      );
    });

    test('query filters by operation', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry(
        includeSigner: true,
      );
      final digestMatches = registry.query(
        operation: CryptographicPrimitiveOperation.computeDigest,
      );
      expect(digestMatches, hasLength(1));
      expect(digestMatches.first.algorithmId,
          Sha256DigestProvider.defaultAlgorithmId);
    });

    test('query filters by algorithmId', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry(
        includeSigner: true,
      );
      final matches =
          registry.query(algorithmId: Ed25519Signer.defaultAlgorithmId);
      expect(matches.length, greaterThanOrEqualTo(1));
    });

    test('lookup returns null for unknown algorithm', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.lookup(
          operation: CryptographicPrimitiveOperation.computeDigest,
          algorithmId: 'unknown-v1',
        ),
        isNull,
      );
    });
  });
}
