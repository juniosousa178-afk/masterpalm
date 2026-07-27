/// Normative Cryptographic Trust adapter paths analyzed by the compatibility gate.
///
/// Used to ensure adapters are not silently excluded from package analysis.
class GuardianCryptographicAdapterPaths {
  const GuardianCryptographicAdapterPaths._();

  static const adapterRelativePaths = <String>[
    'lib/cryptographic_trust/adapters/sha256_digest_provider.dart',
    'lib/cryptographic_trust/adapters/ed25519_signature_verifier.dart',
    'lib/cryptographic_trust/adapters/ed25519_signer.dart',
    'lib/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart',
    'lib/cryptographic_trust/adapters/in_memory_public_key_resolver.dart',
    'lib/cryptographic_trust/key_material/cryptographic_public_key_material.dart',
    'lib/cryptographic_trust/key_material/opaque_cryptographic_signing_key_handle.dart',
    'lib/cryptographic_trust/cryptographic_algorithm_registry.dart',
    'lib/cryptographic_trust/cryptographic_signing_service.dart',
    'lib/cryptographic_trust/cryptographic_signature_verification_service.dart',
  ];

  static const requiredPackageImports = <String>{
    'package:crypto/crypto.dart',
    'package:cryptography/cryptography.dart',
    'package:cryptography/dart.dart',
  };
}
