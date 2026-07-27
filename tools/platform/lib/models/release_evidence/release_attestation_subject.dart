import '../release_governance/release_governance_enums.dart';
import 'release_evidence_enums.dart';

/// Subject of an attestation statement.
class ReleaseAttestationSubject {
  const ReleaseAttestationSubject({
    required this.subjectId,
    required this.subjectType,
    required this.artifactId,
    required this.artifactFingerprint,
    required this.projectId,
    required this.schemaVersion,
    this.releaseId,
    this.commitId,
    this.environment,
    this.identifiers = const {},
  });

  final String subjectId;
  final ReleaseEvidenceSubjectType subjectType;
  final String artifactId;
  final String artifactFingerprint;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final ReleaseEnvironment? environment;
  final int schemaVersion;
  final Map<String, String> identifiers;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'artifactId': artifactId,
        'artifactFingerprint': artifactFingerprint,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (environment != null) 'environment': environment!.wireName,
        'schemaVersion': schemaVersion,
        if (identifiers.isNotEmpty) 'identifiers': identifiers,
      };

  factory ReleaseAttestationSubject.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationSubject(
      subjectId: json['subjectId'] as String,
      subjectType: ReleaseEvidenceSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      artifactId: json['artifactId'] as String,
      artifactFingerprint: json['artifactFingerprint'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      environment: json['environment'] == null
          ? null
          : ReleaseEnvironmentX.fromWireName(json['environment'] as String),
      schemaVersion: json['schemaVersion'] as int,
      identifiers: Map.unmodifiable(
        (json['identifiers'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
