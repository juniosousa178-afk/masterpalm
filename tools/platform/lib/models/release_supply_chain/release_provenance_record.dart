import 'release_provenance_models.dart';
import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Metadata for a release provenance record.
class ReleaseProvenanceMetadata {
  const ReleaseProvenanceMetadata({
    required this.provenanceRecordId,
    required this.projectId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.recordedAt,
    required this.status,
    required this.fingerprint,
    this.releaseId,
    this.commitId,
    this.releaseEvidenceBundleId,
    this.qualityGateSnapshotId,
    this.releaseDecisionSnapshotId,
    this.artifactCount = 0,
    this.relationCount = 0,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String provenanceRecordId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? releaseEvidenceBundleId;
  final String? qualityGateSnapshotId;
  final String? releaseDecisionSnapshotId;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String recordedAt;
  final ReleaseProvenanceStatus status;
  final String fingerprint;
  final int artifactCount;
  final int relationCount;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'provenanceRecordId': provenanceRecordId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (releaseDecisionSnapshotId != null)
          'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        'recordedAt': recordedAt,
        'status': status.wireName,
        'fingerprint': fingerprint,
        'artifactCount': artifactCount,
        'relationCount': relationCount,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseProvenanceMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceMetadata(
      provenanceRecordId: json['provenanceRecordId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      releaseDecisionSnapshotId: json['releaseDecisionSnapshotId'] as String?,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      recordedAt: json['recordedAt'] as String,
      status: ReleaseProvenanceStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      artifactCount: json['artifactCount'] as int? ?? 0,
      relationCount: json['relationCount'] as int? ?? 0,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (releaseDecisionSnapshotId != null)
          'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'status': status.wireName,
        'artifactCount': artifactCount,
        'relationCount': relationCount,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ReleaseProvenanceMetadata copyWith({
    String? provenanceRecordId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? releaseEvidenceBundleId,
    String? qualityGateSnapshotId,
    String? releaseDecisionSnapshotId,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? recordedAt,
    ReleaseProvenanceStatus? status,
    String? fingerprint,
    int? artifactCount,
    int? relationCount,
    List<String>? limitations,
  }) {
    return ReleaseProvenanceMetadata(
      provenanceRecordId: provenanceRecordId ?? this.provenanceRecordId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      qualityGateSnapshotId:
          qualityGateSnapshotId ?? this.qualityGateSnapshotId,
      releaseDecisionSnapshotId:
          releaseDecisionSnapshotId ?? this.releaseDecisionSnapshotId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      recordedAt: recordedAt ?? this.recordedAt,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      artifactCount: artifactCount ?? this.artifactCount,
      relationCount: relationCount ?? this.relationCount,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceMetadata &&
          provenanceRecordId == other.provenanceRecordId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          qualityGateSnapshotId == other.qualityGateSnapshotId &&
          releaseDecisionSnapshotId == other.releaseDecisionSnapshotId &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          recordedAt == other.recordedAt &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          artifactCount == other.artifactCount &&
          relationCount == other.relationCount &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        provenanceRecordId,
        projectId,
        releaseId,
        commitId,
        releaseEvidenceBundleId,
        qualityGateSnapshotId,
        releaseDecisionSnapshotId,
        schemaVersion,
        canonicalizationVersion,
        createdAt,
        recordedAt,
        status,
        fingerprint,
        artifactCount,
        relationCount,
        Object.hashAll(limitations),
      );
}

/// Immutable release provenance record aggregating published artifact lineage.
class ReleaseProvenanceRecord {
  const ReleaseProvenanceRecord({
    required this.metadata,
    required this.subject,
    required this.identity,
    required this.fingerprintDescriptor,
    required this.artifacts,
    required this.relations,
    this.warnings = const [],
    this.explanations = const [],
    this.limitations = const [],
  });

  final ReleaseProvenanceMetadata metadata;
  final ReleaseProvenanceSubject subject;
  final ReleaseProvenanceIdentity identity;
  final ReleaseProvenanceFingerprint fingerprintDescriptor;
  final List<ReleaseProvenanceArtifact> artifacts;
  final List<ReleaseProvenanceRelation> relations;
  final List<String> warnings;
  final List<String> explanations;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'subject': subject.toJson(),
        'identity': identity.toJson(),
        'fingerprintDescriptor': fingerprintDescriptor.toJson(),
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
        'relations': relations.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (explanations.isNotEmpty) 'explanations': explanations,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseProvenanceRecord.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceRecord(
      metadata: ReleaseProvenanceMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      subject: ReleaseProvenanceSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      identity: ReleaseProvenanceIdentity.fromJson(
        json['identity'] as Map<String, dynamic>,
      ),
      fingerprintDescriptor: ReleaseProvenanceFingerprint.fromJson(
        json['fingerprintDescriptor'] as Map<String, dynamic>,
      ),
      artifacts: List.unmodifiable(
        (json['artifacts'] as List<dynamic>)
            .map(
              (e) => ReleaseProvenanceArtifact.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      relations: List.unmodifiable(
        (json['relations'] as List<dynamic>)
            .map(
              (e) => ReleaseProvenanceRelation.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      explanations: List.unmodifiable(
        (json['explanations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final sortedArtifacts = artifacts.map((e) => e.toComparableJson()).toList()
      ..sort((a, b) =>
          (a['artifactId'] as String).compareTo(b['artifactId'] as String));
    final sortedRelations = relations.map((e) => e.toComparableJson()).toList()
      ..sort((a, b) =>
          (a['relationId'] as String).compareTo(b['relationId'] as String));
    return {
      'metadata': metadata.toComparableJson(),
      'subject': subject.toComparableJson(),
      'identity': identity.toComparableJson(),
      'fingerprintDescriptor': fingerprintDescriptor.toComparableJson(),
      'artifacts': sortedArtifacts,
      'relations': sortedRelations,
      if (warnings.isNotEmpty) 'warnings': List<String>.from(warnings)..sort(),
      if (explanations.isNotEmpty)
        'explanations': List<String>.from(explanations)..sort(),
      if (limitations.isNotEmpty)
        'limitations': List<String>.from(limitations)..sort(),
    };
  }

  ReleaseProvenanceRecord copyWith({
    ReleaseProvenanceMetadata? metadata,
    ReleaseProvenanceSubject? subject,
    ReleaseProvenanceIdentity? identity,
    ReleaseProvenanceFingerprint? fingerprintDescriptor,
    List<ReleaseProvenanceArtifact>? artifacts,
    List<ReleaseProvenanceRelation>? relations,
    List<String>? warnings,
    List<String>? explanations,
    List<String>? limitations,
  }) {
    return ReleaseProvenanceRecord(
      metadata: metadata ?? this.metadata,
      subject: subject ?? this.subject,
      identity: identity ?? this.identity,
      fingerprintDescriptor:
          fingerprintDescriptor ?? this.fingerprintDescriptor,
      artifacts: artifacts ?? this.artifacts,
      relations: relations ?? this.relations,
      warnings: warnings ?? this.warnings,
      explanations: explanations ?? this.explanations,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceRecord &&
          metadata == other.metadata &&
          subject == other.subject &&
          identity == other.identity &&
          fingerprintDescriptor == other.fingerprintDescriptor &&
          rscListEquals(artifacts, other.artifacts) &&
          rscListEquals(relations, other.relations) &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(explanations, other.explanations) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        metadata,
        subject,
        identity,
        fingerprintDescriptor,
        Object.hashAll(artifacts),
        Object.hashAll(relations),
        Object.hashAll(warnings),
        Object.hashAll(explanations),
        Object.hashAll(limitations),
      );
}
