import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative retention policy for persistent artifacts.
///
/// Policy only — does not execute deletion, archive, or lifecycle transitions.
/// Legal hold is declarative and not physically applied in Part 1.
class PersistentArtifactRetentionPolicy {
  const PersistentArtifactRetentionPolicy({
    required this.policyId,
    required this.version,
    required this.name,
    required this.description,
    required this.status,
    required this.artifactTypes,
    required this.minimumRetention,
    required this.retentionAction,
    required this.legalHoldRequired,
    required this.immutableUntilExpiration,
    required this.scope,
    this.maximumRetention,
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
  final List<PersistentArtifactType> artifactTypes;
  final String minimumRetention;
  final String? maximumRetention;
  final PersistentArtifactRetentionAction retentionAction;
  final bool legalHoldRequired;
  final bool immutableUntilExpiration;
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
        'artifactTypes': artifactTypes.map((e) => e.wireName).toList(),
        'minimumRetention': minimumRetention,
        if (maximumRetention != null) 'maximumRetention': maximumRetention,
        'retentionAction': retentionAction.wireName,
        'legalHoldRequired': legalHoldRequired,
        'immutableUntilExpiration': immutableUntilExpiration,
        if (scope.isNotEmpty) 'scope': scope,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactRetentionPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactRetentionPolicy(
      policyId: json['policyId'] as String,
      version: json['version'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
      status: PersistentArtifactPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      artifactTypes: List.unmodifiable(
        (json['artifactTypes'] as List<dynamic>)
            .map(
              (e) => PersistentArtifactTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      minimumRetention: json['minimumRetention'] as String,
      maximumRetention: json['maximumRetention'] as String?,
      retentionAction: PersistentArtifactRetentionActionX.fromWireName(
        json['retentionAction'] as String,
      ),
      legalHoldRequired: json['legalHoldRequired'] as bool,
      immutableUntilExpiration: json['immutableUntilExpiration'] as bool,
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
        'artifactTypes': (artifactTypes.map((e) => e.wireName).toList()
          ..sort()),
        'minimumRetention': minimumRetention,
        if (maximumRetention != null) 'maximumRetention': maximumRetention,
        'retentionAction': retentionAction.wireName,
        'legalHoldRequired': legalHoldRequired,
        'immutableUntilExpiration': immutableUntilExpiration,
        if (scope.isNotEmpty) 'scope': paSortedStringMap(scope),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactRetentionPolicy copyWith({
    String? policyId,
    int? version,
    String? name,
    String? description,
    PersistentArtifactPolicyStatus? status,
    List<PersistentArtifactType>? artifactTypes,
    String? minimumRetention,
    String? maximumRetention,
    PersistentArtifactRetentionAction? retentionAction,
    bool? legalHoldRequired,
    bool? immutableUntilExpiration,
    Map<String, String>? scope,
    String? effectiveFrom,
    String? deprecatedAt,
    String? retiredAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactRetentionPolicy(
      policyId: policyId ?? this.policyId,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      artifactTypes: artifactTypes ?? this.artifactTypes,
      minimumRetention: minimumRetention ?? this.minimumRetention,
      maximumRetention: maximumRetention ?? this.maximumRetention,
      retentionAction: retentionAction ?? this.retentionAction,
      legalHoldRequired: legalHoldRequired ?? this.legalHoldRequired,
      immutableUntilExpiration:
          immutableUntilExpiration ?? this.immutableUntilExpiration,
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
      other is PersistentArtifactRetentionPolicy &&
          policyId == other.policyId &&
          version == other.version &&
          name == other.name &&
          description == other.description &&
          status == other.status &&
          paListEquals(artifactTypes, other.artifactTypes) &&
          minimumRetention == other.minimumRetention &&
          maximumRetention == other.maximumRetention &&
          retentionAction == other.retentionAction &&
          legalHoldRequired == other.legalHoldRequired &&
          immutableUntilExpiration == other.immutableUntilExpiration &&
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
        Object.hashAll(artifactTypes),
        minimumRetention,
        maximumRetention,
        retentionAction,
        legalHoldRequired,
        immutableUntilExpiration,
        Object.hashAll(scope.entries),
        effectiveFrom,
        deprecatedAt,
        retiredAt,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative storage policy for persistent artifacts.
///
/// Policy only — does not select providers, create buckets, or execute replication.
/// Does not authorize release or deployment.
class PersistentArtifactStoragePolicy {
  const PersistentArtifactStoragePolicy({
    required this.policyId,
    required this.version,
    required this.name,
    required this.description,
    required this.status,
    required this.allowedLocationTypes,
    required this.allowedStorageClasses,
    required this.minimumDurability,
    required this.consistencyModel,
    required this.minimumReplicaCount,
    required this.requireEncryption,
    required this.requireIntegrityRecord,
    required this.requireCryptographicTrust,
    this.allowedRegions = const [],
    this.constraints = const {},
    this.metadata = const {},
  });

  final String policyId;
  final int version;
  final String name;
  final String description;
  final PersistentArtifactPolicyStatus status;
  final List<PersistentArtifactLocationType> allowedLocationTypes;
  final List<PersistentArtifactStorageClass> allowedStorageClasses;
  final PersistentArtifactDurabilityLevel minimumDurability;
  final PersistentArtifactConsistencyModel consistencyModel;
  final int minimumReplicaCount;
  final bool requireEncryption;
  final bool requireIntegrityRecord;
  final bool requireCryptographicTrust;
  final List<String> allowedRegions;
  final Map<String, String> constraints;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'allowedLocationTypes':
            allowedLocationTypes.map((e) => e.wireName).toList(),
        'allowedStorageClasses':
            allowedStorageClasses.map((e) => e.wireName).toList(),
        'minimumDurability': minimumDurability.wireName,
        'consistencyModel': consistencyModel.wireName,
        'minimumReplicaCount': minimumReplicaCount,
        'requireEncryption': requireEncryption,
        'requireIntegrityRecord': requireIntegrityRecord,
        'requireCryptographicTrust': requireCryptographicTrust,
        if (allowedRegions.isNotEmpty) 'allowedRegions': allowedRegions,
        if (constraints.isNotEmpty) 'constraints': constraints,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactStoragePolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactStoragePolicy(
      policyId: json['policyId'] as String,
      version: json['version'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
      status: PersistentArtifactPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      allowedLocationTypes: List.unmodifiable(
        (json['allowedLocationTypes'] as List<dynamic>)
            .map(
              (e) => PersistentArtifactLocationTypeX.fromWireName(
                e as String,
              ),
            )
            .toList(),
      ),
      allowedStorageClasses: List.unmodifiable(
        (json['allowedStorageClasses'] as List<dynamic>)
            .map(
              (e) => PersistentArtifactStorageClassX.fromWireName(
                e as String,
              ),
            )
            .toList(),
      ),
      minimumDurability: PersistentArtifactDurabilityLevelX.fromWireName(
        json['minimumDurability'] as String,
      ),
      consistencyModel: PersistentArtifactConsistencyModelX.fromWireName(
        json['consistencyModel'] as String,
      ),
      minimumReplicaCount: json['minimumReplicaCount'] as int,
      requireEncryption: json['requireEncryption'] as bool,
      requireIntegrityRecord: json['requireIntegrityRecord'] as bool,
      requireCryptographicTrust: json['requireCryptographicTrust'] as bool,
      allowedRegions: List.unmodifiable(
        (json['allowedRegions'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
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
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'allowedLocationTypes':
            (allowedLocationTypes.map((e) => e.wireName).toList()..sort()),
        'allowedStorageClasses':
            (allowedStorageClasses.map((e) => e.wireName).toList()..sort()),
        'minimumDurability': minimumDurability.wireName,
        'consistencyModel': consistencyModel.wireName,
        'minimumReplicaCount': minimumReplicaCount,
        'requireEncryption': requireEncryption,
        'requireIntegrityRecord': requireIntegrityRecord,
        'requireCryptographicTrust': requireCryptographicTrust,
        if (allowedRegions.isNotEmpty)
          'allowedRegions': List<String>.from(allowedRegions)..sort(),
        if (constraints.isNotEmpty)
          'constraints': paSortedStringMap(constraints),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactStoragePolicy copyWith({
    String? policyId,
    int? version,
    String? name,
    String? description,
    PersistentArtifactPolicyStatus? status,
    List<PersistentArtifactLocationType>? allowedLocationTypes,
    List<PersistentArtifactStorageClass>? allowedStorageClasses,
    PersistentArtifactDurabilityLevel? minimumDurability,
    PersistentArtifactConsistencyModel? consistencyModel,
    int? minimumReplicaCount,
    bool? requireEncryption,
    bool? requireIntegrityRecord,
    bool? requireCryptographicTrust,
    List<String>? allowedRegions,
    Map<String, String>? constraints,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactStoragePolicy(
      policyId: policyId ?? this.policyId,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      allowedLocationTypes: allowedLocationTypes ?? this.allowedLocationTypes,
      allowedStorageClasses:
          allowedStorageClasses ?? this.allowedStorageClasses,
      minimumDurability: minimumDurability ?? this.minimumDurability,
      consistencyModel: consistencyModel ?? this.consistencyModel,
      minimumReplicaCount: minimumReplicaCount ?? this.minimumReplicaCount,
      requireEncryption: requireEncryption ?? this.requireEncryption,
      requireIntegrityRecord:
          requireIntegrityRecord ?? this.requireIntegrityRecord,
      requireCryptographicTrust:
          requireCryptographicTrust ?? this.requireCryptographicTrust,
      allowedRegions: allowedRegions ?? this.allowedRegions,
      constraints: constraints ?? this.constraints,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactStoragePolicy &&
          policyId == other.policyId &&
          version == other.version &&
          name == other.name &&
          description == other.description &&
          status == other.status &&
          paListEquals(allowedLocationTypes, other.allowedLocationTypes) &&
          paListEquals(allowedStorageClasses, other.allowedStorageClasses) &&
          minimumDurability == other.minimumDurability &&
          consistencyModel == other.consistencyModel &&
          minimumReplicaCount == other.minimumReplicaCount &&
          requireEncryption == other.requireEncryption &&
          requireIntegrityRecord == other.requireIntegrityRecord &&
          requireCryptographicTrust == other.requireCryptographicTrust &&
          paListEquals(allowedRegions, other.allowedRegions) &&
          paMapEquals(constraints, other.constraints) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        version,
        name,
        description,
        status,
        Object.hashAll(allowedLocationTypes),
        Object.hashAll(allowedStorageClasses),
        minimumDurability,
        consistencyModel,
        minimumReplicaCount,
        requireEncryption,
        requireIntegrityRecord,
        requireCryptographicTrust,
        Object.hashAll(allowedRegions),
        Object.hashAll(constraints.entries),
        Object.hashAll(metadata.entries),
      );
}
