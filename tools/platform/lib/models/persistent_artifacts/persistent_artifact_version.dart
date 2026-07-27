import 'persistent_artifact_content_descriptor.dart';
import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_reference_models.dart';

/// Declarative version descriptor for a persistent artifact.
///
/// Represents version lineage only — does not copy content or execute lifecycle.
/// Domain fingerprint != cryptographic signature.
class PersistentArtifactVersion {
  const PersistentArtifactVersion({
    required this.artifactId,
    required this.versionId,
    required this.revision,
    required this.status,
    required this.contentDescriptor,
    required this.createdAt,
    this.parentVersionId,
    this.supersededAt,
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String artifactId;
  final String versionId;
  final int revision;
  final String? parentVersionId;
  final PersistentArtifactVersionStatus status;
  final PersistentArtifactContentDescriptor contentDescriptor;
  final String createdAt;
  final String? supersededAt;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'versionId': versionId,
        'revision': revision,
        if (parentVersionId != null) 'parentVersionId': parentVersionId,
        'status': status.wireName,
        'contentDescriptor': contentDescriptor.toJson(),
        'createdAt': createdAt,
        if (supersededAt != null) 'supersededAt': supersededAt,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactVersion.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactVersion(
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      revision: json['revision'] as int,
      parentVersionId: json['parentVersionId'] as String?,
      status: PersistentArtifactVersionStatusX.fromWireName(
        json['status'] as String,
      ),
      contentDescriptor: PersistentArtifactContentDescriptor.fromJson(
        json['contentDescriptor'] as Map<String, dynamic>,
      ),
      createdAt: json['createdAt'] as String,
      supersededAt: json['supersededAt'] as String?,
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'artifactId': artifactId,
        'versionId': versionId,
        'revision': revision,
        if (parentVersionId != null) 'parentVersionId': parentVersionId,
        'status': status.wireName,
        'contentDescriptor': contentDescriptor.toComparableJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
            sourceReferences.map((e) => e.toComparableJson()),
            'sourceId',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactVersion copyWith({
    String? artifactId,
    String? versionId,
    int? revision,
    String? parentVersionId,
    PersistentArtifactVersionStatus? status,
    PersistentArtifactContentDescriptor? contentDescriptor,
    String? createdAt,
    String? supersededAt,
    List<PersistentArtifactSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactVersion(
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      revision: revision ?? this.revision,
      parentVersionId: parentVersionId ?? this.parentVersionId,
      status: status ?? this.status,
      contentDescriptor: contentDescriptor ?? this.contentDescriptor,
      createdAt: createdAt ?? this.createdAt,
      supersededAt: supersededAt ?? this.supersededAt,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactVersion &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          revision == other.revision &&
          parentVersionId == other.parentVersionId &&
          status == other.status &&
          contentDescriptor == other.contentDescriptor &&
          createdAt == other.createdAt &&
          supersededAt == other.supersededAt &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactId,
        versionId,
        revision,
        parentVersionId,
        status,
        contentDescriptor,
        createdAt,
        supersededAt,
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
