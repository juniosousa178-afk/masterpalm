class PersistentArtifactException implements Exception {
  const PersistentArtifactException(this.message);
  final String message;

  @override
  String toString() => 'PersistentArtifactException: $message';
}

class PersistentArtifactNotFoundException extends PersistentArtifactException {
  const PersistentArtifactNotFoundException(String snapshotId)
      : super('Persistent artifact snapshot not found: $snapshotId');
}

class PersistentArtifactPolicyNotFoundException
    extends PersistentArtifactException {
  const PersistentArtifactPolicyNotFoundException(
    this.policyId, {
    this.policyVersion,
  }) : super(
          policyVersion == null
              ? 'Persistent artifact policy not found: $policyId'
              : 'Persistent artifact policy not found: $policyId v$policyVersion',
        );

  final String policyId;
  final int? policyVersion;
}

class PersistentArtifactRegistryFrozenException
    extends PersistentArtifactException {
  const PersistentArtifactRegistryFrozenException(String registryName)
      : super('$registryName is frozen');
}

class PersistentArtifactSnapshotConflictException
    extends PersistentArtifactException {
  const PersistentArtifactSnapshotConflictException(String snapshotId)
      : super('Snapshot conflict for idempotent snapshot: $snapshotId');
}
