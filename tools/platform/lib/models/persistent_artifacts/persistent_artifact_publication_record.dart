import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_location_reference.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_validation_result.dart';

/// Declarative publication record for a persistent artifact.
///
/// Represents declared publication only — does not upload or authorize release.
/// Partial publication remains partial; failure is not unavailable.
class PersistentArtifactPublicationRecord {
  const PersistentArtifactPublicationRecord({
    required this.publicationId,
    required this.artifactId,
    required this.versionId,
    required this.publicationStatus,
    this.publishedLocations = const [],
    this.publishedAt,
    this.publisherIdentityId,
    this.sourceReferences = const [],
    this.issues = const [],
    this.metadata = const {},
  });

  final String publicationId;
  final String artifactId;
  final String versionId;
  final PersistentArtifactPublicationStatus publicationStatus;
  final List<PersistentArtifactLocationReference> publishedLocations;
  final String? publishedAt;
  final String? publisherIdentityId;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'publicationId': publicationId,
        'artifactId': artifactId,
        'versionId': versionId,
        'publicationStatus': publicationStatus.wireName,
        if (publishedLocations.isNotEmpty)
          'publishedLocations':
              publishedLocations.map((e) => e.toJson()).toList(),
        if (publishedAt != null) 'publishedAt': publishedAt,
        if (publisherIdentityId != null)
          'publisherIdentityId': publisherIdentityId,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactPublicationRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactPublicationRecord(
      publicationId: json['publicationId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      publicationStatus: PersistentArtifactPublicationStatusX.fromWireName(
        json['publicationStatus'] as String,
      ),
      publishedLocations: List.unmodifiable(
        (json['publishedLocations'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactLocationReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      publishedAt: json['publishedAt'] as String?,
      publisherIdentityId: json['publisherIdentityId'] as String?,
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIssue.fromJson(
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
        'publicationId': publicationId,
        'artifactId': artifactId,
        'versionId': versionId,
        'publicationStatus': publicationStatus.wireName,
        if (publishedLocations.isNotEmpty)
          'publishedLocations': paSortedComparableList(
            publishedLocations.map((e) => e.toComparableJson()),
            'locationId',
          ),
        if (publisherIdentityId != null)
          'publisherIdentityId': publisherIdentityId,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
            sourceReferences.map((e) => e.toComparableJson()),
            'sourceId',
          ),
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactPublicationRecord copyWith({
    String? publicationId,
    String? artifactId,
    String? versionId,
    PersistentArtifactPublicationStatus? publicationStatus,
    List<PersistentArtifactLocationReference>? publishedLocations,
    String? publishedAt,
    String? publisherIdentityId,
    List<PersistentArtifactSourceReference>? sourceReferences,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactPublicationRecord(
      publicationId: publicationId ?? this.publicationId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      publicationStatus: publicationStatus ?? this.publicationStatus,
      publishedLocations: publishedLocations ?? this.publishedLocations,
      publishedAt: publishedAt ?? this.publishedAt,
      publisherIdentityId: publisherIdentityId ?? this.publisherIdentityId,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactPublicationRecord &&
          publicationId == other.publicationId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          publicationStatus == other.publicationStatus &&
          paListEquals(publishedLocations, other.publishedLocations) &&
          publishedAt == other.publishedAt &&
          publisherIdentityId == other.publisherIdentityId &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        publicationId,
        artifactId,
        versionId,
        publicationStatus,
        Object.hashAll(publishedLocations),
        publishedAt,
        publisherIdentityId,
        Object.hashAll(sourceReferences),
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}
