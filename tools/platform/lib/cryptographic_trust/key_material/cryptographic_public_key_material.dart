import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_equality.dart';

/// Public key bytes required for verification — never contains private material.
class CryptographicPublicKeyMaterial {
  const CryptographicPublicKeyMaterial({
    required this.publicKeyBytes,
    required this.algorithmId,
    required this.encoding,
    required this.keyType,
    this.keyId,
    this.metadata = const {},
  });

  final List<int> publicKeyBytes;
  final String algorithmId;
  final String encoding;
  final CryptographicKeyType keyType;
  final String? keyId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'publicKeyBytes': publicKeyBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        'algorithmId': algorithmId,
        'encoding': encoding,
        'keyType': keyType.wireName,
        if (keyId != null) 'keyId': keyId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicPublicKeyMaterial.fromJson(Map<String, dynamic> json) {
    final hex = json['publicKeyBytes'] as String;
    return CryptographicPublicKeyMaterial(
      publicKeyBytes: List.unmodifiable(
        List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      ),
      algorithmId: json['algorithmId'] as String,
      encoding: json['encoding'] as String,
      keyType: CryptographicKeyTypeX.fromWireName(json['keyType'] as String),
      keyId: json['keyId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'algorithmId': algorithmId,
        'encoding': encoding,
        'keyType': keyType.wireName,
        if (keyId != null) 'keyId': keyId,
      };

  CryptographicPublicKeyMaterial copyWith({
    List<int>? publicKeyBytes,
    String? algorithmId,
    String? encoding,
    CryptographicKeyType? keyType,
    String? keyId,
    Map<String, String>? metadata,
  }) {
    return CryptographicPublicKeyMaterial(
      publicKeyBytes: publicKeyBytes ?? this.publicKeyBytes,
      algorithmId: algorithmId ?? this.algorithmId,
      encoding: encoding ?? this.encoding,
      keyType: keyType ?? this.keyType,
      keyId: keyId ?? this.keyId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicPublicKeyMaterial &&
          trustListEqualsInt(publicKeyBytes, other.publicKeyBytes) &&
          algorithmId == other.algorithmId &&
          encoding == other.encoding &&
          keyType == other.keyType &&
          keyId == other.keyId &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(publicKeyBytes),
        algorithmId,
        encoding,
        keyType,
        keyId,
        Object.hashAll(metadata.entries),
      );
}

bool trustListEqualsInt(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

extension CryptographicPublicKeyMaterialListEquality on List<int> {
  bool trustBytesEquals(List<int> other) => trustListEqualsInt(this, other);
}
