import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

List<CryptographicKeyUsage> _sortedKeyUsage(List<CryptographicKeyUsage> input) {
  return List<CryptographicKeyUsage>.from(input)
    ..sort((a, b) => a.wireName.compareTo(b.wireName));
}

/// Safe public key reference — never stores private key material or secrets.
class CryptographicKeyReference {
  const CryptographicKeyReference({
    required this.keyId,
    required this.keyType,
    required this.algorithmId,
    required this.usage,
    required this.status,
    required this.publicKeyFingerprint,
    required this.version,
    this.issuerId,
    this.ownerId,
    this.validFrom,
    this.validUntil,
    this.metadata = const {},
  });

  final String keyId;
  final CryptographicKeyType keyType;
  final String algorithmId;
  final List<CryptographicKeyUsage> usage;
  final CryptographicKeyStatus status;
  final String? issuerId;
  final String? ownerId;
  final String publicKeyFingerprint;
  final String? validFrom;
  final String? validUntil;
  final String version;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'keyId': keyId,
        'keyType': keyType.wireName,
        'algorithmId': algorithmId,
        'usage': usage.map((e) => e.wireName).toList(),
        'status': status.wireName,
        if (issuerId != null) 'issuerId': issuerId,
        if (ownerId != null) 'ownerId': ownerId,
        'publicKeyFingerprint': publicKeyFingerprint,
        if (validFrom != null) 'validFrom': validFrom,
        if (validUntil != null) 'validUntil': validUntil,
        'version': version,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicKeyReference.fromJson(Map<String, dynamic> json) {
    return CryptographicKeyReference(
      keyId: json['keyId'] as String,
      keyType: CryptographicKeyTypeX.fromWireName(json['keyType'] as String),
      algorithmId: json['algorithmId'] as String,
      usage: List.unmodifiable(
        (json['usage'] as List<dynamic>)
            .map(
              (e) => CryptographicKeyUsageX.fromWireName(e as String),
            )
            .toList(),
      ),
      status: CryptographicKeyStatusX.fromWireName(json['status'] as String),
      issuerId: json['issuerId'] as String?,
      ownerId: json['ownerId'] as String?,
      publicKeyFingerprint: json['publicKeyFingerprint'] as String,
      validFrom: json['validFrom'] as String?,
      validUntil: json['validUntil'] as String?,
      version: json['version'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'keyId': keyId,
        'keyType': keyType.wireName,
        'algorithmId': algorithmId,
        'usage': _sortedKeyUsage(usage).map((e) => e.wireName).toList(),
        'status': status.wireName,
        if (issuerId != null) 'issuerId': issuerId,
        if (ownerId != null) 'ownerId': ownerId,
        'publicKeyFingerprint': publicKeyFingerprint,
        if (validFrom != null) 'validFrom': validFrom,
        if (validUntil != null) 'validUntil': validUntil,
        'version': version,
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicKeyReference copyWith({
    String? keyId,
    CryptographicKeyType? keyType,
    String? algorithmId,
    List<CryptographicKeyUsage>? usage,
    CryptographicKeyStatus? status,
    String? issuerId,
    String? ownerId,
    String? publicKeyFingerprint,
    String? validFrom,
    String? validUntil,
    String? version,
    Map<String, String>? metadata,
  }) {
    return CryptographicKeyReference(
      keyId: keyId ?? this.keyId,
      keyType: keyType ?? this.keyType,
      algorithmId: algorithmId ?? this.algorithmId,
      usage: usage ?? this.usage,
      status: status ?? this.status,
      issuerId: issuerId ?? this.issuerId,
      ownerId: ownerId ?? this.ownerId,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicKeyReference &&
          keyId == other.keyId &&
          keyType == other.keyType &&
          algorithmId == other.algorithmId &&
          trustListEquals(usage, other.usage) &&
          status == other.status &&
          issuerId == other.issuerId &&
          ownerId == other.ownerId &&
          publicKeyFingerprint == other.publicKeyFingerprint &&
          validFrom == other.validFrom &&
          validUntil == other.validUntil &&
          version == other.version &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        keyId,
        keyType,
        algorithmId,
        Object.hashAll(usage),
        status,
        issuerId,
        ownerId,
        publicKeyFingerprint,
        validFrom,
        validUntil,
        version,
        Object.hashAll(metadata.entries),
      );
}
