import '../cryptographic_trust_enums.dart';
import '../cryptographic_trust_policy.dart';
import '../cryptographic_trust_requirement.dart';
import 'default_trust_anchor_v1.dart';

/// Candidate artifact signature trust policy v1.
class ArtifactSignatureTrustPolicyV1 {
  const ArtifactSignatureTrustPolicyV1._();

  static const policyId = 'artifact-signature-trust-v1';

  static CryptographicTrustPolicy create() {
    return CryptographicTrustPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Artifact Signature Trust Policy',
      description:
          'Structural trust policy for artifact signature verification descriptors.',
      status: CryptographicPolicyStatus.candidate,
      requirements: const [
        CryptographicTrustRequirement(
          requirementId: 'require-artifact-signature',
          requirementType: CryptographicRequirementType.signature,
          required: true,
          minimumTrustLevel: CryptographicTrustLevel.moderate,
          allowedAlgorithms: [
            CryptographicSignatureAlgorithm.rsaPss,
            CryptographicSignatureAlgorithm.ecdsa,
            CryptographicSignatureAlgorithm.ed25519,
          ],
          allowedKeyTypes: [
            CryptographicKeyType.rsa,
            CryptographicKeyType.ec,
            CryptographicKeyType.ed25519,
          ],
          requiredKeyUsage: [
            CryptographicKeyUsage.sign,
            CryptographicKeyUsage.verify,
          ],
          requiredSignatureCount: 1,
          requireTrustAnchor: true,
          requireNonRevokedKey: true,
        ),
        CryptographicTrustRequirement(
          requirementId: 'require-artifact-digest',
          requirementType: CryptographicRequirementType.digest,
          required: true,
        ),
      ],
      trustAnchors: const [defaultTrustAnchorV1],
      scope: {
        'domain': 'cryptographic-trust',
        'subjectType': 'artifact',
      },
      createdAt: '2026-01-01T00:00:00.000Z',
      metadata: {
        'limitations':
            'no-real-signature-verification,structural-descriptor-only',
      },
    );
  }
}
