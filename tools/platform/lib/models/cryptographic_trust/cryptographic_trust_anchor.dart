import 'cryptographic_key_reference.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Declarative trust anchor reference — no private keys or X.509 parsing.
///
/// Does not authorize release or imply automatic compliance.
class CryptographicTrustAnchorReference {
  const CryptographicTrustAnchorReference({
    required this.trustAnchorId,
    required this.keyReference,
    required this.trustLevel,
    required this.status,
    required this.issuer,
    required this.scope,
    this.validFrom,
    this.validUntil,
    this.constraints = const {},
    this.metadata = const {},
  });

  final String trustAnchorId;
  final CryptographicKeyReference keyReference;
  final CryptographicTrustLevel trustLevel;
  final CryptographicTrustStatus status;
  final String? validFrom;
  final String? validUntil;
  final String issuer;
  final Map<String, String> scope;
  final Map<String, String> constraints;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'trustAnchorId': trustAnchorId,
        'keyReference': keyReference.toJson(),
        'trustLevel': trustLevel.wireName,
        'status': status.wireName,
        if (validFrom != null) 'validFrom': validFrom,
        if (validUntil != null) 'validUntil': validUntil,
        'issuer': issuer,
        if (scope.isNotEmpty) 'scope': scope,
        if (constraints.isNotEmpty) 'constraints': constraints,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustAnchorReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustAnchorReference(
      trustAnchorId: json['trustAnchorId'] as String,
      keyReference: CryptographicKeyReference.fromJson(
        json['keyReference'] as Map<String, dynamic>,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      status: CryptographicTrustStatusX.fromWireName(
        json['status'] as String,
      ),
      validFrom: json['validFrom'] as String?,
      validUntil: json['validUntil'] as String?,
      issuer: json['issuer'] as String,
      scope: Map.unmodifiable(
        (json['scope'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      constraints: Map.unmodifiable(
        (json['constraints'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'trustAnchorId': trustAnchorId,
        'keyReference': keyReference.toComparableJson(),
        'trustLevel': trustLevel.wireName,
        'status': status.wireName,
        if (validFrom != null) 'validFrom': validFrom,
        if (validUntil != null) 'validUntil': validUntil,
        'issuer': issuer,
        if (scope.isNotEmpty) 'scope': _sortedStringMap(scope),
        if (constraints.isNotEmpty)
          'constraints': _sortedStringMap(constraints),
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicTrustAnchorReference copyWith({
    String? trustAnchorId,
    CryptographicKeyReference? keyReference,
    CryptographicTrustLevel? trustLevel,
    CryptographicTrustStatus? status,
    String? validFrom,
    String? validUntil,
    String? issuer,
    Map<String, String>? scope,
    Map<String, String>? constraints,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustAnchorReference(
      trustAnchorId: trustAnchorId ?? this.trustAnchorId,
      keyReference: keyReference ?? this.keyReference,
      trustLevel: trustLevel ?? this.trustLevel,
      status: status ?? this.status,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      issuer: issuer ?? this.issuer,
      scope: scope ?? this.scope,
      constraints: constraints ?? this.constraints,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustAnchorReference &&
          trustAnchorId == other.trustAnchorId &&
          keyReference == other.keyReference &&
          trustLevel == other.trustLevel &&
          status == other.status &&
          validFrom == other.validFrom &&
          validUntil == other.validUntil &&
          issuer == other.issuer &&
          trustMapEquals(scope, other.scope) &&
          trustMapEquals(constraints, other.constraints) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        trustAnchorId,
        keyReference,
        trustLevel,
        status,
        validFrom,
        validUntil,
        issuer,
        Object.hashAll(scope.entries),
        Object.hashAll(constraints.entries),
        Object.hashAll(metadata.entries),
      );
}
