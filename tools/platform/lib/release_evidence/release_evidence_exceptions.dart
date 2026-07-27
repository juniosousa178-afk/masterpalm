/// Domain exception for invalid release evidence policy.
class ReleaseEvidencePolicyInvalidException implements Exception {
  ReleaseEvidencePolicyInvalidException(this.message, {this.policyId});

  final String message;
  final String? policyId;

  @override
  String toString() =>
      'ReleaseEvidencePolicyInvalidException${policyId != null ? '($policyId)' : ''}: $message';
}

/// Domain exception for invalid release evidence bundle.
class ReleaseEvidenceBundleInvalidException implements Exception {
  ReleaseEvidenceBundleInvalidException(this.message, {this.bundleId});

  final String message;
  final String? bundleId;

  @override
  String toString() =>
      'ReleaseEvidenceBundleInvalidException${bundleId != null ? '($bundleId)' : ''}: $message';
}

/// Domain exception for invalid attestation policy.
class ReleaseAttestationPolicyInvalidException implements Exception {
  ReleaseAttestationPolicyInvalidException(this.message, {this.policyId});

  final String message;
  final String? policyId;

  @override
  String toString() =>
      'ReleaseAttestationPolicyInvalidException${policyId != null ? '($policyId)' : ''}: $message';
}

/// Domain exception for invalid attestation artifact.
class ReleaseAttestationInvalidException implements Exception {
  ReleaseAttestationInvalidException(this.message, {this.attestationId});

  final String message;
  final String? attestationId;

  @override
  String toString() =>
      'ReleaseAttestationInvalidException${attestationId != null ? '($attestationId)' : ''}: $message';
}

/// Domain exception for invalid verification policy.
class ReleaseVerificationPolicyInvalidException implements Exception {
  ReleaseVerificationPolicyInvalidException(this.message, {this.policyId});

  final String message;
  final String? policyId;

  @override
  String toString() =>
      'ReleaseVerificationPolicyInvalidException${policyId != null ? '($policyId)' : ''}: $message';
}

/// Domain exception for invalid verification result.
class ReleaseVerificationResultInvalidException implements Exception {
  ReleaseVerificationResultInvalidException(this.message,
      {this.verificationId});

  final String message;
  final String? verificationId;

  @override
  String toString() =>
      'ReleaseVerificationResultInvalidException${verificationId != null ? '($verificationId)' : ''}: $message';
}

/// Policy was not found in the registry.
class ReleaseEvidencePolicyNotFoundException implements Exception {
  ReleaseEvidencePolicyNotFoundException(this.policyId, {this.policyVersion});

  final String policyId;
  final int? policyVersion;

  @override
  String toString() => policyVersion == null
      ? 'ReleaseEvidencePolicyNotFoundException: $policyId'
      : 'ReleaseEvidencePolicyNotFoundException: $policyId v$policyVersion';
}

/// Bundle publish conflict.
class ReleaseEvidenceBundleConflictException implements Exception {
  ReleaseEvidenceBundleConflictException(this.bundleId);

  final String bundleId;

  @override
  String toString() => 'ReleaseEvidenceBundleConflictException: $bundleId';
}

/// Registry is frozen.
class ReleaseEvidenceRegistryFrozenException implements Exception {
  ReleaseEvidenceRegistryFrozenException(this.registryName);

  final String registryName;

  @override
  String toString() => 'ReleaseEvidenceRegistryFrozenException: $registryName';
}

/// Bundle was not found.
class ReleaseEvidenceNotFoundException implements Exception {
  ReleaseEvidenceNotFoundException(this.bundleId);

  final String bundleId;

  @override
  String toString() => 'ReleaseEvidenceNotFoundException: $bundleId';
}
