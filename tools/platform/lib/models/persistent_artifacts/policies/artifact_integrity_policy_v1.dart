import '../persistent_artifact_enums.dart';
import '../persistent_artifact_equality.dart';

const _policyFingerprintPlaceholder =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Declarative integrity policy for persistent artifacts.
///
/// Policy only — does not compute, verify, or sign digests.
/// Integrity digest != cryptographic signature.
class PersistentArtifactIntegrityPolicy {
  const PersistentArtifactIntegrityPolicy({
    required this.policyId,
    required this.version,
    required this.name,
    required this.description,
    required this.status,
    required this.requiredDigestAlgorithmIds,
    required this.requireCryptographicTrust,
    required this.minimumIntegrityStatus,
    this.scope = const {},
    this.effectiveFrom,
    this.deprecatedAt,
    this.retiredAt,
    this.metadata = const {},
  });

  final String policyId;
  final int version;
  final String name;
  final String description;
  final PersistentArtifactPolicyStatus status;
  final List<String> requiredDigestAlgorithmIds;
  final bool requireCryptographicTrust;
  final PersistentArtifactIntegrityStatus minimumIntegrityStatus;
  final Map<String, String> scope;
  final String? effectiveFrom;
  final String? deprecatedAt;
  final String? retiredAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'requiredDigestAlgorithmIds': requiredDigestAlgorithmIds,
        'requireCryptographicTrust': requireCryptographicTrust,
        'minimumIntegrityStatus': minimumIntegrityStatus.wireName,
        if (scope.isNotEmpty) 'scope': scope,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactIntegrityPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactIntegrityPolicy(
      policyId: json['policyId'] as String,
      version: json['version'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
      status: PersistentArtifactPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      requiredDigestAlgorithmIds: List.unmodifiable(
        (json['requiredDigestAlgorithmIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      requireCryptographicTrust: json['requireCryptographicTrust'] as bool,
      minimumIntegrityStatus: PersistentArtifactIntegrityStatusX.fromWireName(
        json['minimumIntegrityStatus'] as String,
      ),
      scope: Map.unmodifiable(
        (json['scope'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      effectiveFrom: json['effectiveFrom'] as String?,
      deprecatedAt: json['deprecatedAt'] as String?,
      retiredAt: json['retiredAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'requiredDigestAlgorithmIds':
            List<String>.from(requiredDigestAlgorithmIds)..sort(),
        'requireCryptographicTrust': requireCryptographicTrust,
        'minimumIntegrityStatus': minimumIntegrityStatus.wireName,
        if (scope.isNotEmpty) 'scope': paSortedStringMap(scope),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactIntegrityPolicy copyWith({
    String? policyId,
    int? version,
    String? name,
    String? description,
    PersistentArtifactPolicyStatus? status,
    List<String>? requiredDigestAlgorithmIds,
    bool? requireCryptographicTrust,
    PersistentArtifactIntegrityStatus? minimumIntegrityStatus,
    Map<String, String>? scope,
    String? effectiveFrom,
    String? deprecatedAt,
    String? retiredAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactIntegrityPolicy(
      policyId: policyId ?? this.policyId,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      requiredDigestAlgorithmIds:
          requiredDigestAlgorithmIds ?? this.requiredDigestAlgorithmIds,
      requireCryptographicTrust:
          requireCryptographicTrust ?? this.requireCryptographicTrust,
      minimumIntegrityStatus:
          minimumIntegrityStatus ?? this.minimumIntegrityStatus,
      scope: scope ?? this.scope,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      deprecatedAt: deprecatedAt ?? this.deprecatedAt,
      retiredAt: retiredAt ?? this.retiredAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactIntegrityPolicy &&
          policyId == other.policyId &&
          version == other.version &&
          name == other.name &&
          description == other.description &&
          status == other.status &&
          paListEquals(
              requiredDigestAlgorithmIds, other.requiredDigestAlgorithmIds) &&
          requireCryptographicTrust == other.requireCryptographicTrust &&
          minimumIntegrityStatus == other.minimumIntegrityStatus &&
          paMapEquals(scope, other.scope) &&
          effectiveFrom == other.effectiveFrom &&
          deprecatedAt == other.deprecatedAt &&
          retiredAt == other.retiredAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        version,
        name,
        description,
        status,
        Object.hashAll(requiredDigestAlgorithmIds),
        requireCryptographicTrust,
        minimumIntegrityStatus,
        Object.hashAll(scope.entries),
        effectiveFrom,
        deprecatedAt,
        retiredAt,
        Object.hashAll(metadata.entries),
      );
}

/// Candidate artifact integrity policy v1.
class ArtifactIntegrityPolicyV1 {
  const ArtifactIntegrityPolicyV1._();

  static const policyId = 'artifact-integrity-policy-v1';

  static PersistentArtifactIntegrityPolicy create() {
    return PersistentArtifactIntegrityPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Artifact Integrity Policy',
      description:
          'Structural integrity policy for persistent artifact digest and verification requirements.',
      status: PersistentArtifactPolicyStatus.candidate,
      requiredDigestAlgorithmIds: const ['sha256'],
      requireCryptographicTrust: false,
      minimumIntegrityStatus: PersistentArtifactIntegrityStatus.declared,
      scope: const {
        'domain': 'persistent-artifact',
        'policyFingerprint': _policyFingerprintPlaceholder,
      },
      metadata: const {
        'limitations':
            'no-real-digest,no-real-verification,structural-descriptor-only',
      },
    );
  }
}
