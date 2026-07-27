import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';

import 'release_evidence_enums.dart';

/// Normative subject for release evidence collection and verification.
class ReleaseEvidenceSubject {
  const ReleaseEvidenceSubject({
    required this.subjectId,
    required this.subjectType,
    required this.projectId,
    this.releaseId,
    this.releaseVersion,
    this.commitId,
    this.branch,
    this.environment,
    this.artifactId,
    this.artifactFingerprint,
    this.identifiers = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String subjectId;
  final ReleaseEvidenceSubjectType subjectType;
  final String projectId;
  final String? releaseId;
  final String? releaseVersion;
  final String? commitId;
  final String? branch;
  final ReleaseEnvironment? environment;
  final String? artifactId;
  final String? artifactFingerprint;
  final Map<String, String> identifiers;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (releaseVersion != null) 'releaseVersion': releaseVersion,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        if (environment != null) 'environment': environment!.wireName,
        if (artifactId != null) 'artifactId': artifactId,
        if (artifactFingerprint != null)
          'artifactFingerprint': artifactFingerprint,
        if (identifiers.isNotEmpty) 'identifiers': identifiers,
        'schemaVersion': schemaVersion,
      };

  factory ReleaseEvidenceSubject.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceSubject(
      subjectId: json['subjectId'] as String,
      subjectType: ReleaseEvidenceSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      releaseVersion: json['releaseVersion'] as String?,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      environment: json['environment'] == null
          ? null
          : ReleaseEnvironmentX.fromWireName(json['environment'] as String),
      artifactId: json['artifactId'] as String?,
      artifactFingerprint: json['artifactFingerprint'] as String?,
      identifiers: Map.unmodifiable(
        (json['identifiers'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
    );
  }

  ReleaseEvidenceSubject copyWith({
    String? subjectId,
    ReleaseEvidenceSubjectType? subjectType,
    String? projectId,
    String? releaseId,
    String? releaseVersion,
    String? commitId,
    String? branch,
    ReleaseEnvironment? environment,
    String? artifactId,
    String? artifactFingerprint,
    Map<String, String>? identifiers,
    int? schemaVersion,
  }) {
    return ReleaseEvidenceSubject(
      subjectId: subjectId ?? this.subjectId,
      subjectType: subjectType ?? this.subjectType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      commitId: commitId ?? this.commitId,
      branch: branch ?? this.branch,
      environment: environment ?? this.environment,
      artifactId: artifactId ?? this.artifactId,
      artifactFingerprint: artifactFingerprint ?? this.artifactFingerprint,
      identifiers: identifiers ?? this.identifiers,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceSubject &&
          runtimeType == other.runtimeType &&
          subjectId == other.subjectId &&
          subjectType == other.subjectType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          releaseVersion == other.releaseVersion &&
          commitId == other.commitId &&
          branch == other.branch &&
          environment == other.environment &&
          artifactId == other.artifactId &&
          artifactFingerprint == other.artifactFingerprint &&
          _mapEquals(identifiers, other.identifiers) &&
          schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        subjectId,
        subjectType,
        projectId,
        releaseId,
        releaseVersion,
        commitId,
        branch,
        environment,
        artifactId,
        artifactFingerprint,
        Object.hashAll(identifiers.entries),
        schemaVersion,
      );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
