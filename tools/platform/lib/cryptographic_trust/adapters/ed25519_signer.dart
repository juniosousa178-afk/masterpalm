import 'package:cryptography/dart.dart';

import '../../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../interfaces/cryptographic_signer.dart';
import '../key_material/opaque_cryptographic_signing_key_handle.dart';
import 'in_memory_ed25519_signing_key_provider.dart';

/// Ed25519 signer using package:cryptography.
class Ed25519Signer implements CryptographicSigner {
  Ed25519Signer({DartEd25519? algorithm})
      : _algorithm = algorithm ?? DartEd25519();

  final DartEd25519 _algorithm;

  static const defaultAlgorithmId = 'ed25519-v1';

  @override
  String get algorithmId => defaultAlgorithmId;

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.signing,
      };

  @override
  Future<CryptographicSigningPrimitiveResult> signDigest({
    required List<int> digestBytes,
    required OpaqueCryptographicSigningKeyHandle signingKeyHandle,
    required CryptographicSignatureDescriptor descriptor,
    required String signatureId,
    required String subjectId,
  }) async {
    if (descriptor.algorithmId != defaultAlgorithmId &&
        descriptor.algorithm != CryptographicSignatureAlgorithm.ed25519) {
      return const CryptographicSigningPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.algorithmMismatch,
        message: 'signature descriptor algorithm mismatch',
      );
    }

    final keyPair = inMemoryEd25519KeyPairFromHandle(signingKeyHandle);
    if (keyPair == null) {
      return const CryptographicSigningPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        message: 'unsupported signing key handle',
      );
    }

    try {
      final signature = await _algorithm.sign(
        digestBytes,
        keyPair: keyPair,
      );
      return CryptographicSigningPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.valid,
        signatureBytes: List<int>.from(signature.bytes),
      );
    } catch (error) {
      return CryptographicSigningPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        message: error.toString(),
      );
    }
  }
}
