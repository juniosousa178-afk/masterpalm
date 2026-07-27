import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';

import 'release_evidence_collection_rule.dart';
import 'release_evidence_enums.dart';

/// Policy lifecycle metadata for release evidence collection.
class ReleaseEvidencePolicyMetadata {
  const ReleaseEvidencePolicyMetadata({
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
  final List<ReleaseEvidencePolicyChangelogEntry> changelog;
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

  factory ReleaseEvidencePolicyMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidencePolicyMetadata(
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
              (e) => ReleaseEvidencePolicyChangelogEntry.fromJson(
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

class ReleaseEvidencePolicyChangelogEntry {
  const ReleaseEvidencePolicyChangelogEntry({
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

  factory ReleaseEvidencePolicyChangelogEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidencePolicyChangelogEntry(
      version: json['version'] as int,
      summary: json['summary'] as String,
      author: json['author'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Governance metadata for a release evidence policy.
class ReleaseEvidencePolicyGovernance {
  const ReleaseEvidencePolicyGovernance({
    required this.policyOwner,
    required this.approvalAuthority,
    required this.policyApprovalStatus,
    required this.versioningStrategy,
    required this.rollbackPolicy,
    required this.evidenceRequirements,
    required this.compatibilityRequirements,
    required this.retentionRequirements,
    required this.reviewCadence,
    required this.escalationAuthority,
    this.attestationAuthority,
    this.verificationAuthority,
  });

  final String policyOwner;
  final String approvalAuthority;
  final String policyApprovalStatus;
  final String versioningStrategy;
  final String rollbackPolicy;
  final String evidenceRequirements;
  final String compatibilityRequirements;
  final String retentionRequirements;
  final String reviewCadence;
  final String escalationAuthority;
  final String? attestationAuthority;
  final String? verificationAuthority;

  Map<String, dynamic> toJson() => {
        'policyOwner': policyOwner,
        'approvalAuthority': approvalAuthority,
        'policyApprovalStatus': policyApprovalStatus,
        'versioningStrategy': versioningStrategy,
        'rollbackPolicy': rollbackPolicy,
        'evidenceRequirements': evidenceRequirements,
        'compatibilityRequirements': compatibilityRequirements,
        'retentionRequirements': retentionRequirements,
        'reviewCadence': reviewCadence,
        'escalationAuthority': escalationAuthority,
        if (attestationAuthority != null)
          'attestationAuthority': attestationAuthority,
        if (verificationAuthority != null)
          'verificationAuthority': verificationAuthority,
      };

  factory ReleaseEvidencePolicyGovernance.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidencePolicyGovernance(
      policyOwner: json['policyOwner'] as String,
      approvalAuthority: json['approvalAuthority'] as String,
      policyApprovalStatus: json['policyApprovalStatus'] as String,
      versioningStrategy: json['versioningStrategy'] as String,
      rollbackPolicy: json['rollbackPolicy'] as String,
      evidenceRequirements: json['evidenceRequirements'] as String,
      compatibilityRequirements: json['compatibilityRequirements'] as String,
      retentionRequirements: json['retentionRequirements'] as String,
      reviewCadence: json['reviewCadence'] as String,
      escalationAuthority: json['escalationAuthority'] as String,
      attestationAuthority: json['attestationAuthority'] as String?,
      verificationAuthority: json['verificationAuthority'] as String?,
    );
  }
}

/// Compatibility policy for release evidence collection.
class ReleaseEvidenceCompatibilityPolicy {
  const ReleaseEvidenceCompatibilityPolicy({
    required this.supportedSchemas,
    required this.allowedQualityGatePolicyIds,
    required this.allowedQualityGatePolicyVersions,
    required this.allowedReleaseGovernancePolicyIds,
    required this.allowedReleaseGovernancePolicyVersions,
    required this.allowedAttestationPolicyIds,
    required this.allowedVerificationPolicyIds,
    this.requireProjectConsistency = true,
    this.requireCommitConsistency = true,
    this.requirePolicyConsistency = true,
  });

  final List<int> supportedSchemas;
  final List<String> allowedQualityGatePolicyIds;
  final List<int> allowedQualityGatePolicyVersions;
  final List<String> allowedReleaseGovernancePolicyIds;
  final List<int> allowedReleaseGovernancePolicyVersions;
  final List<String> allowedAttestationPolicyIds;
  final List<String> allowedVerificationPolicyIds;
  final bool requireProjectConsistency;
  final bool requireCommitConsistency;
  final bool requirePolicyConsistency;

  Map<String, dynamic> toJson() => {
        'supportedSchemas': supportedSchemas,
        'allowedQualityGatePolicyIds': allowedQualityGatePolicyIds,
        'allowedQualityGatePolicyVersions': allowedQualityGatePolicyVersions,
        'allowedReleaseGovernancePolicyIds': allowedReleaseGovernancePolicyIds,
        'allowedReleaseGovernancePolicyVersions':
            allowedReleaseGovernancePolicyVersions,
        'allowedAttestationPolicyIds': allowedAttestationPolicyIds,
        'allowedVerificationPolicyIds': allowedVerificationPolicyIds,
        'requireProjectConsistency': requireProjectConsistency,
        'requireCommitConsistency': requireCommitConsistency,
        'requirePolicyConsistency': requirePolicyConsistency,
      };

  factory ReleaseEvidenceCompatibilityPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceCompatibilityPolicy(
      supportedSchemas: List.unmodifiable(
        (json['supportedSchemas'] as List<dynamic>).cast<int>(),
      ),
      allowedQualityGatePolicyIds: List.unmodifiable(
        (json['allowedQualityGatePolicyIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      allowedQualityGatePolicyVersions: List.unmodifiable(
        (json['allowedQualityGatePolicyVersions'] as List<dynamic>).cast<int>(),
      ),
      allowedReleaseGovernancePolicyIds: List.unmodifiable(
        (json['allowedReleaseGovernancePolicyIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      allowedReleaseGovernancePolicyVersions: List.unmodifiable(
        (json['allowedReleaseGovernancePolicyVersions'] as List<dynamic>)
            .cast<int>(),
      ),
      allowedAttestationPolicyIds: List.unmodifiable(
        (json['allowedAttestationPolicyIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      allowedVerificationPolicyIds: List.unmodifiable(
        (json['allowedVerificationPolicyIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      requireProjectConsistency:
          json['requireProjectConsistency'] as bool? ?? true,
      requireCommitConsistency:
          json['requireCommitConsistency'] as bool? ?? true,
      requirePolicyConsistency:
          json['requirePolicyConsistency'] as bool? ?? true,
    );
  }
}

/// Eligibility policy for release evidence collection.
class ReleaseEvidenceEligibilityPolicy {
  const ReleaseEvidenceEligibilityPolicy({
    this.requireReleaseContext = true,
    this.requireQualityGate = true,
    this.requireReleaseDecision = true,
    this.requireNormativeEvidence = true,
    this.allowCandidatePolicy = true,
    this.allowHistoricalEvaluation = false,
    this.minimumNormativeEvidenceCount = 1,
    this.supportedEnvironments = const [],
    this.supportedReleaseTypes = const [],
  });

  final bool requireReleaseContext;
  final bool requireQualityGate;
  final bool requireReleaseDecision;
  final bool requireNormativeEvidence;
  final bool allowCandidatePolicy;
  final bool allowHistoricalEvaluation;
  final int minimumNormativeEvidenceCount;
  final List<ReleaseEnvironment> supportedEnvironments;
  final List<ReleaseType> supportedReleaseTypes;

  Map<String, dynamic> toJson() => {
        'requireReleaseContext': requireReleaseContext,
        'requireQualityGate': requireQualityGate,
        'requireReleaseDecision': requireReleaseDecision,
        'requireNormativeEvidence': requireNormativeEvidence,
        'allowCandidatePolicy': allowCandidatePolicy,
        'allowHistoricalEvaluation': allowHistoricalEvaluation,
        'minimumNormativeEvidenceCount': minimumNormativeEvidenceCount,
        'supportedEnvironments':
            supportedEnvironments.map((e) => e.wireName).toList(),
        'supportedReleaseTypes':
            supportedReleaseTypes.map((e) => e.wireName).toList(),
      };

  factory ReleaseEvidenceEligibilityPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceEligibilityPolicy(
      requireReleaseContext: json['requireReleaseContext'] as bool? ?? true,
      requireQualityGate: json['requireQualityGate'] as bool? ?? true,
      requireReleaseDecision: json['requireReleaseDecision'] as bool? ?? true,
      requireNormativeEvidence:
          json['requireNormativeEvidence'] as bool? ?? true,
      allowCandidatePolicy: json['allowCandidatePolicy'] as bool? ?? true,
      allowHistoricalEvaluation:
          json['allowHistoricalEvaluation'] as bool? ?? false,
      minimumNormativeEvidenceCount:
          json['minimumNormativeEvidenceCount'] as int? ?? 1,
      supportedEnvironments: List.unmodifiable(
        (json['supportedEnvironments'] as List<dynamic>? ?? [])
            .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
            .toList(),
      ),
      supportedReleaseTypes: List.unmodifiable(
        (json['supportedReleaseTypes'] as List<dynamic>? ?? [])
            .map((e) => ReleaseTypeX.fromWireName(e as String))
            .toList(),
      ),
    );
  }
}

/// Coverage policy for release evidence collection.
class ReleaseEvidenceCoveragePolicy {
  const ReleaseEvidenceCoveragePolicy({
    this.minimumEvidenceCoverage = 100,
    this.minimumAttestationCoverage = 100,
    this.minimumProvenanceCoverage = 100,
    this.minimumSourceCoverage = 100,
    this.minimumNormativeEvidenceCount = 1,
    this.minimumValidAttestationCount = 0,
  });

  final double minimumEvidenceCoverage;
  final double minimumAttestationCoverage;
  final double minimumProvenanceCoverage;
  final double minimumSourceCoverage;
  final int minimumNormativeEvidenceCount;
  final int minimumValidAttestationCount;

  Map<String, dynamic> toJson() => {
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
        'minimumAttestationCoverage': minimumAttestationCoverage,
        'minimumProvenanceCoverage': minimumProvenanceCoverage,
        'minimumSourceCoverage': minimumSourceCoverage,
        'minimumNormativeEvidenceCount': minimumNormativeEvidenceCount,
        'minimumValidAttestationCount': minimumValidAttestationCount,
      };

  factory ReleaseEvidenceCoveragePolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceCoveragePolicy(
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 100,
      minimumAttestationCoverage:
          (json['minimumAttestationCoverage'] as num?)?.toDouble() ?? 100,
      minimumProvenanceCoverage:
          (json['minimumProvenanceCoverage'] as num?)?.toDouble() ?? 100,
      minimumSourceCoverage:
          (json['minimumSourceCoverage'] as num?)?.toDouble() ?? 100,
      minimumNormativeEvidenceCount:
          json['minimumNormativeEvidenceCount'] as int? ?? 1,
      minimumValidAttestationCount:
          json['minimumValidAttestationCount'] as int? ?? 0,
    );
  }
}

/// Retention policy for release evidence artifacts.
class ReleaseEvidenceRetentionPolicy {
  const ReleaseEvidenceRetentionPolicy({
    this.retainPolicyId = true,
    this.retainPolicyVersion = true,
    this.retainFingerprints = true,
    this.retainSourceReferences = true,
    this.retainAttestations = true,
    this.retainProvenance = true,
    this.minimumRetentionDuration,
  });

  final bool retainPolicyId;
  final bool retainPolicyVersion;
  final bool retainFingerprints;
  final bool retainSourceReferences;
  final bool retainAttestations;
  final bool retainProvenance;
  final String? minimumRetentionDuration;

  Map<String, dynamic> toJson() => {
        'retainPolicyId': retainPolicyId,
        'retainPolicyVersion': retainPolicyVersion,
        'retainFingerprints': retainFingerprints,
        'retainSourceReferences': retainSourceReferences,
        'retainAttestations': retainAttestations,
        'retainProvenance': retainProvenance,
        if (minimumRetentionDuration != null)
          'minimumRetentionDuration': minimumRetentionDuration,
      };

  factory ReleaseEvidenceRetentionPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceRetentionPolicy(
      retainPolicyId: json['retainPolicyId'] as bool? ?? true,
      retainPolicyVersion: json['retainPolicyVersion'] as bool? ?? true,
      retainFingerprints: json['retainFingerprints'] as bool? ?? true,
      retainSourceReferences: json['retainSourceReferences'] as bool? ?? true,
      retainAttestations: json['retainAttestations'] as bool? ?? true,
      retainProvenance: json['retainProvenance'] as bool? ?? true,
      minimumRetentionDuration: json['minimumRetentionDuration'] as String?,
    );
  }
}

/// Reference to an attestation requirement within an evidence policy.
class ReleaseEvidenceAttestationRequirementRef {
  const ReleaseEvidenceAttestationRequirementRef({
    required this.requirementId,
    required this.attestationType,
    required this.required,
    this.minimumCount = 1,
  });

  final String requirementId;
  final ReleaseAttestationType attestationType;
  final bool required;
  final int minimumCount;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'attestationType': attestationType.wireName,
        'required': required,
        'minimumCount': minimumCount,
      };

  factory ReleaseEvidenceAttestationRequirementRef.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceAttestationRequirementRef(
      requirementId: json['requirementId'] as String,
      attestationType: ReleaseAttestationTypeX.fromWireName(
        json['attestationType'] as String,
      ),
      required: json['required'] as bool,
      minimumCount: json['minimumCount'] as int? ?? 1,
    );
  }
}

/// Declarative release evidence collection policy.
class ReleaseEvidencePolicy {
  const ReleaseEvidencePolicy({
    required this.metadata,
    required this.governance,
    required this.rules,
    required this.ruleSets,
    required this.requiredEvidenceTypes,
    required this.requiredArtifactTypes,
    required this.compatibilityPolicy,
    required this.eligibilityPolicy,
    required this.coveragePolicy,
    required this.retentionPolicy,
    this.attestationRequirements = const [],
    this.limitations = const [],
    this.extensions = const {},
  });

  static const int currentSchemaVersion =
      ReleaseEvidencePolicyMetadata.currentSchemaVersion;
  static const int currentCalculationVersion =
      ReleaseEvidencePolicyMetadata.currentCalculationVersion;
  static const int currentCanonicalizationVersion =
      ReleaseEvidencePolicyMetadata.currentCanonicalizationVersion;

  final ReleaseEvidencePolicyMetadata metadata;
  final ReleaseEvidencePolicyGovernance governance;
  final List<ReleaseEvidenceCollectionRule> rules;
  final List<ReleaseEvidenceCollectionRuleSet> ruleSets;
  final List<ReleaseEvidenceType> requiredEvidenceTypes;
  final List<ReleaseEvidenceArtifactType> requiredArtifactTypes;
  final ReleaseEvidenceCompatibilityPolicy compatibilityPolicy;
  final ReleaseEvidenceEligibilityPolicy eligibilityPolicy;
  final ReleaseEvidenceCoveragePolicy coveragePolicy;
  final ReleaseEvidenceRetentionPolicy retentionPolicy;
  final List<ReleaseEvidenceAttestationRequirementRef> attestationRequirements;
  final List<String> limitations;
  final Map<String, String> extensions;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'governance': governance.toJson(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'ruleSets': ruleSets.map((s) => s.toJson()).toList(),
        'requiredEvidenceTypes':
            requiredEvidenceTypes.map((e) => e.wireName).toList(),
        'requiredArtifactTypes':
            requiredArtifactTypes.map((e) => e.wireName).toList(),
        'compatibilityPolicy': compatibilityPolicy.toJson(),
        'eligibilityPolicy': eligibilityPolicy.toJson(),
        'coveragePolicy': coveragePolicy.toJson(),
        'retentionPolicy': retentionPolicy.toJson(),
        if (attestationRequirements.isNotEmpty)
          'attestationRequirements':
              attestationRequirements.map((r) => r.toJson()).toList(),
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  factory ReleaseEvidencePolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidencePolicy(
      metadata: ReleaseEvidencePolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      governance: ReleaseEvidencePolicyGovernance.fromJson(
        json['governance'] as Map<String, dynamic>,
      ),
      rules: List.unmodifiable(
        (json['rules'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceCollectionRule.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      ruleSets: List.unmodifiable(
        (json['ruleSets'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceCollectionRuleSet.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      requiredEvidenceTypes: List.unmodifiable(
        (json['requiredEvidenceTypes'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      requiredArtifactTypes: List.unmodifiable(
        (json['requiredArtifactTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceArtifactTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      compatibilityPolicy: ReleaseEvidenceCompatibilityPolicy.fromJson(
        json['compatibilityPolicy'] as Map<String, dynamic>,
      ),
      eligibilityPolicy: ReleaseEvidenceEligibilityPolicy.fromJson(
        json['eligibilityPolicy'] as Map<String, dynamic>,
      ),
      coveragePolicy: ReleaseEvidenceCoveragePolicy.fromJson(
        json['coveragePolicy'] as Map<String, dynamic>,
      ),
      retentionPolicy: ReleaseEvidenceRetentionPolicy.fromJson(
        json['retentionPolicy'] as Map<String, dynamic>,
      ),
      attestationRequirements: List.unmodifiable(
        (json['attestationRequirements'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceAttestationRequirementRef.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
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

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    meta.remove('updatedAt');
    meta.remove('fingerprint');
    json['metadata'] = meta;
    final ruleSets = List<Map<String, dynamic>>.from(
      (json['ruleSets'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['ruleSetId'].toString().compareTo(
              b['ruleSetId'].toString(),
            ),
      );
    json['ruleSets'] = ruleSets;
    final rules = List<Map<String, dynamic>>.from(
      (json['rules'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['ruleId'].toString().compareTo(b['ruleId'].toString()),
      );
    json['rules'] = rules;
    return json;
  }
}
