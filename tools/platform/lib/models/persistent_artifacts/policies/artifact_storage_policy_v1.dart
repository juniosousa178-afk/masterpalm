import '../persistent_artifact_enums.dart';
import '../persistent_artifact_policy_models.dart';

const _policyFingerprintPlaceholder =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Candidate artifact storage policy v1.
class ArtifactStoragePolicyV1 {
  const ArtifactStoragePolicyV1._();

  static const policyId = 'artifact-storage-policy-v1';

  static PersistentArtifactStoragePolicy create() {
    return PersistentArtifactStoragePolicy(
      policyId: policyId,
      version: 1,
      name: 'Default Artifact Storage Policy',
      description:
          'Structural storage policy for persistent artifact location, durability, and protection requirements.',
      status: PersistentArtifactPolicyStatus.candidate,
      allowedLocationTypes: const [
        PersistentArtifactLocationType.logicalNamespace,
        PersistentArtifactLocationType.objectStore,
        PersistentArtifactLocationType.archive,
      ],
      allowedStorageClasses: const [
        PersistentArtifactStorageClass.standard,
        PersistentArtifactStorageClass.infrequentAccess,
        PersistentArtifactStorageClass.archive,
      ],
      minimumDurability: PersistentArtifactDurabilityLevel.standard,
      consistencyModel: PersistentArtifactConsistencyModel.readAfterWrite,
      minimumReplicaCount: 1,
      requireEncryption: true,
      requireIntegrityRecord: true,
      requireCryptographicTrust: false,
      constraints: const {
        'policyFingerprint': _policyFingerprintPlaceholder,
      },
      metadata: const {
        'limitations':
            'no-provider-selection,no-real-storage,structural-descriptor-only',
      },
    );
  }
}
