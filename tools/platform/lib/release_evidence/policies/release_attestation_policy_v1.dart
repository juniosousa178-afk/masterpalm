import '../../models/release_evidence/release_attestation_policy.dart';
import '../../models/release_evidence/release_evidence_enums.dart';
import '../../models/release_governance/release_governance_enums.dart';

/// Candidate attestation policy v1.
class ReleaseAttestationPolicyV1 {
  const ReleaseAttestationPolicyV1._();

  static const policyId = 'release-attestation-v1';

  static ReleaseAttestationPolicy create() {
    return ReleaseAttestationPolicy(
      metadata: const ReleaseAttestationPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'MasterPalm Release Attestation',
        description:
            'Candidate attestation policy governing verifiable statements about release evidence bundles.',
        owner: 'MasterPalm Engineering Governance',
        status: ReleaseEvidencePolicyStatus.candidate,
        schemaVersion: ReleaseAttestationPolicyMetadata.currentSchemaVersion,
        calculationVersion:
            ReleaseAttestationPolicyMetadata.currentCalculationVersion,
        canonicalizationVersion:
            ReleaseAttestationPolicyMetadata.currentCanonicalizationVersion,
        createdAt: '2026-01-01T00:00:00.000Z',
        rationale:
            'Conservative candidate attestation policy with environment-specific requirements.',
        changelog: [
          ReleaseAttestationPolicyChangelogEntry(
            version: 1,
            summary: 'Initial candidate attestation policy',
            author: 'MasterPalm Engineering Governance',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ],
        tags: ['release-attestation', 'candidate'],
      ),
      supportedAttestationTypes: const [
        ReleaseAttestationType.evidenceBundleIntegrity,
        ReleaseAttestationType.qualityGateDecision,
        ReleaseAttestationType.releaseGovernanceDecision,
        ReleaseAttestationType.provenanceCompleteness,
        ReleaseAttestationType.releaseAuthorization,
      ],
      supportedPredicateTypes: const [
        ReleaseAttestationPredicateType.evidenceBundle,
        ReleaseAttestationPredicateType.qualityGate,
        ReleaseAttestationPredicateType.releaseDecision,
        ReleaseAttestationPredicateType.provenance,
        ReleaseAttestationPredicateType.readiness,
      ],
      issuerRequirements: const ReleaseAttestationIssuerRequirement(
        allowedIssuerTypes: [
          ReleaseAttestationIssuerType.platform,
          ReleaseAttestationIssuerType.service,
          ReleaseAttestationIssuerType.automation,
        ],
        allowedIssuerIds: ['masterpalm-platform', 'release-bot'],
        requireActiveIssuer: true,
        allowUnverifiedIssuer: true,
        requireEvidenceReferences: false,
      ),
      authorityRequirements: ReleaseAttestationAuthorityRequirement(
        allowedAuthorityIds: const [
          'masterpalm-attestation-authority',
          'release-governance-authority',
        ],
        requireActiveAuthority: true,
        requireEvidenceReferences: true,
        allowedEnvironments: const [
          ReleaseEnvironment.development,
          ReleaseEnvironment.test,
          ReleaseEnvironment.qa,
          ReleaseEnvironment.staging,
          ReleaseEnvironment.preProduction,
          ReleaseEnvironment.production,
        ],
        allowedReleaseTypes: const [
          ReleaseType.development,
          ReleaseType.internal,
          ReleaseType.beta,
          ReleaseType.releaseCandidate,
          ReleaseType.production,
          ReleaseType.hotfix,
        ],
      ),
      evidenceRequirements: const ReleaseAttestationEvidenceRequirement(
        minimumEvidenceCount: 1,
        requiredEvidenceTypes: [
          ReleaseEvidenceType.qualityGate,
          ReleaseEvidenceType.releaseGovernance,
        ],
        requireFingerprints: true,
        requireSourceReferences: true,
      ),
      subjectRequirements: const ReleaseAttestationSubjectRequirement(
        allowedSubjectTypes: [
          ReleaseEvidenceSubjectType.evidenceBundle,
          ReleaseEvidenceSubjectType.release,
          ReleaseEvidenceSubjectType.qualityGateSnapshot,
          ReleaseEvidenceSubjectType.releaseDecisionSnapshot,
        ],
        requireProjectId: true,
        requireReleaseId: true,
        minimumSubjectCount: 1,
      ),
      expirationPolicy: const ReleaseAttestationExpirationPolicy(
        requireExpiration: false,
        defaultExpirationDuration: 'P30D',
        allowExpiredForHistorical: true,
        warnBeforeExpirationDuration: 'P3D',
      ),
      signaturePolicy: const ReleaseAttestationSignaturePolicy(
        signatureRequired: false,
        allowUnverifiedSignature: true,
        allowAbsentSignature: true,
        unsupportedSignatureProducesLimitation: true,
        futureCapabilityOnly: false,
      ),
      compatibilityPolicy: const ReleaseAttestationCompatibilityPolicy(
        supportedSchemas: [1],
        allowedEvidencePolicyIds: ['release-evidence-v1'],
        allowedVerificationPolicyIds: ['release-verification-v1'],
      ),
      verificationPolicy: const ReleaseAttestationVerificationPolicyRef(
        policyId: 'release-verification-v1',
        policyVersion: 1,
        required: false,
      ),
      requiredAttestations: [
        ..._developmentRequirements(),
        ..._qaRequirements(),
        ..._productionRequirements(),
      ],
      limitations: const [
        'no-cryptographic-verification',
        'no-signature-generation',
        'no-external-identity-verification',
      ],
    );
  }

  static List<ReleaseAttestationRequirement> _developmentRequirements() {
    return const [
      ReleaseAttestationRequirement(
        requirementId: 'dev-bundle-integrity',
        attestationType: ReleaseAttestationType.evidenceBundleIntegrity,
        predicateType: ReleaseAttestationPredicateType.evidenceBundle,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.evidenceBundle],
        environments: [ReleaseEnvironment.development],
        releaseTypes: [ReleaseType.development, ReleaseType.internal],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 1,
      ),
    ];
  }

  static List<ReleaseAttestationRequirement> _qaRequirements() {
    return const [
      ReleaseAttestationRequirement(
        requirementId: 'qa-bundle-integrity',
        attestationType: ReleaseAttestationType.evidenceBundleIntegrity,
        predicateType: ReleaseAttestationPredicateType.evidenceBundle,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.evidenceBundle],
        environments: [ReleaseEnvironment.qa, ReleaseEnvironment.staging],
        releaseTypes: [
          ReleaseType.beta,
          ReleaseType.releaseCandidate,
        ],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 2,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'qa-quality-gate-decision',
        attestationType: ReleaseAttestationType.qualityGateDecision,
        predicateType: ReleaseAttestationPredicateType.qualityGate,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.qualityGateSnapshot],
        environments: [ReleaseEnvironment.qa, ReleaseEnvironment.staging],
        releaseTypes: [
          ReleaseType.beta,
          ReleaseType.releaseCandidate,
        ],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 3,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'qa-governance-decision',
        attestationType: ReleaseAttestationType.releaseGovernanceDecision,
        predicateType: ReleaseAttestationPredicateType.releaseDecision,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['release-governance-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.releaseDecisionSnapshot],
        environments: [ReleaseEnvironment.qa, ReleaseEnvironment.staging],
        releaseTypes: [
          ReleaseType.beta,
          ReleaseType.releaseCandidate,
        ],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 4,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'qa-provenance-completeness',
        attestationType: ReleaseAttestationType.provenanceCompleteness,
        predicateType: ReleaseAttestationPredicateType.provenance,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.evidenceBundle],
        environments: [ReleaseEnvironment.qa, ReleaseEnvironment.staging],
        releaseTypes: [
          ReleaseType.beta,
          ReleaseType.releaseCandidate,
        ],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 5,
      ),
    ];
  }

  static List<ReleaseAttestationRequirement> _productionRequirements() {
    return const [
      ReleaseAttestationRequirement(
        requirementId: 'prod-bundle-integrity',
        attestationType: ReleaseAttestationType.evidenceBundleIntegrity,
        predicateType: ReleaseAttestationPredicateType.evidenceBundle,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.evidenceBundle],
        environments: [
          ReleaseEnvironment.preProduction,
          ReleaseEnvironment.production,
        ],
        releaseTypes: [ReleaseType.production, ReleaseType.hotfix],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 6,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'prod-quality-gate-decision',
        attestationType: ReleaseAttestationType.qualityGateDecision,
        predicateType: ReleaseAttestationPredicateType.qualityGate,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.qualityGateSnapshot],
        environments: [
          ReleaseEnvironment.preProduction,
          ReleaseEnvironment.production,
        ],
        releaseTypes: [ReleaseType.production, ReleaseType.hotfix],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 7,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'prod-governance-decision',
        attestationType: ReleaseAttestationType.releaseGovernanceDecision,
        predicateType: ReleaseAttestationPredicateType.releaseDecision,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['release-governance-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.releaseDecisionSnapshot],
        environments: [
          ReleaseEnvironment.preProduction,
          ReleaseEnvironment.production,
        ],
        releaseTypes: [ReleaseType.production, ReleaseType.hotfix],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 8,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'prod-release-authorization',
        attestationType: ReleaseAttestationType.releaseAuthorization,
        predicateType: ReleaseAttestationPredicateType.readiness,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['release-governance-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.release],
        environments: [ReleaseEnvironment.production],
        releaseTypes: [ReleaseType.production, ReleaseType.hotfix],
        evidenceRequired: true,
        signatureRequired: true,
        externalVerificationRequired: false,
        required: true,
        order: 9,
      ),
      ReleaseAttestationRequirement(
        requirementId: 'prod-provenance-completeness',
        attestationType: ReleaseAttestationType.provenanceCompleteness,
        predicateType: ReleaseAttestationPredicateType.provenance,
        minimumCount: 1,
        distinctIssuersRequired: 1,
        allowedIssuerIds: ['masterpalm-platform'],
        allowedAuthorityIds: ['masterpalm-attestation-authority'],
        subjectTypes: [ReleaseEvidenceSubjectType.evidenceBundle],
        environments: [
          ReleaseEnvironment.preProduction,
          ReleaseEnvironment.production,
        ],
        releaseTypes: [ReleaseType.production, ReleaseType.hotfix],
        evidenceRequired: true,
        signatureRequired: false,
        externalVerificationRequired: false,
        required: true,
        order: 10,
      ),
    ];
  }
}
