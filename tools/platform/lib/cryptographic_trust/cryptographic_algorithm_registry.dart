import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'cryptographic_trust_exceptions.dart';
import 'interfaces/cryptographic_digest_provider.dart';
import 'interfaces/cryptographic_signature_verifier.dart';
import 'interfaces/cryptographic_signer.dart';

/// Registration descriptor for a cryptographic algorithm implementation.
class CryptographicAlgorithmRegistration {
  const CryptographicAlgorithmRegistration({
    required this.algorithmId,
    required this.operation,
    required this.capabilities,
    this.keyType,
    this.format,
    this.digestProvider,
    this.signatureVerifier,
    this.signer,
  });

  final String algorithmId;
  final CryptographicPrimitiveOperation operation;
  final Set<CryptographicProviderCapability> capabilities;
  final CryptographicKeyType? keyType;
  final CryptographicSignatureFormat? format;
  final CryptographicDigestProvider? digestProvider;
  final CryptographicSignatureVerifier? signatureVerifier;
  final CryptographicSigner? signer;
}

String _algorithmKey(
  CryptographicPrimitiveOperation operation,
  String algorithmId, {
  CryptographicKeyType? keyType,
  CryptographicSignatureFormat? format,
}) {
  final keyTypePart = keyType?.wireName ?? '-';
  final formatPart = format?.wireName ?? '-';
  return '${operation.wireName}:$algorithmId:$keyTypePart:$formatPart';
}

/// Registry of cryptographic algorithm implementations.
///
/// Selection is by lookup — no switch-based dispatch in consumers.
class CryptographicAlgorithmRegistry {
  CryptographicAlgorithmRegistry();

  final Map<String, CryptographicAlgorithmRegistration> _registrations = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void register(CryptographicAlgorithmRegistration registration) {
    if (_frozen) {
      throw CryptographicTrustRegistryFrozenException(
        'CryptographicAlgorithmRegistry',
      );
    }
    final key = _algorithmKey(
      registration.operation,
      registration.algorithmId,
      keyType: registration.keyType,
      format: registration.format,
    );
    if (_registrations.containsKey(key)) {
      throw CryptographicTrustAlgorithmConflictException(
        registration.algorithmId,
        operation: registration.operation.wireName,
      );
    }
    _registrations[key] = registration;
  }

  void registerAll(Iterable<CryptographicAlgorithmRegistration> registrations) {
    for (final registration in registrations) {
      register(registration);
    }
  }

  void freeze() => _frozen = true;

  bool contains({
    required CryptographicPrimitiveOperation operation,
    required String algorithmId,
    CryptographicKeyType? keyType,
    CryptographicSignatureFormat? format,
  }) {
    return _registrations.containsKey(
      _algorithmKey(operation, algorithmId, keyType: keyType, format: format),
    );
  }

  CryptographicAlgorithmRegistration? lookup({
    required CryptographicPrimitiveOperation operation,
    required String algorithmId,
    CryptographicKeyType? keyType,
    CryptographicSignatureFormat? format,
  }) {
    return _registrations[_algorithmKey(operation, algorithmId,
        keyType: keyType, format: format)];
  }

  CryptographicDigestProvider? resolveDigestProvider(String algorithmId) {
    return lookup(
      operation: CryptographicPrimitiveOperation.computeDigest,
      algorithmId: algorithmId,
    )?.digestProvider;
  }

  CryptographicSignatureVerifier? resolveSignatureVerifier({
    required String algorithmId,
    required CryptographicKeyType keyType,
    required CryptographicSignatureFormat format,
  }) {
    return lookup(
      operation: CryptographicPrimitiveOperation.verifySignature,
      algorithmId: algorithmId,
      keyType: keyType,
      format: format,
    )?.signatureVerifier;
  }

  CryptographicSigner? resolveSigner({
    required String algorithmId,
    required CryptographicKeyType keyType,
    required CryptographicSignatureFormat format,
  }) {
    return lookup(
      operation: CryptographicPrimitiveOperation.sign,
      algorithmId: algorithmId,
      keyType: keyType,
      format: format,
    )?.signer;
  }

  List<CryptographicAlgorithmRegistration> query({
    CryptographicPrimitiveOperation? operation,
    String? algorithmId,
  }) {
    final matches = _registrations.values.where((registration) {
      if (operation != null && registration.operation != operation) {
        return false;
      }
      if (algorithmId != null && registration.algorithmId != algorithmId) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final op = a.operation.wireName.compareTo(b.operation.wireName);
        if (op != 0) return op;
        return a.algorithmId.compareTo(b.algorithmId);
      });
    return matches;
  }
}
