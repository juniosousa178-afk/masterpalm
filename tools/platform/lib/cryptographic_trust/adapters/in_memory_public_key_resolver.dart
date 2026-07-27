import '../../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../interfaces/cryptographic_public_key_resolver.dart';
import '../key_material/cryptographic_public_key_material.dart';

/// In-memory public key resolver for tests and offline evaluation.
class InMemoryPublicKeyResolver implements CryptographicPublicKeyResolver {
  InMemoryPublicKeyResolver({
    Map<String, CryptographicPublicKeyMaterial>? keysById,
  }) : _keysById = Map<String, CryptographicPublicKeyMaterial>.from(
          keysById ?? {},
        );

  final Map<String, CryptographicPublicKeyMaterial> _keysById;

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.publicKeyResolution,
      };

  void register(CryptographicPublicKeyMaterial material) {
    final keyId = material.keyId;
    if (keyId == null || keyId.isEmpty) {
      throw ArgumentError('keyId is required for in-memory registration');
    }
    _keysById[keyId] = material;
  }

  void registerAll(Iterable<CryptographicPublicKeyMaterial> materials) {
    for (final material in materials) {
      register(material);
    }
  }

  @override
  CryptographicPublicKeyResolutionResult resolvePublicKey(
    CryptographicKeyReference keyReference,
  ) {
    final material = _keysById[keyReference.keyId];
    if (material == null) {
      return const CryptographicPublicKeyResolutionResult(
        outcome: CryptographicPrimitiveOutcome.keyNotFound,
        message: 'public key not found',
      );
    }
    if (material.algorithmId != keyReference.algorithmId &&
        material.keyType != keyReference.keyType) {
      return const CryptographicPublicKeyResolutionResult(
        outcome: CryptographicPrimitiveOutcome.algorithmMismatch,
        message: 'public key algorithm mismatch',
      );
    }
    return CryptographicPublicKeyResolutionResult(
      outcome: CryptographicPrimitiveOutcome.valid,
      publicKeyMaterial: material,
    );
  }
}
