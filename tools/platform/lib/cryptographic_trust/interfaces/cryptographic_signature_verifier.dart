import '../../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../key_material/cryptographic_public_key_material.dart';

/// Result of a signature verification primitive invocation.
class CryptographicSignatureVerificationPrimitiveResult {
  const CryptographicSignatureVerificationPrimitiveResult({
    required this.outcome,
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final String? message;
}

/// Vendor-neutral signature verification contract.
abstract class CryptographicSignatureVerifier {
  String get algorithmId;

  Set<CryptographicProviderCapability> get capabilities;

  Future<CryptographicSignatureVerificationPrimitiveResult> verifySignature({
    required List<int> subjectBytes,
    required CryptographicSignatureEnvelope envelope,
    required CryptographicPublicKeyMaterial publicKeyMaterial,
  });
}
