import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Deterministic fingerprint descriptor for release provenance records.
class ReleaseProvenanceFingerprint {
  const ReleaseProvenanceFingerprint({
    required this.algorithm,
    required this.value,
    this.canonicalizationVersion = currentCanonicalizationVersion,
  });

  static const String defaultAlgorithm = 'sha256';
  static const int currentCanonicalizationVersion = 1;

  final String algorithm;
  final String value;
  final int canonicalizationVersion;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'value': value,
        'canonicalizationVersion': canonicalizationVersion,
      };

  factory ReleaseProvenanceFingerprint.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceFingerprint(
      algorithm: json['algorithm'] as String? ?? defaultAlgorithm,
      value: json['value'] as String,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'algorithm': algorithm,
        'value': value,
        'canonicalizationVersion': canonicalizationVersion,
      };

  ReleaseProvenanceFingerprint copyWith({
    String? algorithm,
    String? value,
    int? canonicalizationVersion,
  }) {
    return ReleaseProvenanceFingerprint(
      algorithm: algorithm ?? this.algorithm,
      value: value ?? this.value,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceFingerprint &&
          algorithm == other.algorithm &&
          value == other.value &&
          canonicalizationVersion == other.canonicalizationVersion;

  @override
  int get hashCode => Object.hash(algorithm, value, canonicalizationVersion);
}

/// Normative identity for a release provenance subject.
class ReleaseProvenanceIdentity {
  const ReleaseProvenanceIdentity({
    required this.identityId,
    required this.subjectType,
    required this.projectId,
    this.releaseId,
    this.commitId,
    this.artifactId,
    this.bundleId,
    this.identifiers = const {},
  });

  final String identityId;
  final ReleaseProvenanceSubjectType subjectType;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? artifactId;
  final String? bundleId;
  final Map<String, String> identifiers;

  Map<String, dynamic> toJson() => {
        'identityId': identityId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (artifactId != null) 'artifactId': artifactId,
        if (bundleId != null) 'bundleId': bundleId,
        if (identifiers.isNotEmpty) 'identifiers': identifiers,
      };

  factory ReleaseProvenanceIdentity.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceIdentity(
      identityId: json['identityId'] as String,
      subjectType: ReleaseProvenanceSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      artifactId: json['artifactId'] as String?,
      bundleId: json['bundleId'] as String?,
      identifiers: Map.unmodifiable(
        (json['identifiers'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'identityId': identityId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (artifactId != null) 'artifactId': artifactId,
        if (bundleId != null) 'bundleId': bundleId,
        if (identifiers.isNotEmpty)
          'identifiers': Map.fromEntries(
            identifiers.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ReleaseProvenanceIdentity copyWith({
    String? identityId,
    ReleaseProvenanceSubjectType? subjectType,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? artifactId,
    String? bundleId,
    Map<String, String>? identifiers,
  }) {
    return ReleaseProvenanceIdentity(
      identityId: identityId ?? this.identityId,
      subjectType: subjectType ?? this.subjectType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      artifactId: artifactId ?? this.artifactId,
      bundleId: bundleId ?? this.bundleId,
      identifiers: identifiers ?? this.identifiers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceIdentity &&
          identityId == other.identityId &&
          subjectType == other.subjectType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          artifactId == other.artifactId &&
          bundleId == other.bundleId &&
          rscMapEquals(identifiers, other.identifiers);

  @override
  int get hashCode => Object.hash(
        identityId,
        subjectType,
        projectId,
        releaseId,
        commitId,
        artifactId,
        bundleId,
        Object.hashAll(identifiers.entries),
      );
}

/// Subject reference for release provenance.
class ReleaseProvenanceSubject {
  const ReleaseProvenanceSubject({
    required this.subjectId,
    required this.subjectType,
    required this.projectId,
    this.releaseId,
    this.commitId,
    this.displayName,
    this.identifiers = const {},
  });

  final String subjectId;
  final ReleaseProvenanceSubjectType subjectType;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? displayName;
  final Map<String, String> identifiers;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (displayName != null) 'displayName': displayName,
        if (identifiers.isNotEmpty) 'identifiers': identifiers,
      };

  factory ReleaseProvenanceSubject.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceSubject(
      subjectId: json['subjectId'] as String,
      subjectType: ReleaseProvenanceSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      displayName: json['displayName'] as String?,
      identifiers: Map.unmodifiable(
        (json['identifiers'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (displayName != null) 'displayName': displayName,
        if (identifiers.isNotEmpty)
          'identifiers': Map.fromEntries(
            identifiers.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ReleaseProvenanceSubject copyWith({
    String? subjectId,
    ReleaseProvenanceSubjectType? subjectType,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? displayName,
    Map<String, String>? identifiers,
  }) {
    return ReleaseProvenanceSubject(
      subjectId: subjectId ?? this.subjectId,
      subjectType: subjectType ?? this.subjectType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      displayName: displayName ?? this.displayName,
      identifiers: identifiers ?? this.identifiers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceSubject &&
          subjectId == other.subjectId &&
          subjectType == other.subjectType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          displayName == other.displayName &&
          rscMapEquals(identifiers, other.identifiers);

  @override
  int get hashCode => Object.hash(
        subjectId,
        subjectType,
        projectId,
        releaseId,
        commitId,
        displayName,
        Object.hashAll(identifiers.entries),
      );
}

/// Published artifact reference within release provenance.
class ReleaseProvenanceArtifact {
  const ReleaseProvenanceArtifact({
    required this.artifactId,
    required this.artifactType,
    required this.fingerprint,
    this.snapshotId,
    this.uri,
    this.metadata = const {},
  });

  final String artifactId;
  final ReleaseProvenanceArtifactType artifactType;
  final String fingerprint;
  final String? snapshotId;
  final String? uri;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'artifactType': artifactType.wireName,
        'fingerprint': fingerprint,
        if (snapshotId != null) 'snapshotId': snapshotId,
        if (uri != null) 'uri': uri,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseProvenanceArtifact.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceArtifact(
      artifactId: json['artifactId'] as String,
      artifactType: ReleaseProvenanceArtifactTypeX.fromWireName(
        json['artifactType'] as String,
      ),
      fingerprint: json['fingerprint'] as String,
      snapshotId: json['snapshotId'] as String?,
      uri: json['uri'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'artifactId': artifactId,
        'artifactType': artifactType.wireName,
        'fingerprint': fingerprint,
        if (snapshotId != null) 'snapshotId': snapshotId,
        if (uri != null) 'uri': uri,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ReleaseProvenanceArtifact copyWith({
    String? artifactId,
    ReleaseProvenanceArtifactType? artifactType,
    String? fingerprint,
    String? snapshotId,
    String? uri,
    Map<String, String>? metadata,
  }) {
    return ReleaseProvenanceArtifact(
      artifactId: artifactId ?? this.artifactId,
      artifactType: artifactType ?? this.artifactType,
      fingerprint: fingerprint ?? this.fingerprint,
      snapshotId: snapshotId ?? this.snapshotId,
      uri: uri ?? this.uri,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceArtifact &&
          artifactId == other.artifactId &&
          artifactType == other.artifactType &&
          fingerprint == other.fingerprint &&
          snapshotId == other.snapshotId &&
          uri == other.uri &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactId,
        artifactType,
        fingerprint,
        snapshotId,
        uri,
        Object.hashAll(metadata.entries),
      );
}

/// Directed relation between provenance artifacts.
class ReleaseProvenanceRelation {
  const ReleaseProvenanceRelation({
    required this.relationId,
    required this.relationType,
    required this.fromArtifactId,
    required this.toArtifactId,
    this.description,
    this.metadata = const {},
  });

  final String relationId;
  final ReleaseProvenanceRelationType relationType;
  final String fromArtifactId;
  final String toArtifactId;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'relationId': relationId,
        'relationType': relationType.wireName,
        'fromArtifactId': fromArtifactId,
        'toArtifactId': toArtifactId,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseProvenanceRelation.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceRelation(
      relationId: json['relationId'] as String,
      relationType: ReleaseProvenanceRelationTypeX.fromWireName(
        json['relationType'] as String,
      ),
      fromArtifactId: json['fromArtifactId'] as String,
      toArtifactId: json['toArtifactId'] as String,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'relationId': relationId,
        'relationType': relationType.wireName,
        'fromArtifactId': fromArtifactId,
        'toArtifactId': toArtifactId,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ReleaseProvenanceRelation copyWith({
    String? relationId,
    ReleaseProvenanceRelationType? relationType,
    String? fromArtifactId,
    String? toArtifactId,
    String? description,
    Map<String, String>? metadata,
  }) {
    return ReleaseProvenanceRelation(
      relationId: relationId ?? this.relationId,
      relationType: relationType ?? this.relationType,
      fromArtifactId: fromArtifactId ?? this.fromArtifactId,
      toArtifactId: toArtifactId ?? this.toArtifactId,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseProvenanceRelation &&
          relationId == other.relationId &&
          relationType == other.relationType &&
          fromArtifactId == other.fromArtifactId &&
          toArtifactId == other.toArtifactId &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        relationId,
        relationType,
        fromArtifactId,
        toArtifactId,
        description,
        Object.hashAll(metadata.entries),
      );
}
