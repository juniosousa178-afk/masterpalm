import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Declared signer identity — not application user authentication.
///
/// [displayName] is excluded from [toComparableJson] (non-normative label).
/// [claims] must not contain secrets.
class CryptographicSignerIdentity {
  const CryptographicSignerIdentity({
    required this.identityId,
    required this.identityType,
    required this.keyId,
    required this.trustLevel,
    this.displayName,
    this.organizationId,
    this.issuerId,
    this.claims = const {},
    this.metadata = const {},
  });

  final String identityId;
  final CryptographicIdentityType identityType;
  final String? displayName;
  final String? organizationId;
  final String keyId;
  final String? issuerId;
  final Map<String, String> claims;
  final CryptographicTrustLevel trustLevel;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'identityId': identityId,
        'identityType': identityType.wireName,
        if (displayName != null) 'displayName': displayName,
        if (organizationId != null) 'organizationId': organizationId,
        'keyId': keyId,
        if (issuerId != null) 'issuerId': issuerId,
        if (claims.isNotEmpty) 'claims': claims,
        'trustLevel': trustLevel.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicSignerIdentity.fromJson(Map<String, dynamic> json) {
    return CryptographicSignerIdentity(
      identityId: json['identityId'] as String,
      identityType: CryptographicIdentityTypeX.fromWireName(
        json['identityType'] as String,
      ),
      displayName: json['displayName'] as String?,
      organizationId: json['organizationId'] as String?,
      keyId: json['keyId'] as String,
      issuerId: json['issuerId'] as String?,
      claims: Map.unmodifiable(
        (json['claims'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'identityId': identityId,
        'identityType': identityType.wireName,
        if (organizationId != null) 'organizationId': organizationId,
        'keyId': keyId,
        if (issuerId != null) 'issuerId': issuerId,
        if (claims.isNotEmpty) 'claims': _sortedStringMap(claims),
        'trustLevel': trustLevel.wireName,
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicSignerIdentity copyWith({
    String? identityId,
    CryptographicIdentityType? identityType,
    String? displayName,
    String? organizationId,
    String? keyId,
    String? issuerId,
    Map<String, String>? claims,
    CryptographicTrustLevel? trustLevel,
    Map<String, String>? metadata,
  }) {
    return CryptographicSignerIdentity(
      identityId: identityId ?? this.identityId,
      identityType: identityType ?? this.identityType,
      displayName: displayName ?? this.displayName,
      organizationId: organizationId ?? this.organizationId,
      keyId: keyId ?? this.keyId,
      issuerId: issuerId ?? this.issuerId,
      claims: claims ?? this.claims,
      trustLevel: trustLevel ?? this.trustLevel,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicSignerIdentity &&
          identityId == other.identityId &&
          identityType == other.identityType &&
          displayName == other.displayName &&
          organizationId == other.organizationId &&
          keyId == other.keyId &&
          issuerId == other.issuerId &&
          trustMapEquals(claims, other.claims) &&
          trustLevel == other.trustLevel &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        identityId,
        identityType,
        displayName,
        organizationId,
        keyId,
        issuerId,
        Object.hashAll(claims.entries),
        trustLevel,
        Object.hashAll(metadata.entries),
      );
}
