import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';

/// Declarative trust requirement — does not execute verification or authorize release.
class CryptographicTrustRequirement {
  const CryptographicTrustRequirement({
    required this.requirementId,
    required this.requirementType,
    required this.required,
    this.minimumTrustLevel,
    this.allowedAlgorithms = const [],
    this.allowedKeyTypes = const [],
    this.requiredKeyUsage = const [],
    this.requiredSignatureCount,
    this.requiredAttestationTypes = const [],
    this.requireTrustAnchor = false,
    this.requireTransparencyLog = false,
    this.requireNonRevokedKey = false,
    this.constraints = const {},
    this.metadata = const {},
  });

  final String requirementId;
  final CryptographicRequirementType requirementType;
  final bool required;
  final CryptographicTrustLevel? minimumTrustLevel;
  final List<CryptographicSignatureAlgorithm> allowedAlgorithms;
  final List<CryptographicKeyType> allowedKeyTypes;
  final List<CryptographicKeyUsage> requiredKeyUsage;
  final int? requiredSignatureCount;
  final List<CryptographicAttestationType> requiredAttestationTypes;
  final bool requireTrustAnchor;
  final bool requireTransparencyLog;
  final bool requireNonRevokedKey;
  final Map<String, String> constraints;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'requirementType': requirementType.wireName,
        'required': required,
        if (minimumTrustLevel != null)
          'minimumTrustLevel': minimumTrustLevel!.wireName,
        if (allowedAlgorithms.isNotEmpty)
          'allowedAlgorithms': allowedAlgorithms.map((e) => e.wireName).toList()
            ..sort(),
        if (allowedKeyTypes.isNotEmpty)
          'allowedKeyTypes': allowedKeyTypes.map((e) => e.wireName).toList()
            ..sort(),
        if (requiredKeyUsage.isNotEmpty)
          'requiredKeyUsage': requiredKeyUsage.map((e) => e.wireName).toList()
            ..sort(),
        if (requiredSignatureCount != null)
          'requiredSignatureCount': requiredSignatureCount,
        if (requiredAttestationTypes.isNotEmpty)
          'requiredAttestationTypes':
              requiredAttestationTypes.map((e) => e.wireName).toList()..sort(),
        'requireTrustAnchor': requireTrustAnchor,
        'requireTransparencyLog': requireTransparencyLog,
        'requireNonRevokedKey': requireNonRevokedKey,
        if (constraints.isNotEmpty) 'constraints': constraints,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustRequirement.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustRequirement(
      requirementId: json['requirementId'] as String,
      requirementType: CryptographicRequirementTypeX.fromWireName(
        json['requirementType'] as String,
      ),
      required: json['required'] as bool,
      minimumTrustLevel: json['minimumTrustLevel'] == null
          ? null
          : CryptographicTrustLevelX.fromWireName(
              json['minimumTrustLevel'] as String,
            ),
      allowedAlgorithms: List.unmodifiable(
        (json['allowedAlgorithms'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSignatureAlgorithmX.fromWireName(
                e.toString(),
              ),
            )
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      allowedKeyTypes: List.unmodifiable(
        (json['allowedKeyTypes'] as List<dynamic>? ?? [])
            .map((e) => CryptographicKeyTypeX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requiredKeyUsage: List.unmodifiable(
        (json['requiredKeyUsage'] as List<dynamic>? ?? [])
            .map((e) => CryptographicKeyUsageX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requiredSignatureCount: json['requiredSignatureCount'] as int?,
      requiredAttestationTypes: List.unmodifiable(
        (json['requiredAttestationTypes'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicAttestationTypeX.fromWireName(e.toString()),
            )
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requireTrustAnchor: json['requireTrustAnchor'] as bool? ?? false,
      requireTransparencyLog: json['requireTransparencyLog'] as bool? ?? false,
      requireNonRevokedKey: json['requireNonRevokedKey'] as bool? ?? false,
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
        'requirementId': requirementId,
        'requirementType': requirementType.wireName,
        'required': required,
        if (minimumTrustLevel != null)
          'minimumTrustLevel': minimumTrustLevel!.wireName,
        if (allowedAlgorithms.isNotEmpty)
          'allowedAlgorithms': allowedAlgorithms.map((e) => e.wireName).toList()
            ..sort(),
        if (allowedKeyTypes.isNotEmpty)
          'allowedKeyTypes': allowedKeyTypes.map((e) => e.wireName).toList()
            ..sort(),
        if (requiredKeyUsage.isNotEmpty)
          'requiredKeyUsage': requiredKeyUsage.map((e) => e.wireName).toList()
            ..sort(),
        if (requiredSignatureCount != null)
          'requiredSignatureCount': requiredSignatureCount,
        if (requiredAttestationTypes.isNotEmpty)
          'requiredAttestationTypes':
              requiredAttestationTypes.map((e) => e.wireName).toList()..sort(),
        'requireTrustAnchor': requireTrustAnchor,
        'requireTransparencyLog': requireTransparencyLog,
        'requireNonRevokedKey': requireNonRevokedKey,
        if (constraints.isNotEmpty)
          'constraints': Map.fromEntries(
            constraints.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  CryptographicTrustRequirement copyWith({
    String? requirementId,
    CryptographicRequirementType? requirementType,
    bool? required,
    CryptographicTrustLevel? minimumTrustLevel,
    List<CryptographicSignatureAlgorithm>? allowedAlgorithms,
    List<CryptographicKeyType>? allowedKeyTypes,
    List<CryptographicKeyUsage>? requiredKeyUsage,
    int? requiredSignatureCount,
    List<CryptographicAttestationType>? requiredAttestationTypes,
    bool? requireTrustAnchor,
    bool? requireTransparencyLog,
    bool? requireNonRevokedKey,
    Map<String, String>? constraints,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustRequirement(
      requirementId: requirementId ?? this.requirementId,
      requirementType: requirementType ?? this.requirementType,
      required: required ?? this.required,
      minimumTrustLevel: minimumTrustLevel ?? this.minimumTrustLevel,
      allowedAlgorithms: allowedAlgorithms ?? this.allowedAlgorithms,
      allowedKeyTypes: allowedKeyTypes ?? this.allowedKeyTypes,
      requiredKeyUsage: requiredKeyUsage ?? this.requiredKeyUsage,
      requiredSignatureCount:
          requiredSignatureCount ?? this.requiredSignatureCount,
      requiredAttestationTypes:
          requiredAttestationTypes ?? this.requiredAttestationTypes,
      requireTrustAnchor: requireTrustAnchor ?? this.requireTrustAnchor,
      requireTransparencyLog:
          requireTransparencyLog ?? this.requireTransparencyLog,
      requireNonRevokedKey: requireNonRevokedKey ?? this.requireNonRevokedKey,
      constraints: constraints ?? this.constraints,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustRequirement &&
          requirementId == other.requirementId &&
          requirementType == other.requirementType &&
          required == other.required &&
          minimumTrustLevel == other.minimumTrustLevel &&
          trustListEquals(allowedAlgorithms, other.allowedAlgorithms) &&
          trustListEquals(allowedKeyTypes, other.allowedKeyTypes) &&
          trustListEquals(requiredKeyUsage, other.requiredKeyUsage) &&
          requiredSignatureCount == other.requiredSignatureCount &&
          trustListEquals(
            requiredAttestationTypes,
            other.requiredAttestationTypes,
          ) &&
          requireTrustAnchor == other.requireTrustAnchor &&
          requireTransparencyLog == other.requireTransparencyLog &&
          requireNonRevokedKey == other.requireNonRevokedKey &&
          trustMapEquals(constraints, other.constraints) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requirementId,
        requirementType,
        required,
        minimumTrustLevel,
        Object.hashAll(allowedAlgorithms),
        Object.hashAll(allowedKeyTypes),
        Object.hashAll(requiredKeyUsage),
        requiredSignatureCount,
        Object.hashAll(requiredAttestationTypes),
        requireTrustAnchor,
        requireTransparencyLog,
        requireNonRevokedKey,
        Object.hashAll(constraints.entries),
        Object.hashAll(metadata.entries),
      );
}
