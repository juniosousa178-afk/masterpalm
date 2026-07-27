import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative replication requirement for persistent artifacts.
///
/// Requirement only — does not execute replication or test connectivity.
class PersistentArtifactReplicationRequirement {
  const PersistentArtifactReplicationRequirement({
    required this.requirementId,
    required this.minimumReplicaCount,
    required this.distinctFailureDomains,
    required this.durabilityLevel,
    required this.consistencyModel,
    required this.required,
    this.artifactId,
    this.allowedRegions = const [],
    this.requiredStorageClasses = const [],
    this.metadata = const {},
  });

  final String requirementId;
  final String? artifactId;
  final int minimumReplicaCount;
  final int distinctFailureDomains;
  final List<String> allowedRegions;
  final List<PersistentArtifactStorageClass> requiredStorageClasses;
  final PersistentArtifactDurabilityLevel durabilityLevel;
  final PersistentArtifactConsistencyModel consistencyModel;
  final bool required;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        if (artifactId != null) 'artifactId': artifactId,
        'minimumReplicaCount': minimumReplicaCount,
        'distinctFailureDomains': distinctFailureDomains,
        if (allowedRegions.isNotEmpty) 'allowedRegions': allowedRegions,
        if (requiredStorageClasses.isNotEmpty)
          'requiredStorageClasses':
              requiredStorageClasses.map((e) => e.wireName).toList(),
        'durabilityLevel': durabilityLevel.wireName,
        'consistencyModel': consistencyModel.wireName,
        'required': required,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactReplicationRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactReplicationRequirement(
      requirementId: json['requirementId'] as String,
      artifactId: json['artifactId'] as String?,
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
      required: json['required'] as bool,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requirementId': requirementId,
        if (artifactId != null) 'artifactId': artifactId,
        'minimumReplicaCount': minimumReplicaCount,
        'distinctFailureDomains': distinctFailureDomains,
        if (allowedRegions.isNotEmpty)
          'allowedRegions': List<String>.from(allowedRegions)..sort(),
        if (requiredStorageClasses.isNotEmpty)
          'requiredStorageClasses':
              (requiredStorageClasses.map((e) => e.wireName).toList()..sort()),
        'durabilityLevel': durabilityLevel.wireName,
        'consistencyModel': consistencyModel.wireName,
        'required': required,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactReplicationRequirement copyWith({
    String? requirementId,
    String? artifactId,
    int? minimumReplicaCount,
    int? distinctFailureDomains,
    List<String>? allowedRegions,
    List<PersistentArtifactStorageClass>? requiredStorageClasses,
    PersistentArtifactDurabilityLevel? durabilityLevel,
    PersistentArtifactConsistencyModel? consistencyModel,
    bool? required,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactReplicationRequirement(
      requirementId: requirementId ?? this.requirementId,
      artifactId: artifactId ?? this.artifactId,
      minimumReplicaCount: minimumReplicaCount ?? this.minimumReplicaCount,
      distinctFailureDomains:
          distinctFailureDomains ?? this.distinctFailureDomains,
      allowedRegions: allowedRegions ?? this.allowedRegions,
      requiredStorageClasses:
          requiredStorageClasses ?? this.requiredStorageClasses,
      durabilityLevel: durabilityLevel ?? this.durabilityLevel,
      consistencyModel: consistencyModel ?? this.consistencyModel,
      required: required ?? this.required,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactReplicationRequirement &&
          requirementId == other.requirementId &&
          artifactId == other.artifactId &&
          minimumReplicaCount == other.minimumReplicaCount &&
          distinctFailureDomains == other.distinctFailureDomains &&
          paListEquals(allowedRegions, other.allowedRegions) &&
          paListEquals(requiredStorageClasses, other.requiredStorageClasses) &&
          durabilityLevel == other.durabilityLevel &&
          consistencyModel == other.consistencyModel &&
          required == other.required &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requirementId,
        artifactId,
        minimumReplicaCount,
        distinctFailureDomains,
        Object.hashAll(allowedRegions),
        Object.hashAll(requiredStorageClasses),
        durabilityLevel,
        consistencyModel,
        required,
        Object.hashAll(metadata.entries),
      );
}
