/// Domain exception for invalid release governance policy.
class ReleaseGovernancePolicyInvalidException implements Exception {
  ReleaseGovernancePolicyInvalidException(this.message, {this.policyId});

  final String message;
  final String? policyId;

  @override
  String toString() =>
      'ReleaseGovernancePolicyInvalidException${policyId != null ? '($policyId)' : ''}: $message';
}

/// Domain exception for invalid release context.
class ReleaseContextInvalidException implements Exception {
  ReleaseContextInvalidException(this.message, {this.releaseId});

  final String message;
  final String? releaseId;

  @override
  String toString() =>
      'ReleaseContextInvalidException${releaseId != null ? '($releaseId)' : ''}: $message';
}

/// Domain exception for invalid approval artifact.
class ReleaseApprovalInvalidException implements Exception {
  ReleaseApprovalInvalidException(this.message, {this.approvalId});

  final String message;
  final String? approvalId;

  @override
  String toString() =>
      'ReleaseApprovalInvalidException${approvalId != null ? '($approvalId)' : ''}: $message';
}

/// Domain exception for invalid waiver artifact.
class ReleaseWaiverInvalidException implements Exception {
  ReleaseWaiverInvalidException(this.message, {this.waiverId});

  final String message;
  final String? waiverId;

  @override
  String toString() =>
      'ReleaseWaiverInvalidException${waiverId != null ? '($waiverId)' : ''}: $message';
}

/// Domain exception for invalid release decision snapshot.
class ReleaseDecisionSnapshotInvalidException implements Exception {
  ReleaseDecisionSnapshotInvalidException(this.message, {this.snapshotId});

  final String message;
  final String? snapshotId;

  @override
  String toString() =>
      'ReleaseDecisionSnapshotInvalidException${snapshotId != null ? '($snapshotId)' : ''}: $message';
}

/// Policy was not found in the registry.
class ReleaseGovernancePolicyNotFoundException implements Exception {
  ReleaseGovernancePolicyNotFoundException(this.policyId, {this.policyVersion});

  final String policyId;
  final int? policyVersion;

  @override
  String toString() => policyVersion == null
      ? 'ReleaseGovernancePolicyNotFoundException: $policyId'
      : 'ReleaseGovernancePolicyNotFoundException: $policyId v$policyVersion';
}

/// Source resolution failed unexpectedly.
class ReleaseGovernanceSourceResolutionException implements Exception {
  ReleaseGovernanceSourceResolutionException(this.message, {this.sourceType});

  final String message;
  final String? sourceType;

  @override
  String toString() =>
      'ReleaseGovernanceSourceResolutionException: $message${sourceType == null ? '' : ' ($sourceType)'}';
}

/// Rule evaluation failed internally.
class ReleaseGovernanceEvaluationException implements Exception {
  ReleaseGovernanceEvaluationException(this.message, {this.ruleId});

  final String message;
  final String? ruleId;

  @override
  String toString() =>
      'ReleaseGovernanceEvaluationException: $message${ruleId == null ? '' : ' [$ruleId]'}';
}

/// Structural compatibility failure.
class ReleaseGovernanceCompatibilityException implements Exception {
  ReleaseGovernanceCompatibilityException(this.message);

  final String message;

  @override
  String toString() => 'ReleaseGovernanceCompatibilityException: $message';
}

/// Snapshot publish conflict.
class ReleaseGovernanceSnapshotConflictException implements Exception {
  ReleaseGovernanceSnapshotConflictException(this.snapshotId);

  final String snapshotId;

  @override
  String toString() =>
      'ReleaseGovernanceSnapshotConflictException: $snapshotId';
}

/// Registry is frozen.
class ReleaseGovernanceRegistryFrozenException implements Exception {
  ReleaseGovernanceRegistryFrozenException(this.registryName);

  final String registryName;

  @override
  String toString() =>
      'ReleaseGovernanceRegistryFrozenException: $registryName';
}

/// Snapshot was not found.
class ReleaseGovernanceNotFoundException implements Exception {
  ReleaseGovernanceNotFoundException(this.snapshotId);

  final String snapshotId;

  @override
  String toString() => 'ReleaseGovernanceNotFoundException: $snapshotId';
}
