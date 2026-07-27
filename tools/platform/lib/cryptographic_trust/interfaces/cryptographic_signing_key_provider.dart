import '../../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../key_material/opaque_cryptographic_signing_key_handle.dart';

/// Result of signing key handle resolution.
class CryptographicSigningKeyResolutionResult {
  const CryptographicSigningKeyResolutionResult({
    required this.outcome,
    this.handle,
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final OpaqueCryptographicSigningKeyHandle? handle;
  final String? message;
}

/// Vendor-neutral signing key handle resolution contract.
abstract class CryptographicSigningKeyProvider {
  Set<CryptographicProviderCapability> get capabilities;

  CryptographicSigningKeyResolutionResult resolveSigningHandle(
    CryptographicKeyReference keyReference,
  );
}
