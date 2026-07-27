import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';

/// Result of transparency proof verification.
class CryptographicTransparencyProofVerificationResult {
  const CryptographicTransparencyProofVerificationResult({
    required this.outcome,
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final String? message;
}

/// Optional vendor-neutral transparency proof verification contract.
abstract class CryptographicTransparencyProofVerifier {
  String get logId;

  Set<CryptographicProviderCapability> get capabilities;

  CryptographicTransparencyProofVerificationResult verifyProof({
    required List<int> leafDigest,
    required List<int> proofBytes,
    required List<int> rootHash,
  });
}
