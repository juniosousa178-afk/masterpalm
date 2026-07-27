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
  group('Cryptographic Trust algorithm registry audit', () {
    test('default registry resolves digest provider', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.resolveDigestProvider(Sha256DigestProvider.defaultAlgorithmId),
        isNotNull,
      );
    });

    test('default registry resolves ed25519 verifier', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.resolveSignatureVerifier(
          algorithmId: Ed25519SignatureVerifier.defaultAlgorithmId,
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
        ),
        isNotNull,
      );
    });

    test('signer registration available when includeSigner true', () {
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
        isNotNull,
      );
    });

    test('duplicate registration throws conflict', () {
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

    test('frozen registry rejects new registration', () {
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
            keyType: CryptographicKeyType.ed25519,
            format: CryptographicSignatureFormat.raw,
            signer: Ed25519Signer(),
          ),
        ),
        throwsA(isA<CryptographicTrustRegistryFrozenException>()),
      );
    });

    test('unknown algorithm resolution returns null', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      expect(
        registry.resolveDigestProvider('unknown-v99'),
        isNull,
      );
    });
  });
}
