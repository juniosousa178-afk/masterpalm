import '../persistent_artifact_enums.dart';
import '../persistent_artifact_equality.dart';

const _policyFingerprintPlaceholder =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Declarative replication policy for persistent artifacts.
///
/// Policy only — does not execute replication or test connectivity.
class PersistentArtifactReplicationPolicy {
  const PersistentArtifactReplicationPolicy({
    required this.policyId,
    required this.version,
    required this.name,
    required this.description,
    required this.status,
    required this.minimumReplicaCount,
    required this.distinctFailureDomains,
    required this.durabilityLevel,
    required this.consistencyModel,
    this.allowedRegions = const [],
    this.requiredStorageClasses = const [],
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
  final int minimumReplicaCount;
  final int distinctFailureDomains;
  final List<String> allowedRegions;
  final List<PersistentArtifactStorageClass> requiredStorageClasses;
  final PersistentArtifactDurabilityLevel durabilityLevel;
  final PersistentArtifactConsistencyModel consistencyModel;
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
        'minimumReplicaCount': minimumReplicaCount,
        'distinctFailureDomains': distinctFailureDomains,
        if (allowedRegions.isNotEmpty) 'allowedRegions': allowedRegions,
        if (requiredStorageClasses.isNotEmpty)
          'requiredStorageClasses':
              requiredStorageClasses.map((e) => e.wireName).toList(),
        'durabilityLevel': durabilityLevel.wireName,
        'consistencyModel': consistencyModel.wireName,
        if (scope.isNotEmpty) 'scope': scope,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactReplicationPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactReplicationPolicy(
      policyId: json['policyId'] as String,
      version: json['version'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
      status: PersistentArtifactPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      minimumReplicaCount: json['minimumReplicaCount'] as int,
      distinctFailureDomains: json['distinctFailureDomains'] as int,
      allowedRegions: List.unmodifiable(
        (json['allowedRegions'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      requiredStorageClasses: List.unmodifiable(
        (json['requiredStorageClasses'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactStorageClassX.fromWireName(
                e as String,
              ),
            )
            .toList(),
      ),
      durabilityLevel: PersistentArtifactDurabilityLevelX.fromWireName(
        json['durabilityLevel'] as String,
      ),
      consistencyModel: PersistentArtifactConsistencyModelX.fromWireName(
        json['consistencyModel'] as String,
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
        'minimumReplicaCount': minimumReplicaCount,
        'distinctFailureDomains': distinctFailureDomains,
        if (allowedRegions.isNotEmpty)
          'allowedRegions': List<String>.from(allowedRegions)..sort(),
        if (requiredStorageClasses.isNotEmpty)
          'requiredStorageClasses':
              (requiredStorageClasses.map((e) => e.wireName).toList()..sort()),
        'durabilityLevel': durabilityLevel.wireName,
        'consistencyModel': consistencyModel.wireName,
        if (scope.isNotEmpty) 'scope': paSortedStringMap(scope),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactReplicationPolicy copyWith({
    String? policyId,
    int? version,
    String? name,
    String? description,
    PersistentArtifactPolicyStatus? status,
    int? minimumReplicaCount,
    int? distinctFailureDomains,
    List<String>? allowedRegions,
    List<PersistentArtifactStorageClass>? requiredStorageClasses,
    PersistentArtifactDurabilityLevel? durabilityLevel,
    PersistentArtifactConsistencyModel? consistencyModel,
    Map<String, String>? scope,
    String? effectiveFrom,
    String? deprecatedAt,
    String? retiredAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactReplicationPolicy(
      policyId: policyId ?? this.policyId,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      minimumReplicaCount: minimumReplicaCount ?? this.minimumReplicaCount,
      distinctFailureDomains:
          distinctFailureDomains ?? this.distinctFailureDomains,
      allowedRegions: allowedRegions ?? this.allowedRegions,
      requiredStorageClasses:
          requiredStorageClasses ?? this.requiredStorageClasses,
      durabilityLevel: durabilityLevel ?? this.durabilityLevel,
      consistencyModel: consistencyModel ?? this.consistencyModel,
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
      other is PersistentArtifactReplicationPolicy &&
          policyId == other.policyId &&
          version == other.version &&
          name == other.name &&
          description == other.description &&
          status == other.status &&
          minimumReplicaCount == other.minimumReplicaCount &&
          distinctFailureDomains == other.distinctFailureDomains &&
          paListEquals(allowedRegions, other.allowedRegions) &&
          paListEquals(requiredStorageClasses, other.requiredStorageClasses) &&
          durabilityLevel == other.durabilityLevel &&
          consistencyModel == other.consistencyModel &&
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
        minimumReplicaCount,
        distinctFailureDomains,
        Object.hashAll(allowedRegions),
        Object.hashAll(requiredStorageClasses),
        durabilityLevel,
        consistencyModel,
        Object.hashAll(scope.entries),
        effectiveFrom,
        deprecatedAt,
        retiredAt,
        Object.hashAll(metadata.entries),
      );
}

/// Candidate artifact replication policy v1.
class ArtifactReplicationPolicyV1 {
  const ArtifactReplicationPolicyV1._();

  static const policyId = 'artifact-replication-policy-v1';

  static PersistentArtifactReplicationPolicy create() {
    return PersistentArtifactReplicationPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Artifact Replication Policy',
      description:
          'Structural replication policy for persistent artifact durability and failure domain requirements.',
      status: PersistentArtifactPolicyStatus.candidate,
      minimumReplicaCount: 2,
      distinctFailureDomains: 2,
      durabilityLevel: PersistentArtifactDurabilityLevel.enhanced,
      consistencyModel: PersistentArtifactConsistencyModel.eventual,
      requiredStorageClasses: const [
        PersistentArtifactStorageClass.standard,
      ],
      scope: const {
        'domain': 'persistent-artifact',
        'policyFingerprint': _policyFingerprintPlaceholder,
      },
      metadata: const {
        'limitations':
            'no-real-replication,no-connectivity-test,structural-descriptor-only',
      },
    );
  }
}
