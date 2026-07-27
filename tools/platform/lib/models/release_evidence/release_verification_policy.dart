import 'release_evidence_enums.dart';

/// Policy lifecycle metadata for verification policies.
class ReleaseVerificationPolicyMetadata {
  const ReleaseVerificationPolicyMetadata({
    required this.policyId,
    required this.policyVersion,
    required this.displayName,
    required this.description,
    required this.owner,
    required this.status,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.changelog,
    required this.rationale,
    this.updatedAt,
    this.tags = const [],
    this.fingerprint,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String policyId;
  final int policyVersion;
  final String displayName;
  final String description;
  final String owner;
  final ReleaseEvidencePolicyStatus status;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String? updatedAt;
  final List<ReleaseVerificationPolicyChangelogEntry> changelog;
  final String rationale;
  final List<String> tags;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'displayName': displayName,
        'description': description,
        'owner': owner,
        'status': status.wireName,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        'changelog': changelog.map((e) => e.toJson()).toList(),
        'rationale': rationale,
        if (tags.isNotEmpty) 'tags': tags,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory ReleaseVerificationPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseVerificationPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      description: json['description'] as String,
      owner: json['owner'] as String,
      status: ReleaseEvidencePolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String?,
      changelog: List.unmodifiable(
        (json['changelog'] as List<dynamic>)
            .map(
              (e) => ReleaseVerificationPolicyChangelogEntry.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      rationale: json['rationale'] as String,
      tags: List.unmodifiable(
        (json['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
    );
  }
}

class ReleaseVerificationPolicyChangelogEntry {
  const ReleaseVerificationPolicyChangelogEntry({
    required this.version,
    required this.summary,
    required this.author,
    required this.createdAt,
  });

  final int version;
  final String summary;
  final String author;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'summary': summary,
        'author': author,
        'createdAt': createdAt,
      };

  factory ReleaseVerificationPolicyChangelogEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseVerificationPolicyChangelogEntry(
      version: json['version'] as int,
      summary: json['summary'] as String,
      author: json['author'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Reference to a verification policy.
class ReleaseVerificationPolicyReference {
  const ReleaseVerificationPolicyReference({
    required this.policyId,
    required this.policyVersion,
    required this.policyFingerprint,
  });

  final String policyId;
  final int policyVersion;
  final String policyFingerprint;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyFingerprint': policyFingerprint,
      };

  factory ReleaseVerificationPolicyReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseVerificationPolicyReference(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyFingerprint: json['policyFingerprint'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseVerificationPolicyReference &&
          runtimeType == other.runtimeType &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyFingerprint == other.policyFingerprint;

  @override
  int get hashCode => Object.hash(policyId, policyVersion, policyFingerprint);
}

/// Declarative verification policy for release evidence artifacts.
class ReleaseVerificationPolicy {
  const ReleaseVerificationPolicy({
    required this.metadata,
    this.requireFingerprint = true,
    this.requireArtifactIdentity = true,
    this.requireSubjectConsistency = true,
    this.requireProjectConsistency = true,
    this.requireCommitConsistency = true,
    this.requirePolicyConsistency = true,
    this.requireSchemaCompatibility = true,
    this.requireCanonicalizationCompatibility = true,
    this.requireIssuerValidity = true,
    this.requireAuthorityValidity = true,
    this.requireEvidenceCompleteness = true,
    this.requireProvenance = false,
    this.requireSignature = false,
    this.allowUnverifiedSignature = true,
    this.allowUnverifiedIssuer = false,
    this.allowPartialVerification = false,
    this.minimumEvidenceCoverage = 100,
    this.minimumAttestationCoverage = 100,
    this.supportedSchemas = const [1],
    this.supportedCanonicalizationVersions = const [1],
    this.limitations = const [],
    this.extensions = const {},
  });

  final ReleaseVerificationPolicyMetadata metadata;
  final bool requireFingerprint;
  final bool requireArtifactIdentity;
  final bool requireSubjectConsistency;
  final bool requireProjectConsistency;
  final bool requireCommitConsistency;
  final bool requirePolicyConsistency;
  final bool requireSchemaCompatibility;
  final bool requireCanonicalizationCompatibility;
  final bool requireIssuerValidity;
  final bool requireAuthorityValidity;
  final bool requireEvidenceCompleteness;
  final bool requireProvenance;
  final bool requireSignature;
  final bool allowUnverifiedSignature;
  final bool allowUnverifiedIssuer;
  final bool allowPartialVerification;
  final double minimumEvidenceCoverage;
  final double minimumAttestationCoverage;
  final List<int> supportedSchemas;
  final List<int> supportedCanonicalizationVersions;
  final List<String> limitations;
  final Map<String, String> extensions;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'requireFingerprint': requireFingerprint,
        'requireArtifactIdentity': requireArtifactIdentity,
        'requireSubjectConsistency': requireSubjectConsistency,
        'requireProjectConsistency': requireProjectConsistency,
        'requireCommitConsistency': requireCommitConsistency,
        'requirePolicyConsistency': requirePolicyConsistency,
        'requireSchemaCompatibility': requireSchemaCompatibility,
        'requireCanonicalizationCompatibility':
            requireCanonicalizationCompatibility,
        'requireIssuerValidity': requireIssuerValidity,
        'requireAuthorityValidity': requireAuthorityValidity,
        'requireEvidenceCompleteness': requireEvidenceCompleteness,
        'requireProvenance': requireProvenance,
        'requireSignature': requireSignature,
        'allowUnverifiedSignature': allowUnverifiedSignature,
        'allowUnverifiedIssuer': allowUnverifiedIssuer,
        'allowPartialVerification': allowPartialVerification,
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
        'minimumAttestationCoverage': minimumAttestationCoverage,
        'supportedSchemas': supportedSchemas,
        'supportedCanonicalizationVersions': supportedCanonicalizationVersions,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  factory ReleaseVerificationPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseVerificationPolicy(
      metadata: ReleaseVerificationPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      requireFingerprint: json['requireFingerprint'] as bool? ?? true,
      requireArtifactIdentity: json['requireArtifactIdentity'] as bool? ?? true,
      requireSubjectConsistency:
          json['requireSubjectConsistency'] as bool? ?? true,
      requireProjectConsistency:
          json['requireProjectConsistency'] as bool? ?? true,
      requireCommitConsistency:
          json['requireCommitConsistency'] as bool? ?? true,
      requirePolicyConsistency:
          json['requirePolicyConsistency'] as bool? ?? true,
      requireSchemaCompatibility:
          json['requireSchemaCompatibility'] as bool? ?? true,
      requireCanonicalizationCompatibility:
          json['requireCanonicalizationCompatibility'] as bool? ?? true,
      requireIssuerValidity: json['requireIssuerValidity'] as bool? ?? true,
      requireAuthorityValidity:
          json['requireAuthorityValidity'] as bool? ?? true,
      requireEvidenceCompleteness:
          json['requireEvidenceCompleteness'] as bool? ?? true,
      requireProvenance: json['requireProvenance'] as bool? ?? false,
      requireSignature: json['requireSignature'] as bool? ?? false,
      allowUnverifiedSignature:
          json['allowUnverifiedSignature'] as bool? ?? true,
      allowUnverifiedIssuer: json['allowUnverifiedIssuer'] as bool? ?? false,
      allowPartialVerification:
          json['allowPartialVerification'] as bool? ?? false,
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 100,
      minimumAttestationCoverage:
          (json['minimumAttestationCoverage'] as num?)?.toDouble() ?? 100,
      supportedSchemas: List.unmodifiable(
        (json['supportedSchemas'] as List<dynamic>? ?? [1]).cast<int>(),
      ),
      supportedCanonicalizationVersions: List.unmodifiable(
        (json['supportedCanonicalizationVersions'] as List<dynamic>? ?? [1])
            .cast<int>(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      extensions: Map.unmodifiable(
        (json['extensions'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
