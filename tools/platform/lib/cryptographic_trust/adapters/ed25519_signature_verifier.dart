import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import '../../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../interfaces/cryptographic_signature_verifier.dart';
import '../key_material/cryptographic_public_key_material.dart';
import 'sha256_digest_provider.dart';

/// Ed25519 signature verifier using package:cryptography.
class Ed25519SignatureVerifier implements CryptographicSignatureVerifier {
  Ed25519SignatureVerifier({DartEd25519? algorithm})
      : _algorithm = algorithm ?? DartEd25519();

  final DartEd25519 _algorithm;

  static const defaultAlgorithmId = 'ed25519-v1';

  @override
  String get algorithmId => defaultAlgorithmId;

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.signatureVerification,
      };

  @override
  Future<CryptographicSignatureVerificationPrimitiveResult> verifySignature({
    required List<int> subjectBytes,
    required CryptographicSignatureEnvelope envelope,
    required CryptographicPublicKeyMaterial publicKeyMaterial,
  }) async {
    if (envelope.signatureDescriptor.algorithmId != defaultAlgorithmId &&
        envelope.signatureDescriptor.algorithm !=
            CryptographicSignatureAlgorithm.ed25519) {
      return const CryptographicSignatureVerificationPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.algorithmMismatch,
        message: 'signature descriptor algorithm mismatch',
      );
    }
    if (publicKeyMaterial.algorithmId != defaultAlgorithmId &&
        publicKeyMaterial.keyType != CryptographicKeyType.ed25519) {
      return const CryptographicSignatureVerificationPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.algorithmMismatch,
        message: 'public key algorithm mismatch',
      );
    }

    try {
      final signatureBytes = decodeSignatureValue(
        envelope.signatureValue,
        envelope.signatureEncoding,
      );
      final publicKey = SimplePublicKey(
        List<int>.from(publicKeyMaterial.publicKeyBytes),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        signatureBytes,
        publicKey: publicKey,
      );
      final valid = await _algorithm.verify(subjectBytes, signature: signature);
      return CryptographicSignatureVerificationPrimitiveResult(
        outcome: valid
            ? CryptographicPrimitiveOutcome.valid
            : CryptographicPrimitiveOutcome.invalid,
        message: valid ? null : 'signature verification failed',
      );
    } on FormatException catch (error) {
      return CryptographicSignatureVerificationPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.malformed,
        message: error.message,
      );
    } catch (error) {
      return CryptographicSignatureVerificationPrimitiveResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        message: error.toString(),
      );
    }
  }
}

List<int> decodeSignatureValue(String value, String encoding) {
  final trimmed = value.trim();
  switch (encoding) {
    case 'hex':
      return hexToBytes(trimmed);
    case 'base64':
      return base64.decode(trimmed);
    default:
      throw FormatException('unsupported signature encoding: $encoding');
  }
}
