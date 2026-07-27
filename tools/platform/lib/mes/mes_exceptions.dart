/// Base exception for MES operations.
class MESException implements Exception {
  MESException(this.message, {this.cause, this.code});

  final String message;
  final Object? cause;
  final String? code;

  @override
  String toString() => 'MESException($code): $message';
}

class MESPolicyException extends MESException {
  MESPolicyException(String message)
      : super(message, code: 'mes_policy_failed');
}

class MESValidationException extends MESException {
  MESValidationException(String message)
      : super(message, code: 'mes_validation_failed');
}

class MESCompatibilityException extends MESException {
  MESCompatibilityException(String message)
      : super(message, code: 'mes_compatibility_failed');
}

class MESConflictException extends MESException {
  MESConflictException(String snapshotId)
      : super('MES snapshot conflict: $snapshotId', code: 'mes_conflict');
}

class MESNotFoundException extends MESException {
  MESNotFoundException(String snapshotId)
      : super('MES snapshot not found: $snapshotId', code: 'mes_not_found');
}
