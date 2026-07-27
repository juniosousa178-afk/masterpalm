import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/key_material/opaque_cryptographic_signing_key_handle.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust key material audit', () {
    test('public key material excludes private bytes', () async {
      final material =
          await CryptographicTrustOperationalFixtures.testPublicKeyMaterial();
      expect(material.toJson().containsKey('privateKey'), isFalse);
      expect(material.toJson().containsKey('seed'), isFalse);
      expect(material.publicKeyBytes, isNotEmpty);
    });

    test('opaque handle toString excludes key pair object', () async {
      await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
      final handle = InMemoryEd25519SigningKeyHandle(
        keyId: 'audit-key',
        keyPair: await CryptographicTrustOperationalFixtures.testKeyPair(),
      );
      final text = handle.toString();
      expect(text, contains('keyId: audit-key'));
      expect(text, isNot(contains('SimpleKeyPair')));
    });

    test('signing key provider resolves registered handle', () async {
      await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
      final provider = InMemoryEd25519SigningKeyProvider()
        ..registerKeyPair(
          CryptographicTrustOperationalFixtures.signingKeyId,
          await CryptographicTrustOperationalFixtures.testKeyPair(),
        );
      final resolution = provider.resolveSigningHandle(
        await CryptographicTrustOperationalFixtures.signingKeyReference(),
      );
      expect(resolution.handle, isA<OpaqueCryptographicSigningKeyHandle>());
    });

    test('public key fingerprint stable across resolutions', () async {
      final fp1 = await CryptographicTrustOperationalFixtures
          .testPublicKeyFingerprint();
      final fp2 = await CryptographicTrustOperationalFixtures
          .testPublicKeyFingerprint();
      expect(fp1, fp2);
    });

    test('unregistered key resolution returns unresolved handle', () async {
      final provider = InMemoryEd25519SigningKeyProvider();
      final resolution = provider.resolveSigningHandle(
        await CryptographicTrustOperationalFixtures.signingKeyReference(),
      );
      expect(resolution.handle, isNull);
    });
  });
}
