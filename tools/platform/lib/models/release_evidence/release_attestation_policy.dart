import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';

import 'release_evidence_enums.dart';

/// Policy lifecycle metadata for attestation policies.
class ReleaseAttestationPolicyMetadata {
  const ReleaseAttestationPolicyMetadata({
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
  final List<ReleaseAttestationPolicyChangelogEntry> changelog;
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

  factory ReleaseAttestationPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationPolicyMetadata(
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
              (e) => ReleaseAttestationPolicyChangelogEntry.fromJson(
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

class ReleaseAttestationPolicyChangelogEntry {
  const ReleaseAttestationPolicyChangelogEntry({
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

  factory ReleaseAttestationPolicyChangelogEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationPolicyChangelogEntry(
      version: json['version'] as int,
      summary: json['summary'] as String,
      author: json['author'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Issuer requirements for attestation policies.
class ReleaseAttestationIssuerRequirement {
  const ReleaseAttestationIssuerRequirement({
    required this.allowedIssuerTypes,
    this.allowedIssuerIds = const [],
    this.requireActiveIssuer = true,
    this.allowUnverifiedIssuer = false,
    this.requireEvidenceReferences = false,
  });

  final List<ReleaseAttestationIssuerType> allowedIssuerTypes;
  final List<String> allowedIssuerIds;
  final bool requireActiveIssuer;
  final bool allowUnverifiedIssuer;
  final bool requireEvidenceReferences;

  Map<String, dynamic> toJson() => {
        'allowedIssuerTypes':
            allowedIssuerTypes.map((e) => e.wireName).toList(),
        if (allowedIssuerIds.isNotEmpty) 'allowedIssuerIds': allowedIssuerIds,
        'requireActiveIssuer': requireActiveIssuer,
        'allowUnverifiedIssuer': allowUnverifiedIssuer,
        'requireEvidenceReferences': requireEvidenceReferences,
      };

  factory ReleaseAttestationIssuerRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationIssuerRequirement(
      allowedIssuerTypes: List.unmodifiable(
        (json['allowedIssuerTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseAttestationIssuerTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      allowedIssuerIds: List.unmodifiable(
        (json['allowedIssuerIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      requireActiveIssuer: json['requireActiveIssuer'] as bool? ?? true,
      allowUnverifiedIssuer: json['allowUnverifiedIssuer'] as bool? ?? false,
      requireEvidenceReferences:
          json['requireEvidenceReferences'] as bool? ?? false,
    );
  }
}

/// Authority requirements for attestation policies.
class ReleaseAttestationAuthorityRequirement {
  const ReleaseAttestationAuthorityRequirement({
    required this.allowedAuthorityIds,
    this.requireActiveAuthority = true,
    this.requireEvidenceReferences = false,
    this.allowedEnvironments = const [],
    this.allowedReleaseTypes = const [],
  });

  final List<String> allowedAuthorityIds;
  final bool requireActiveAuthority;
  final bool requireEvidenceReferences;
  final List<ReleaseEnvironment> allowedEnvironments;
  final List<ReleaseType> allowedReleaseTypes;

  Map<String, dynamic> toJson() => {
        'allowedAuthorityIds': allowedAuthorityIds,
        'requireActiveAuthority': requireActiveAuthority,
        'requireEvidenceReferences': requireEvidenceReferences,
        if (allowedEnvironments.isNotEmpty)
          'allowedEnvironments':
              allowedEnvironments.map((e) => e.wireName).toList(),
        if (allowedReleaseTypes.isNotEmpty)
          'allowedReleaseTypes':
              allowedReleaseTypes.map((e) => e.wireName).toList(),
      };

  factory ReleaseAttestationAuthorityRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationAuthorityRequirement(
      allowedAuthorityIds: List.unmodifiable(
        (json['allowedAuthorityIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      requireActiveAuthority: json['requireActiveAuthority'] as bool? ?? true,
      requireEvidenceReferences:
          json['requireEvidenceReferences'] as bool? ?? false,
      allowedEnvironments: List.unmodifiable(
        (json['allowedEnvironments'] as List<dynamic>? ?? [])
            .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
            .toList(),
      ),
      allowedReleaseTypes: List.unmodifiable(
        (json['allowedReleaseTypes'] as List<dynamic>? ?? [])
            .map((e) => ReleaseTypeX.fromWireName(e as String))
            .toList(),
      ),
    );
  }
}

/// Evidence requirements for attestation policies.
class ReleaseAttestationEvidenceRequirement {
  const ReleaseAttestationEvidenceRequirement({
    required this.minimumEvidenceCount,
    this.requiredEvidenceTypes = const [],
    this.requireFingerprints = true,
    this.requireSourceReferences = true,
  });

  final int minimumEvidenceCount;
  final List<ReleaseEvidenceType> requiredEvidenceTypes;
  final bool requireFingerprints;
  final bool requireSourceReferences;

  Map<String, dynamic> toJson() => {
        'minimumEvidenceCount': minimumEvidenceCount,
        if (requiredEvidenceTypes.isNotEmpty)
          'requiredEvidenceTypes':
              requiredEvidenceTypes.map((e) => e.wireName).toList(),
        'requireFingerprints': requireFingerprints,
        'requireSourceReferences': requireSourceReferences,
      };

  factory ReleaseAttestationEvidenceRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationEvidenceRequirement(
      minimumEvidenceCount: json['minimumEvidenceCount'] as int,
      requiredEvidenceTypes: List.unmodifiable(
        (json['requiredEvidenceTypes'] as List<dynamic>? ?? [])
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      requireFingerprints: json['requireFingerprints'] as bool? ?? true,
      requireSourceReferences: json['requireSourceReferences'] as bool? ?? true,
    );
  }
}

/// Subject requirements for attestation policies.
class ReleaseAttestationSubjectRequirement {
  const ReleaseAttestationSubjectRequirement({
    required this.allowedSubjectTypes,
    this.requireProjectId = true,
    this.requireReleaseId = false,
    this.requireCommitId = false,
    this.minimumSubjectCount = 1,
  });

  final List<ReleaseEvidenceSubjectType> allowedSubjectTypes;
  final bool requireProjectId;
  final bool requireReleaseId;
  final bool requireCommitId;
  final int minimumSubjectCount;

  Map<String, dynamic> toJson() => {
        'allowedSubjectTypes':
            allowedSubjectTypes.map((e) => e.wireName).toList(),
        'requireProjectId': requireProjectId,
        'requireReleaseId': requireReleaseId,
        'requireCommitId': requireCommitId,
        'minimumSubjectCount': minimumSubjectCount,
      };

  factory ReleaseAttestationSubjectRequirement.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationSubjectRequirement(
      allowedSubjectTypes: List.unmodifiable(
        (json['allowedSubjectTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceSubjectTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      requireProjectId: json['requireProjectId'] as bool? ?? true,
      requireReleaseId: json['requireReleaseId'] as bool? ?? false,
      requireCommitId: json['requireCommitId'] as bool? ?? false,
      minimumSubjectCount: json['minimumSubjectCount'] as int? ?? 1,
    );
  }
}

/// Expiration policy for attestations.
class ReleaseAttestationExpirationPolicy {
  const ReleaseAttestationExpirationPolicy({
    this.requireExpiration = false,
    this.defaultExpirationDuration,
    this.allowExpiredForHistorical = false,
    this.warnBeforeExpirationDuration,
  });

  final bool requireExpiration;
  final String? defaultExpirationDuration;
  final bool allowExpiredForHistorical;
  final String? warnBeforeExpirationDuration;

  Map<String, dynamic> toJson() => {
        'requireExpiration': requireExpiration,
        if (defaultExpirationDuration != null)
          'defaultExpirationDuration': defaultExpirationDuration,
        'allowExpiredForHistorical': allowExpiredForHistorical,
        if (warnBeforeExpirationDuration != null)
          'warnBeforeExpirationDuration': warnBeforeExpirationDuration,
      };

  factory ReleaseAttestationExpirationPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationExpirationPolicy(
      requireExpiration: json['requireExpiration'] as bool? ?? false,
      defaultExpirationDuration: json['defaultExpirationDuration'] as String?,
      allowExpiredForHistorical:
          json['allowExpiredForHistorical'] as bool? ?? false,
      warnBeforeExpirationDuration:
          json['warnBeforeExpirationDuration'] as String?,
    );
  }
}

/// Signature policy for attestations.
class ReleaseAttestationSignaturePolicy {
  const ReleaseAttestationSignaturePolicy({
    this.signatureRequired = false,
    this.allowUnverifiedSignature = true,
    this.allowAbsentSignature = true,
    this.unsupportedSignatureProducesLimitation = true,
    this.futureCapabilityOnly = false,
  });

  final bool signatureRequired;
  final bool allowUnverifiedSignature;
  final bool allowAbsentSignature;
  final bool unsupportedSignatureProducesLimitation;
  final bool futureCapabilityOnly;

  Map<String, dynamic> toJson() => {
        'signatureRequired': signatureRequired,
        'allowUnverifiedSignature': allowUnverifiedSignature,
        'allowAbsentSignature': allowAbsentSignature,
        'unsupportedSignatureProducesLimitation':
            unsupportedSignatureProducesLimitation,
        'futureCapabilityOnly': futureCapabilityOnly,
      };

  factory ReleaseAttestationSignaturePolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationSignaturePolicy(
      signatureRequired: json['signatureRequired'] as bool? ?? false,
      allowUnverifiedSignature:
          json['allowUnverifiedSignature'] as bool? ?? true,
      allowAbsentSignature: json['allowAbsentSignature'] as bool? ?? true,
      unsupportedSignatureProducesLimitation:
          json['unsupportedSignatureProducesLimitation'] as bool? ?? true,
      futureCapabilityOnly: json['futureCapabilityOnly'] as bool? ?? false,
    );
  }
}

/// Compatibility policy for attestation policies.
class ReleaseAttestationCompatibilityPolicy {
  const ReleaseAttestationCompatibilityPolicy({
    required this.supportedSchemas,
    this.allowedEvidencePolicyIds = const [],
    this.allowedVerificationPolicyIds = const [],
  });

  final List<int> supportedSchemas;
  final List<String> allowedEvidencePolicyIds;
  final List<String> allowedVerificationPolicyIds;

  Map<String, dynamic> toJson() => {
        'supportedSchemas': supportedSchemas,
        if (allowedEvidencePolicyIds.isNotEmpty)
          'allowedEvidencePolicyIds': allowedEvidencePolicyIds,
        if (allowedVerificationPolicyIds.isNotEmpty)
          'allowedVerificationPolicyIds': allowedVerificationPolicyIds,
      };

  factory ReleaseAttestationCompatibilityPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationCompatibilityPolicy(
      supportedSchemas: List.unmodifiable(
        (json['supportedSchemas'] as List<dynamic>).cast<int>(),
      ),
      allowedEvidencePolicyIds: List.unmodifiable(
        (json['allowedEvidencePolicyIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      allowedVerificationPolicyIds: List.unmodifiable(
        (json['allowedVerificationPolicyIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}

/// Reference to verification policy within attestation policy.
class ReleaseAttestationVerificationPolicyRef {
  const ReleaseAttestationVerificationPolicyRef({
    required this.policyId,
    required this.policyVersion,
    this.required = false,
  });

  final String policyId;
  final int policyVersion;
  final bool required;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'required': required,
      };

  factory ReleaseAttestationVerificationPolicyRef.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseAttestationVerificationPolicyRef(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      required: json['required'] as bool? ?? false,
    );
  }
}

/// Required attestation declaration within an attestation policy.
class ReleaseAttestationRequirement {
  const ReleaseAttestationRequirement({
    required this.requirementId,
    required this.attestationType,
    required this.predicateType,
    required this.minimumCount,
    required this.distinctIssuersRequired,
    required this.subjectTypes,
    required this.environments,
    required this.releaseTypes,
    required this.evidenceRequired,
    required this.signatureRequired,
    required this.externalVerificationRequired,
    required this.required,
    required this.order,
    this.allowedIssuerIds = const [],
    this.allowedAuthorityIds = const [],
    this.expiresAfter,
    this.enabled = true,
  });

  final String requirementId;
  final ReleaseAttestationType attestationType;
  final ReleaseAttestationPredicateType predicateType;
  final int minimumCount;
  final int distinctIssuersRequired;
  final List<String> allowedIssuerIds;
  final List<String> allowedAuthorityIds;
  final List<ReleaseEvidenceSubjectType> subjectTypes;
  final List<ReleaseEnvironment> environments;
  final List<ReleaseType> releaseTypes;
  final bool evidenceRequired;
  final bool signatureRequired;
  final bool externalVerificationRequired;
  final String? expiresAfter;
  final bool required;
  final int order;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'attestationType': attestationType.wireName,
        'predicateType': predicateType.wireName,
        'minimumCount': minimumCount,
        'distinctIssuersRequired': distinctIssuersRequired,
        if (allowedIssuerIds.isNotEmpty) 'allowedIssuerIds': allowedIssuerIds,
        if (allowedAuthorityIds.isNotEmpty)
          'allowedAuthorityIds': allowedAuthorityIds,
        'subjectTypes': subjectTypes.map((e) => e.wireName).toList(),
        'environments': environments.map((e) => e.wireName).toList(),
        'releaseTypes': releaseTypes.map((e) => e.wireName).toList(),
        'evidenceRequired': evidenceRequired,
        'signatureRequired': signatureRequired,
        'externalVerificationRequired': externalVerificationRequired,
        if (expiresAfter != null) 'expiresAfter': expiresAfter,
        'required': required,
        'order': order,
        'enabled': enabled,
      };

  factory ReleaseAttestationRequirement.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationRequirement(
      requirementId: json['requirementId'] as String,
      attestationType: ReleaseAttestationTypeX.fromWireName(
        json['attestationType'] as String,
      ),
      predicateType: ReleaseAttestationPredicateTypeX.fromWireName(
        json['predicateType'] as String,
      ),
      minimumCount: json['minimumCount'] as int,
      distinctIssuersRequired: json['distinctIssuersRequired'] as int,
      allowedIssuerIds: List.unmodifiable(
        (json['allowedIssuerIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      allowedAuthorityIds: List.unmodifiable(
        (json['allowedAuthorityIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      subjectTypes: List.unmodifiable(
        (json['subjectTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceSubjectTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      environments: List.unmodifiable(
        (json['environments'] as List<dynamic>)
            .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
            .toList(),
      ),
      releaseTypes: List.unmodifiable(
        (json['releaseTypes'] as List<dynamic>)
            .map((e) => ReleaseTypeX.fromWireName(e as String))
            .toList(),
      ),
      evidenceRequired: json['evidenceRequired'] as bool,
      signatureRequired: json['signatureRequired'] as bool,
      externalVerificationRequired:
          json['externalVerificationRequired'] as bool,
      expiresAfter: json['expiresAfter'] as String?,
      required: json['required'] as bool,
      order: json['order'] as int,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Declarative attestation policy.
class ReleaseAttestationPolicy {
  const ReleaseAttestationPolicy({
    required this.metadata,
    required this.supportedAttestationTypes,
    required this.supportedPredicateTypes,
    required this.issuerRequirements,
    required this.authorityRequirements,
    required this.evidenceRequirements,
    required this.subjectRequirements,
    required this.expirationPolicy,
    required this.signaturePolicy,
    required this.compatibilityPolicy,
    this.verificationPolicy,
    this.requiredAttestations = const [],
    this.limitations = const [],
    this.extensions = const {},
  });

  final ReleaseAttestationPolicyMetadata metadata;
  final List<ReleaseAttestationType> supportedAttestationTypes;
  final List<ReleaseAttestationPredicateType> supportedPredicateTypes;
  final ReleaseAttestationIssuerRequirement issuerRequirements;
  final ReleaseAttestationAuthorityRequirement authorityRequirements;
  final ReleaseAttestationEvidenceRequirement evidenceRequirements;
  final ReleaseAttestationSubjectRequirement subjectRequirements;
  final ReleaseAttestationExpirationPolicy expirationPolicy;
  final ReleaseAttestationSignaturePolicy signaturePolicy;
  final ReleaseAttestationCompatibilityPolicy compatibilityPolicy;
  final ReleaseAttestationVerificationPolicyRef? verificationPolicy;
  final List<ReleaseAttestationRequirement> requiredAttestations;
  final List<String> limitations;
  final Map<String, String> extensions;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'supportedAttestationTypes':
            supportedAttestationTypes.map((e) => e.wireName).toList(),
        'supportedPredicateTypes':
            supportedPredicateTypes.map((e) => e.wireName).toList(),
        'issuerRequirements': issuerRequirements.toJson(),
        'authorityRequirements': authorityRequirements.toJson(),
        'evidenceRequirements': evidenceRequirements.toJson(),
        'subjectRequirements': subjectRequirements.toJson(),
        'expirationPolicy': expirationPolicy.toJson(),
        'signaturePolicy': signaturePolicy.toJson(),
        'compatibilityPolicy': compatibilityPolicy.toJson(),
        if (verificationPolicy != null)
          'verificationPolicy': verificationPolicy!.toJson(),
        if (requiredAttestations.isNotEmpty)
          'requiredAttestations':
              requiredAttestations.map((r) => r.toJson()).toList(),
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  factory ReleaseAttestationPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationPolicy(
      metadata: ReleaseAttestationPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      supportedAttestationTypes: List.unmodifiable(
        (json['supportedAttestationTypes'] as List<dynamic>)
            .map((e) => ReleaseAttestationTypeX.fromWireName(e as String))
            .toList(),
      ),
      supportedPredicateTypes: List.unmodifiable(
        (json['supportedPredicateTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseAttestationPredicateTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      issuerRequirements: ReleaseAttestationIssuerRequirement.fromJson(
        json['issuerRequirements'] as Map<String, dynamic>,
      ),
      authorityRequirements: ReleaseAttestationAuthorityRequirement.fromJson(
        json['authorityRequirements'] as Map<String, dynamic>,
      ),
      evidenceRequirements: ReleaseAttestationEvidenceRequirement.fromJson(
        json['evidenceRequirements'] as Map<String, dynamic>,
      ),
      subjectRequirements: ReleaseAttestationSubjectRequirement.fromJson(
        json['subjectRequirements'] as Map<String, dynamic>,
      ),
      expirationPolicy: ReleaseAttestationExpirationPolicy.fromJson(
        json['expirationPolicy'] as Map<String, dynamic>,
      ),
      signaturePolicy: ReleaseAttestationSignaturePolicy.fromJson(
        json['signaturePolicy'] as Map<String, dynamic>,
      ),
      compatibilityPolicy: ReleaseAttestationCompatibilityPolicy.fromJson(
        json['compatibilityPolicy'] as Map<String, dynamic>,
      ),
      verificationPolicy: json['verificationPolicy'] == null
          ? null
          : ReleaseAttestationVerificationPolicyRef.fromJson(
              json['verificationPolicy'] as Map<String, dynamic>,
            ),
      requiredAttestations: List.unmodifiable(
        (json['requiredAttestations'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseAttestationRequirement.fromJson(
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
}
