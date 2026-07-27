import '../persistent_artifact_enums.dart';
import '../persistent_artifact_policy_models.dart';

const _policyFingerprintPlaceholder =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Candidate artifact retention policy v1.
class ArtifactRetentionPolicyV1 {
  const ArtifactRetentionPolicyV1._();

  static const policyId = 'artifact-retention-policy-v1';

  static PersistentArtifactRetentionPolicy create() {
    return PersistentArtifactRetentionPolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Artifact Retention Policy',
      description:
          'Structural retention policy for persistent artifact lifecycle and legal hold requirements.',
      status: PersistentArtifactPolicyStatus.candidate,
      artifactTypes: const [
        PersistentArtifactType.releaseEvidence,
        PersistentArtifactType.releaseSupplyChain,
        PersistentArtifactType.cryptographicTrustSnapshot,
        PersistentArtifactType.report,
        PersistentArtifactType.manifest,
      ],
      minimumRetention: 'P365D',
      maximumRetention: 'P2555D',
      retentionAction: PersistentArtifactRetentionAction.retain,
      legalHoldRequired: false,
      immutableUntilExpiration: false,
      scope: const {
        'domain': 'persistent-artifact',
        'policyFingerprint': _policyFingerprintPlaceholder,
      },
      metadata: const {
        'limitations':
            'no-real-deletion,no-real-archive,structural-descriptor-only',
      },
    );
  }
}
