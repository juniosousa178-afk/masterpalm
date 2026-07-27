import '../cryptographic_trust_enums.dart';
import '../cryptographic_trust_policy.dart';
import '../cryptographic_trust_requirement.dart';
import 'default_trust_anchor_v1.dart';

/// Candidate attestation trust policy v1.
class AttestationTrustPolicyV1 {
  const AttestationTrustPolicyV1._();

  static const policyId = 'attestation-trust-v1';

  static CryptographicTrustPolicy create() {
    return CryptographicTrustPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Attestation Trust Policy',
      description:
          'Structural trust policy for attestation statement descriptors.',
      status: CryptographicPolicyStatus.candidate,
      requirements: const [
        CryptographicTrustRequirement(
          requirementId: 'require-build-provenance-attestation',
          requirementType: CryptographicRequirementType.attestation,
          required: true,
          minimumTrustLevel: CryptographicTrustLevel.moderate,
          requiredAttestationTypes: [
            CryptographicAttestationType.buildProvenance,
            CryptographicAttestationType.artifactIntegrity,
          ],
          requiredSignatureCount: 1,
          requireTrustAnchor: true,
        ),
        CryptographicTrustRequirement(
          requirementId: 'require-attestation-signature',
          requirementType: CryptographicRequirementType.signature,
          required: true,
          allowedAlgorithms: [
            CryptographicSignatureAlgorithm.ecdsa,
            CryptographicSignatureAlgorithm.ed25519,
          ],
          requiredKeyUsage: [CryptographicKeyUsage.sign],
        ),
      ],
      trustAnchors: const [defaultTrustAnchorV1],
      scope: {
        'domain': 'cryptographic-trust',
        'subjectType': 'attestation',
      },
      createdAt: '2026-01-01T00:00:00.000Z',
      metadata: {
        'limitations':
            'no-real-attestation-verification,structural-descriptor-only',
      },
    );
  }
}
