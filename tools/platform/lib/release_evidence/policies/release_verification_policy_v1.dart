import '../../models/release_evidence/release_evidence_enums.dart';
import '../../models/release_evidence/release_verification_policy.dart';

/// Candidate verification policy v1.
class ReleaseVerificationPolicyV1 {
  const ReleaseVerificationPolicyV1._();

  static const policyId = 'release-verification-v1';

  static ReleaseVerificationPolicy create() {
    return ReleaseVerificationPolicy(
      metadata: const ReleaseVerificationPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'MasterPalm Release Verification',
        description:
            'Candidate verification policy for structural and normative release evidence checks.',
        owner: 'MasterPalm Engineering Governance',
        status: ReleaseEvidencePolicyStatus.candidate,
        schemaVersion: ReleaseVerificationPolicyMetadata.currentSchemaVersion,
        calculationVersion:
            ReleaseVerificationPolicyMetadata.currentCalculationVersion,
        canonicalizationVersion:
            ReleaseVerificationPolicyMetadata.currentCanonicalizationVersion,
        createdAt: '2026-01-01T00:00:00.000Z',
        rationale:
            'Conservative candidate verification policy without cryptographic verification.',
        changelog: [
          ReleaseVerificationPolicyChangelogEntry(
            version: 1,
            summary: 'Initial candidate verification policy',
            author: 'MasterPalm Engineering Governance',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ],
        tags: ['release-verification', 'candidate'],
      ),
      requireFingerprint: true,
      requireArtifactIdentity: true,
      requireSubjectConsistency: true,
      requireProjectConsistency: true,
      requireCommitConsistency: true,
      requirePolicyConsistency: true,
      requireSchemaCompatibility: true,
      requireCanonicalizationCompatibility: true,
      requireIssuerValidity: true,
      requireAuthorityValidity: true,
      requireEvidenceCompleteness: true,
      requireProvenance: true,
      requireSignature: false,
      allowUnverifiedSignature: true,
      allowUnverifiedIssuer: true,
      allowPartialVerification: true,
      minimumEvidenceCoverage: 100,
      minimumAttestationCoverage: 100,
      supportedSchemas: const [1],
      supportedCanonicalizationVersions: const [1],
      limitations: const [
        'no-cryptographic-verification',
        'no-signature-generation',
        'no-external-identity-verification',
        'signature-required-for-production-is-future-capability',
      ],
    );
  }

  /// Production-oriented variant with stricter signature expectations.
  static ReleaseVerificationPolicy createProductionStrict() {
    final base = create();
    return ReleaseVerificationPolicy(
      metadata: base.metadata,
      requireFingerprint: base.requireFingerprint,
      requireArtifactIdentity: base.requireArtifactIdentity,
      requireSubjectConsistency: base.requireSubjectConsistency,
      requireProjectConsistency: base.requireProjectConsistency,
      requireCommitConsistency: base.requireCommitConsistency,
      requirePolicyConsistency: base.requirePolicyConsistency,
      requireSchemaCompatibility: base.requireSchemaCompatibility,
      requireCanonicalizationCompatibility:
          base.requireCanonicalizationCompatibility,
      requireIssuerValidity: base.requireIssuerValidity,
      requireAuthorityValidity: base.requireAuthorityValidity,
      requireEvidenceCompleteness: base.requireEvidenceCompleteness,
      requireProvenance: true,
      requireSignature: true,
      allowUnverifiedSignature: true,
      allowUnverifiedIssuer: false,
      allowPartialVerification: false,
      minimumEvidenceCoverage: 100,
      minimumAttestationCoverage: 100,
      supportedSchemas: base.supportedSchemas,
      supportedCanonicalizationVersions: base.supportedCanonicalizationVersions,
      limitations: [
        ...base.limitations,
        'production-signature-required-but-not-cryptographically-verified',
      ],
    );
  }
}
