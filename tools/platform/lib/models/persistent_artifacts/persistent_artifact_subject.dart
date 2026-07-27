import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Subject of a persistable artifact.
///
/// References upstream modules by IDs and fingerprints only.
/// Does not carry bytes, local paths, or download URLs.
/// Domain fingerprint != cryptographic signature.
class PersistentArtifactSubject {
  const PersistentArtifactSubject({
    required this.subjectId,
    required this.artifactType,
    required this.projectId,
    required this.sourceModule,
    required this.sourceId,
    required this.sourceFingerprint,
    this.releaseId,
    this.contentType,
    this.schemaVersion,
    this.metadata = const {},
  });

  final String subjectId;
  final PersistentArtifactType artifactType;
  final String projectId;
  final String? releaseId;
  final String sourceModule;
  final String sourceId;
  final String sourceFingerprint;
  final String? contentType;
  final String? schemaVersion;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'artifactType': artifactType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'sourceModule': sourceModule,
        'sourceId': sourceId,
        'sourceFingerprint': sourceFingerprint,
        if (contentType != null) 'contentType': contentType,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactSubject.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactSubject(
      subjectId: json['subjectId'] as String,
      artifactType: PersistentArtifactTypeX.fromWireName(
        json['artifactType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      sourceModule: json['sourceModule'] as String,
      sourceId: json['sourceId'] as String,
      sourceFingerprint: json['sourceFingerprint'] as String,
      contentType: json['contentType'] as String?,
      schemaVersion: json['schemaVersion'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'subjectId': subjectId,
        'artifactType': artifactType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'sourceModule': sourceModule,
        'sourceId': sourceId,
        'sourceFingerprint': sourceFingerprint,
        if (contentType != null) 'contentType': contentType,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactSubject copyWith({
    String? subjectId,
    PersistentArtifactType? artifactType,
    String? projectId,
    String? releaseId,
    String? sourceModule,
    String? sourceId,
    String? sourceFingerprint,
    String? contentType,
    String? schemaVersion,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactSubject(
      subjectId: subjectId ?? this.subjectId,
      artifactType: artifactType ?? this.artifactType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      sourceModule: sourceModule ?? this.sourceModule,
      sourceId: sourceId ?? this.sourceId,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      contentType: contentType ?? this.contentType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactSubject &&
          subjectId == other.subjectId &&
          artifactType == other.artifactType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          sourceModule == other.sourceModule &&
          sourceId == other.sourceId &&
          sourceFingerprint == other.sourceFingerprint &&
          contentType == other.contentType &&
          schemaVersion == other.schemaVersion &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        subjectId,
        artifactType,
        projectId,
        releaseId,
        sourceModule,
        sourceId,
        sourceFingerprint,
        contentType,
        schemaVersion,
        Object.hashAll(metadata.entries),
      );
}
