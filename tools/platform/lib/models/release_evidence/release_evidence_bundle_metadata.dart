import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';

/// Normative metadata for a release evidence bundle.
class ReleaseEvidenceBundleMetadata {
  const ReleaseEvidenceBundleMetadata({
    required this.bundleId,
    required this.projectId,
    required this.releaseId,
    required this.releaseVersion,
    required this.commitId,
    required this.environment,
    required this.policyId,
    required this.policyVersion,
    required this.policyFingerprint,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.sourceSetFingerprint,
    required this.requestFingerprint,
    required this.createdAt,
    required this.evaluatedAt,
    required this.referenceTime,
    required this.evidenceCount,
    required this.attestationCount,
    required this.fingerprint,
  });

  static const int currentSchemaVersion = 1;

  final String bundleId;
  final String projectId;
  final String releaseId;
  final String releaseVersion;
  final String commitId;
  final ReleaseEnvironment environment;
  final String policyId;
  final int policyVersion;
  final String policyFingerprint;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final String sourceSetFingerprint;
  final String requestFingerprint;
  final String createdAt;
  final String evaluatedAt;
  final String referenceTime;
  final int evidenceCount;
  final int attestationCount;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'bundleId': bundleId,
        'projectId': projectId,
        'releaseId': releaseId,
        'releaseVersion': releaseVersion,
        'commitId': commitId,
        'environment': environment.wireName,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyFingerprint': policyFingerprint,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'sourceSetFingerprint': sourceSetFingerprint,
        'requestFingerprint': requestFingerprint,
        'createdAt': createdAt,
        'evaluatedAt': evaluatedAt,
        'referenceTime': referenceTime,
        'evidenceCount': evidenceCount,
        'attestationCount': attestationCount,
        'fingerprint': fingerprint,
      };

  factory ReleaseEvidenceBundleMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceBundleMetadata(
      bundleId: json['bundleId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      releaseVersion: json['releaseVersion'] as String,
      commitId: json['commitId'] as String,
      environment: ReleaseEnvironmentX.fromWireName(
        json['environment'] as String,
      ),
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyFingerprint: json['policyFingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      calculationVersion: json['calculationVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      sourceSetFingerprint: json['sourceSetFingerprint'] as String,
      requestFingerprint: json['requestFingerprint'] as String,
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String,
      referenceTime: json['referenceTime'] as String,
      evidenceCount: json['evidenceCount'] as int,
      attestationCount: json['attestationCount'] as int,
      fingerprint: json['fingerprint'] as String,
    );
  }

  ReleaseEvidenceBundleMetadata copyWith({
    String? bundleId,
    String? projectId,
    String? releaseId,
    String? releaseVersion,
    String? commitId,
    ReleaseEnvironment? environment,
    String? policyId,
    int? policyVersion,
    String? policyFingerprint,
    int? schemaVersion,
    int? calculationVersion,
    int? canonicalizationVersion,
    String? sourceSetFingerprint,
    String? requestFingerprint,
    String? createdAt,
    String? evaluatedAt,
    String? referenceTime,
    int? evidenceCount,
    int? attestationCount,
    String? fingerprint,
  }) {
    return ReleaseEvidenceBundleMetadata(
      bundleId: bundleId ?? this.bundleId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      commitId: commitId ?? this.commitId,
      environment: environment ?? this.environment,
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      policyFingerprint: policyFingerprint ?? this.policyFingerprint,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      calculationVersion: calculationVersion ?? this.calculationVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      sourceSetFingerprint: sourceSetFingerprint ?? this.sourceSetFingerprint,
      requestFingerprint: requestFingerprint ?? this.requestFingerprint,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      referenceTime: referenceTime ?? this.referenceTime,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      attestationCount: attestationCount ?? this.attestationCount,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceBundleMetadata &&
          runtimeType == other.runtimeType &&
          bundleId == other.bundleId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          releaseVersion == other.releaseVersion &&
          commitId == other.commitId &&
          environment == other.environment &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyFingerprint == other.policyFingerprint &&
          schemaVersion == other.schemaVersion &&
          calculationVersion == other.calculationVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          sourceSetFingerprint == other.sourceSetFingerprint &&
          requestFingerprint == other.requestFingerprint &&
          createdAt == other.createdAt &&
          evaluatedAt == other.evaluatedAt &&
          referenceTime == other.referenceTime &&
          evidenceCount == other.evidenceCount &&
          attestationCount == other.attestationCount &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(
        bundleId,
        projectId,
        releaseId,
        releaseVersion,
        commitId,
        environment,
        policyId,
        policyVersion,
        policyFingerprint,
        schemaVersion,
        calculationVersion,
        canonicalizationVersion,
        sourceSetFingerprint,
        requestFingerprint,
        createdAt,
        evaluatedAt,
        referenceTime,
        evidenceCount,
        attestationCount,
        fingerprint,
      );
}
