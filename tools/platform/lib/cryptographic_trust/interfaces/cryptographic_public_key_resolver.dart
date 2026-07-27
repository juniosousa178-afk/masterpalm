import '../../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../key_material/cryptographic_public_key_material.dart';

/// Result of public key resolution.
class CryptographicPublicKeyResolutionResult {
  const CryptographicPublicKeyResolutionResult({
    required this.outcome,
    this.publicKeyMaterial,
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final CryptographicPublicKeyMaterial? publicKeyMaterial;
  final String? message;
}

/// Vendor-neutral public key resolution contract.
abstract class CryptographicPublicKeyResolver {
  Set<CryptographicProviderCapability> get capabilities;

  CryptographicPublicKeyResolutionResult resolvePublicKey(
    CryptographicKeyReference keyReference,
  );
}
