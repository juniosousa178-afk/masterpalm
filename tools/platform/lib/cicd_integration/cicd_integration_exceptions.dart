/// Base exception for CI/CD integration domain.
class CicdIntegrationException implements Exception {
  const CicdIntegrationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'CicdIntegrationException: $message';
}

class CicdIntegrationPolicyNotFoundException extends CicdIntegrationException {
  CicdIntegrationPolicyNotFoundException(
    this.policyId, {
    this.policyVersion,
  }) : super(
          'Policy not found: $policyId${policyVersion != null ? '@$policyVersion' : ''}',
          code: 'CICD_POLICY_NOT_FOUND',
        );

  final String policyId;
  final int? policyVersion;
}

class CicdIntegrationRegistryFrozenException extends CicdIntegrationException {
  CicdIntegrationRegistryFrozenException(String registry)
      : super('Registry frozen: $registry', code: 'CICD_REGISTRY_FROZEN');
}

class CicdIntegrationPolicyInvalidException extends CicdIntegrationException {
  CicdIntegrationPolicyInvalidException(
    String message, {
    required this.policyId,
  }) : super(message, code: 'CICD_POLICY_INVALID');

  final String policyId;
}

class CicdIntegrationSnapshotConflictException
    extends CicdIntegrationException {
  CicdIntegrationSnapshotConflictException(this.snapshotId)
      : super(
          'Snapshot conflict for id: $snapshotId',
          code: 'CICD_SNAPSHOT_CONFLICT',
        );

  final String snapshotId;
}

class CicdIntegrationNotFoundException extends CicdIntegrationException {
  CicdIntegrationNotFoundException(this.snapshotId)
      : super('Snapshot not found: $snapshotId', code: 'CICD_NOT_FOUND');

  final String snapshotId;
}
