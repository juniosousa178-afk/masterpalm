/// Base exception for Cryptographic Trust domain.
class CryptographicTrustException implements Exception {
  const CryptographicTrustException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'CryptographicTrustException: $message';
}

class CryptographicTrustPolicyNotFoundException
    extends CryptographicTrustException {
  CryptographicTrustPolicyNotFoundException(
    this.policyId, {
    this.policyVersion,
  }) : super(
          'Policy not found: $policyId${policyVersion != null ? '@$policyVersion' : ''}',
          code: 'CT_POLICY_NOT_FOUND',
        );

  final String policyId;
  final int? policyVersion;
}

class CryptographicTrustRegistryFrozenException
    extends CryptographicTrustException {
  CryptographicTrustRegistryFrozenException(String registry)
      : super('Registry frozen: $registry', code: 'CT_REGISTRY_FROZEN');
}

class CryptographicTrustPolicyInvalidException
    extends CryptographicTrustException {
  CryptographicTrustPolicyInvalidException(
    String message, {
    required this.policyId,
  }) : super(message, code: 'CT_POLICY_INVALID');

  final String policyId;
}

class CryptographicTrustAlgorithmNotFoundException
    extends CryptographicTrustException {
  CryptographicTrustAlgorithmNotFoundException(
    this.algorithmId, {
    this.operation,
  }) : super(
          'Algorithm not found: $algorithmId${operation != null ? ' ($operation)' : ''}',
          code: 'CT_ALGORITHM_NOT_FOUND',
        );

  final String algorithmId;
  final String? operation;
}

class CryptographicTrustAlgorithmConflictException
    extends CryptographicTrustException {
  CryptographicTrustAlgorithmConflictException(
    this.algorithmId, {
    this.operation,
  }) : super(
          'Algorithm registration conflict: $algorithmId${operation != null ? ' ($operation)' : ''}',
          code: 'CT_ALGORITHM_CONFLICT',
        );

  final String algorithmId;
  final String? operation;
}

class CryptographicTrustSnapshotConflictException
    extends CryptographicTrustException {
  CryptographicTrustSnapshotConflictException(this.snapshotId)
      : super(
          'Snapshot conflict for id: $snapshotId',
          code: 'CT_SNAPSHOT_CONFLICT',
        );

  final String snapshotId;
}

class CryptographicTrustNotFoundException extends CryptographicTrustException {
  CryptographicTrustNotFoundException(this.snapshotId)
      : super('Snapshot not found: $snapshotId', code: 'CT_NOT_FOUND');

  final String snapshotId;
}

class CryptographicTrustUnsupportedOperationException
    extends CryptographicTrustException {
  CryptographicTrustUnsupportedOperationException(
    String operation, {
    String? algorithmId,
  }) : super(
          'Unsupported operation: $operation${algorithmId != null ? ' for $algorithmId' : ''}',
          code: 'CT_UNSUPPORTED_OPERATION',
        );
}
