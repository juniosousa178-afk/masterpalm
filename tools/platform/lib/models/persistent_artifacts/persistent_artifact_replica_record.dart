import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_location_reference.dart';
import 'persistent_artifact_validation_result.dart';

/// Declarative replica record for a persistent artifact.
///
/// Represents a declared replica only — does not copy content or verify physically.
class PersistentArtifactReplicaRecord {
  const PersistentArtifactReplicaRecord({
    required this.replicaId,
    required this.artifactId,
    required this.versionId,
    required this.locationReference,
    required this.status,
    required this.contentFingerprint,
    this.replicatedAt,
    this.lastVerifiedAt,
    this.issues = const [],
    this.metadata = const {},
  });

  final String replicaId;
  final String artifactId;
  final String versionId;
  final PersistentArtifactLocationReference locationReference;
  final PersistentArtifactReplicationStatus status;
  final String contentFingerprint;
  final String? replicatedAt;
  final String? lastVerifiedAt;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'replicaId': replicaId,
        'artifactId': artifactId,
        'versionId': versionId,
        'locationReference': locationReference.toJson(),
        'status': status.wireName,
        'contentFingerprint': contentFingerprint,
        if (replicatedAt != null) 'replicatedAt': replicatedAt,
        if (lastVerifiedAt != null) 'lastVerifiedAt': lastVerifiedAt,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactReplicaRecord.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactReplicaRecord(
      replicaId: json['replicaId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      locationReference: PersistentArtifactLocationReference.fromJson(
        json['locationReference'] as Map<String, dynamic>,
      ),
      status: PersistentArtifactReplicationStatusX.fromWireName(
        json['status'] as String,
      ),
      contentFingerprint: json['contentFingerprint'] as String,
      replicatedAt: json['replicatedAt'] as String?,
      lastVerifiedAt: json['lastVerifiedAt'] as String?,
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
        'replicaId': replicaId,
        'artifactId': artifactId,
        'versionId': versionId,
        'locationReference': locationReference.toComparableJson(),
        'status': status.wireName,
        'contentFingerprint': contentFingerprint,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactReplicaRecord copyWith({
    String? replicaId,
    String? artifactId,
    String? versionId,
    PersistentArtifactLocationReference? locationReference,
    PersistentArtifactReplicationStatus? status,
    String? contentFingerprint,
    String? replicatedAt,
    String? lastVerifiedAt,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactReplicaRecord(
      replicaId: replicaId ?? this.replicaId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      locationReference: locationReference ?? this.locationReference,
      status: status ?? this.status,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      replicatedAt: replicatedAt ?? this.replicatedAt,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactReplicaRecord &&
          replicaId == other.replicaId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          locationReference == other.locationReference &&
          status == other.status &&
          contentFingerprint == other.contentFingerprint &&
          replicatedAt == other.replicatedAt &&
          lastVerifiedAt == other.lastVerifiedAt &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        replicaId,
        artifactId,
        versionId,
        locationReference,
        status,
        contentFingerprint,
        replicatedAt,
        lastVerifiedAt,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}
