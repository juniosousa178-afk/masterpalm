import 'package:cryptography/cryptography.dart';

import '../../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../interfaces/cryptographic_signing_key_provider.dart';
import '../key_material/cryptographic_public_key_material.dart';
import '../key_material/opaque_cryptographic_signing_key_handle.dart';
import 'sha256_digest_provider.dart';

/// Non-production in-memory Ed25519 signing key provider.
///
/// Intended for tests only. Dart does not guarantee complete memory zeroization.
class InMemoryEd25519SigningKeyProvider
    implements CryptographicSigningKeyProvider {
  InMemoryEd25519SigningKeyProvider({
    Map<String, SimpleKeyPair>? keyPairsById,
    Ed25519? algorithm,
  })  : _keyPairsById = Map<String, SimpleKeyPair>.from(keyPairsById ?? {}),
        _algorithm = algorithm ?? Ed25519();

  final Map<String, SimpleKeyPair> _keyPairsById;
  final Ed25519 _algorithm;

  static const defaultAlgorithmId = 'ed25519-v1';

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.signingKeyResolution,
      };

  Future<SimpleKeyPair> generateKeyPair(String keyId) async {
    final keyPair = await _algorithm.newKeyPair();
    _keyPairsById[keyId] = keyPair;
    return keyPair;
  }

  void registerKeyPair(String keyId, SimpleKeyPair keyPair) {
    _keyPairsById[keyId] = keyPair;
  }

  @override
  CryptographicSigningKeyResolutionResult resolveSigningHandle(
    CryptographicKeyReference keyReference,
  ) {
    if (keyReference.algorithmId != defaultAlgorithmId &&
        keyReference.keyType != CryptographicKeyType.ed25519) {
      return const CryptographicSigningKeyResolutionResult(
        outcome: CryptographicPrimitiveOutcome.algorithmMismatch,
        message: 'key reference algorithm mismatch',
      );
    }
    final keyPair = _keyPairsById[keyReference.keyId];
    if (keyPair == null) {
      return const CryptographicSigningKeyResolutionResult(
        outcome: CryptographicPrimitiveOutcome.keyNotFound,
        message: 'in-memory signing key not found',
      );
    }
    return CryptographicSigningKeyResolutionResult(
      outcome: CryptographicPrimitiveOutcome.valid,
      handle: InMemoryEd25519SigningKeyHandle(
        keyId: keyReference.keyId,
        keyPair: keyPair,
      ),
    );
  }
}

/// In-memory Ed25519 signing key handle — non-production, tests only.
class InMemoryEd25519SigningKeyHandle
    extends OpaqueCryptographicSigningKeyHandle {
  InMemoryEd25519SigningKeyHandle({
    required super.keyId,
    required this.keyPair,
  }) : super(
          algorithmId: InMemoryEd25519SigningKeyProvider.defaultAlgorithmId,
          holder: keyPair,
        );

  final SimpleKeyPair keyPair;
}

SimpleKeyPair? inMemoryEd25519KeyPairFromHandle(
  OpaqueCryptographicSigningKeyHandle handle,
) {
  if (handle is InMemoryEd25519SigningKeyHandle) {
    return handle.keyPair;
  }
  return null;
}

Future<CryptographicPublicKeyMaterial> publicKeyMaterialFromKeyPair({
  required String keyId,
  required SimpleKeyPair keyPair,
  String encoding = 'raw',
}) async {
  final publicKey = await keyPair.extractPublicKey();
  return CryptographicPublicKeyMaterial(
    publicKeyBytes: List<int>.from(publicKey.bytes),
    algorithmId: InMemoryEd25519SigningKeyProvider.defaultAlgorithmId,
    encoding: encoding,
    keyType: CryptographicKeyType.ed25519,
    keyId: keyId,
  );
}

Future<String> publicKeyFingerprintFromKeyPair(SimpleKeyPair keyPair) async {
  final material = await publicKeyMaterialFromKeyPair(
    keyId: 'derived',
    keyPair: keyPair,
  );
  final digest = Sha256DigestProvider().computeDigest(
    subjectBytes: material.publicKeyBytes,
    descriptor: material.toComparableJson().isEmpty
        ? throw StateError('invalid key material')
        : const CryptographicDigestDescriptor(
            algorithm: CryptographicDigestAlgorithm.sha256,
            algorithmId: Sha256DigestProvider.defaultAlgorithmId,
            outputSizeBits: 256,
          ),
    subjectId: material.keyId ?? 'derived',
  );
  return digest.value;
}
