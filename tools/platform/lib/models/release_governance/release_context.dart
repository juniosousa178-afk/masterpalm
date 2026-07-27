import 'release_governance_enums.dart';

/// Normative release identity fields.
class ReleaseIdentifier {
  const ReleaseIdentifier({
    required this.projectId,
    required this.version,
    this.commitId,
    this.environment,
    this.releaseType,
  });

  final String projectId;
  final String version;
  final String? commitId;
  final ReleaseEnvironment? environment;
  final ReleaseType? releaseType;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'version': version,
        if (commitId != null) 'commitId': commitId,
        if (environment != null) 'environment': environment!.wireName,
        if (releaseType != null) 'releaseType': releaseType!.wireName,
      };

  factory ReleaseIdentifier.fromJson(Map<String, dynamic> json) {
    return ReleaseIdentifier(
      projectId: json['projectId'] as String,
      version: json['version'] as String,
      commitId: json['commitId'] as String?,
      environment: json['environment'] == null
          ? null
          : ReleaseEnvironmentX.fromWireName(json['environment'] as String),
      releaseType: json['releaseType'] == null
          ? null
          : ReleaseTypeX.fromWireName(json['releaseType'] as String),
    );
  }
}

/// Reference to a release artifact without duplicating payload.
class ReleaseArtifactReference {
  const ReleaseArtifactReference({
    required this.artifactId,
    required this.artifactType,
    this.fingerprint,
    this.schemaVersion,
    this.metadata = const {},
  });

  final String artifactId;
  final String artifactType;
  final String? fingerprint;
  final int? schemaVersion;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'artifactType': artifactType,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseArtifactReference.fromJson(Map<String, dynamic> json) {
    return ReleaseArtifactReference(
      artifactId: json['artifactId'] as String,
      artifactType: json['artifactType'] as String,
      fingerprint: json['fingerprint'] as String?,
      schemaVersion: json['schemaVersion'] as int?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Immutable context for the release being governed.
class ReleaseContext {
  const ReleaseContext({
    required this.projectId,
    required this.releaseId,
    required this.releaseName,
    required this.releaseVersion,
    required this.commitId,
    required this.branch,
    required this.environment,
    required this.releaseType,
    required this.requestedAt,
    required this.requestedBy,
    this.targetDate,
    this.artifactReferences = const [],
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String projectId;
  final String releaseId;
  final String releaseName;
  final String releaseVersion;
  final String commitId;
  final String branch;
  final ReleaseEnvironment environment;
  final ReleaseType releaseType;
  final String requestedAt;
  final String requestedBy;
  final String? targetDate;
  final List<ReleaseArtifactReference> artifactReferences;
  final Map<String, String> metadata;
  final int schemaVersion;

  ReleaseIdentifier get identifier => ReleaseIdentifier(
        projectId: projectId,
        version: releaseVersion,
        commitId: commitId,
        environment: environment,
        releaseType: releaseType,
      );

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'releaseId': releaseId,
        'releaseName': releaseName,
        'releaseVersion': releaseVersion,
        'commitId': commitId,
        'branch': branch,
        'environment': environment.wireName,
        'releaseType': releaseType.wireName,
        'requestedAt': requestedAt,
        'requestedBy': requestedBy,
        if (targetDate != null) 'targetDate': targetDate,
        'artifactReferences':
            artifactReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
        'schemaVersion': schemaVersion,
      };

  factory ReleaseContext.fromJson(Map<String, dynamic> json) {
    return ReleaseContext(
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      releaseName: json['releaseName'] as String,
      releaseVersion: json['releaseVersion'] as String,
      commitId: json['commitId'] as String,
      branch: json['branch'] as String,
      environment: ReleaseEnvironmentX.fromWireName(
        json['environment'] as String,
      ),
      releaseType: ReleaseTypeX.fromWireName(json['releaseType'] as String),
      requestedAt: json['requestedAt'] as String,
      requestedBy: json['requestedBy'] as String,
      targetDate: json['targetDate'] as String?,
      artifactReferences: (json['artifactReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseArtifactReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
    );
  }
}
