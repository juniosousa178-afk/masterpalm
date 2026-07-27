import '../../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../key_material/opaque_cryptographic_signing_key_handle.dart';

/// Result of a signing primitive invocation.
class CryptographicSigningPrimitiveResult {
  const CryptographicSigningPrimitiveResult({
    required this.outcome,
    this.signatureBytes,
    this.envelope,
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final List<int>? signatureBytes;
  final CryptographicSignatureEnvelope? envelope;
  final String? message;
}

/// Vendor-neutral signing contract.
abstract class CryptographicSigner {
  String get algorithmId;

  Set<CryptographicProviderCapability> get capabilities;

  Future<CryptographicSigningPrimitiveResult> signDigest({
    required List<int> digestBytes,
    required OpaqueCryptographicSigningKeyHandle signingKeyHandle,
    required CryptographicSignatureDescriptor descriptor,
    required String signatureId,
    required String subjectId,
  });
}
