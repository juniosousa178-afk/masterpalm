import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative storage location reference.
///
/// Does not read, write, or access network resources.
class PersistentArtifactLocationReference {
  const PersistentArtifactLocationReference({
    required this.locationId,
    required this.locationType,
    required this.storageNamespace,
    required this.objectKey,
    required this.storageClass,
    required this.accessScope,
    required this.contentFingerprint,
    this.storageProviderId,
    this.region,
    this.versionId,
    this.metadata = const {},
  });

  final String locationId;
  final PersistentArtifactLocationType locationType;
  final String? storageProviderId;
  final String storageNamespace;
  final String objectKey;
  final String? region;
  final PersistentArtifactStorageClass storageClass;
  final PersistentArtifactAccessScope accessScope;
  final String? versionId;
  final String contentFingerprint;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'locationId': locationId,
        'locationType': locationType.wireName,
        if (storageProviderId != null) 'storageProviderId': storageProviderId,
        'storageNamespace': storageNamespace,
        'objectKey': objectKey,
        if (region != null) 'region': region,
        'storageClass': storageClass.wireName,
        'accessScope': accessScope.wireName,
        if (versionId != null) 'versionId': versionId,
        'contentFingerprint': contentFingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactLocationReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactLocationReference(
      locationId: json['locationId'] as String,
      locationType: PersistentArtifactLocationTypeX.fromWireName(
        json['locationType'] as String,
      ),
      storageProviderId: json['storageProviderId'] as String?,
      storageNamespace: json['storageNamespace'] as String,
      objectKey: json['objectKey'] as String,
      region: json['region'] as String?,
      storageClass: PersistentArtifactStorageClassX.fromWireName(
        json['storageClass'] as String,
      ),
      accessScope: PersistentArtifactAccessScopeX.fromWireName(
        json['accessScope'] as String,
      ),
      versionId: json['versionId'] as String?,
      contentFingerprint: json['contentFingerprint'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'locationId': locationId,
        'locationType': locationType.wireName,
        if (storageProviderId != null) 'storageProviderId': storageProviderId,
        'storageNamespace': storageNamespace,
        'objectKey': objectKey,
        if (region != null) 'region': region,
        'storageClass': storageClass.wireName,
        'accessScope': accessScope.wireName,
        if (versionId != null) 'versionId': versionId,
        'contentFingerprint': contentFingerprint,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactLocationReference copyWith({
    String? locationId,
    PersistentArtifactLocationType? locationType,
    String? storageProviderId,
    String? storageNamespace,
    String? objectKey,
    String? region,
    PersistentArtifactStorageClass? storageClass,
    PersistentArtifactAccessScope? accessScope,
    String? versionId,
    String? contentFingerprint,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactLocationReference(
      locationId: locationId ?? this.locationId,
      locationType: locationType ?? this.locationType,
      storageProviderId: storageProviderId ?? this.storageProviderId,
      storageNamespace: storageNamespace ?? this.storageNamespace,
      objectKey: objectKey ?? this.objectKey,
      region: region ?? this.region,
      storageClass: storageClass ?? this.storageClass,
      accessScope: accessScope ?? this.accessScope,
      versionId: versionId ?? this.versionId,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactLocationReference &&
          locationId == other.locationId &&
          locationType == other.locationType &&
          storageProviderId == other.storageProviderId &&
          storageNamespace == other.storageNamespace &&
          objectKey == other.objectKey &&
          region == other.region &&
          storageClass == other.storageClass &&
          accessScope == other.accessScope &&
          versionId == other.versionId &&
          contentFingerprint == other.contentFingerprint &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        locationId,
        locationType,
        storageProviderId,
        storageNamespace,
        objectKey,
        region,
        storageClass,
        accessScope,
        versionId,
        contentFingerprint,
        Object.hashAll(metadata.entries),
      );
}
