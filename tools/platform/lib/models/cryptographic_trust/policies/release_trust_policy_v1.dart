import '../cryptographic_trust_enums.dart';
import '../cryptographic_trust_policy.dart';
import '../cryptographic_trust_requirement.dart';
import 'default_trust_anchor_v1.dart';

/// Candidate release trust policy v1.
class ReleaseTrustPolicyV1 {
  const ReleaseTrustPolicyV1._();

  static const policyId = 'release-trust-v1';

  static CryptographicTrustPolicy create() {
    return CryptographicTrustPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Release Trust Policy',
      description:
          'Structural trust policy combining signature and attestation requirements for release subjects.',
      status: CryptographicPolicyStatus.candidate,
      requirements: const [
        CryptographicTrustRequirement(
          requirementId: 'require-release-signatures',
          requirementType: CryptographicRequirementType.signature,
          required: true,
          minimumTrustLevel: CryptographicTrustLevel.high,
          allowedAlgorithms: [
            CryptographicSignatureAlgorithm.rsaPss,
            CryptographicSignatureAlgorithm.ecdsa,
            CryptographicSignatureAlgorithm.ed25519,
          ],
          requiredSignatureCount: 1,
          requireTrustAnchor: true,
          requireNonRevokedKey: true,
        ),
        CryptographicTrustRequirement(
          requirementId: 'require-release-attestations',
          requirementType: CryptographicRequirementType.attestation,
          required: true,
          requiredAttestationTypes: [
            CryptographicAttestationType.supplyChain,
            CryptographicAttestationType.releaseReadiness,
          ],
        ),
        CryptographicTrustRequirement(
          requirementId: 'require-transparency-log',
          requirementType: CryptographicRequirementType.transparencyLog,
          required: false,
          requireTransparencyLog: true,
        ),
      ],
      trustAnchors: const [defaultTrustAnchorV1],
      scope: {
        'domain': 'cryptographic-trust',
        'subjectType': 'release',
      },
      createdAt: '2026-01-01T00:00:00.000Z',
      metadata: {
        'limitations':
            'no-release-authorization,no-real-verification,structural-descriptor-only',
      },
    );
  }
}
