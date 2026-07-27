/// Policy was not found in the registry.
class QualityGatePolicyNotFoundException implements Exception {
  QualityGatePolicyNotFoundException(this.policyId, {this.policyVersion});

  final String policyId;
  final int? policyVersion;

  @override
  String toString() => policyVersion == null
      ? 'QualityGatePolicyNotFoundException: $policyId'
      : 'QualityGatePolicyNotFoundException: $policyId v$policyVersion';
}

/// Policy failed validation.
class QualityGatePolicyInvalidException implements Exception {
  QualityGatePolicyInvalidException(this.message, {this.errors = const []});

  final String message;
  final List<String> errors;

  @override
  String toString() => 'QualityGatePolicyInvalidException: $message';
}

/// Source resolution failed unexpectedly.
class QualityGateSourceResolutionException implements Exception {
  QualityGateSourceResolutionException(this.message, {this.sourceType});

  final String message;
  final String? sourceType;

  @override
  String toString() =>
      'QualityGateSourceResolutionException: $message${sourceType == null ? '' : ' ($sourceType)'}';
}

/// Rule evaluation failed internally.
class QualityGateEvaluationException implements Exception {
  QualityGateEvaluationException(this.message, {this.ruleId});

  final String message;
  final String? ruleId;

  @override
  String toString() =>
      'QualityGateEvaluationException: $message${ruleId == null ? '' : ' [$ruleId]'}';
}

/// Structural compatibility failure.
class QualityGateCompatibilityException implements Exception {
  QualityGateCompatibilityException(this.message);

  final String message;

  @override
  String toString() => 'QualityGateCompatibilityException: $message';
}

/// Snapshot publish conflict.
class QualityGateSnapshotConflictException implements Exception {
  QualityGateSnapshotConflictException(this.snapshotId);

  final String snapshotId;

  @override
  String toString() => 'QualityGateSnapshotConflictException: $snapshotId';
}

/// Registry is frozen.
class QualityGateRegistryFrozenException implements Exception {
  QualityGateRegistryFrozenException(this.registryName);

  final String registryName;

  @override
  String toString() => 'QualityGateRegistryFrozenException: $registryName';
}

/// Snapshot was not found.
class QualityGateNotFoundException implements Exception {
  QualityGateNotFoundException(this.snapshotId);

  final String snapshotId;

  @override
  String toString() => 'QualityGateNotFoundException: $snapshotId';
}
