/// Base exception for release supply chain domain.
class ReleaseSupplyChainException implements Exception {
  const ReleaseSupplyChainException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'ReleaseSupplyChainException: $message';
}

class ReleaseSupplyChainPolicyNotFoundException
    extends ReleaseSupplyChainException {
  ReleaseSupplyChainPolicyNotFoundException(
    this.policyId, {
    this.policyVersion,
  }) : super(
          'Policy not found: $policyId${policyVersion != null ? '@$policyVersion' : ''}',
          code: 'RSC_POLICY_NOT_FOUND',
        );

  final String policyId;
  final int? policyVersion;
}

class ReleaseSupplyChainRegistryFrozenException
    extends ReleaseSupplyChainException {
  ReleaseSupplyChainRegistryFrozenException(String registry)
      : super('Registry frozen: $registry', code: 'RSC_REGISTRY_FROZEN');
}

class ReleaseSupplyChainPolicyInvalidException
    extends ReleaseSupplyChainException {
  ReleaseSupplyChainPolicyInvalidException(
    String message, {
    required this.policyId,
  }) : super(message, code: 'RSC_POLICY_INVALID');

  final String policyId;
}

class ReleaseSupplyChainSnapshotConflictException
    extends ReleaseSupplyChainException {
  ReleaseSupplyChainSnapshotConflictException(this.snapshotId)
      : super(
          'Snapshot conflict for id: $snapshotId',
          code: 'RSC_SNAPSHOT_CONFLICT',
        );

  final String snapshotId;
}

class ReleaseSupplyChainNotFoundException extends ReleaseSupplyChainException {
  ReleaseSupplyChainNotFoundException(this.snapshotId)
      : super('Snapshot not found: $snapshotId', code: 'RSC_NOT_FOUND');

  final String snapshotId;
}
