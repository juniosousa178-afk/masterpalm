/// Provider operation being instrumented or reported.
enum CryptographicTrustOperation {
  evaluate,
  evaluateAndPublish,
  publish,
  load,
  latest,
  query,
  invalidate,
  resolve,
  collect,
  computeDigest,
  verifySignature,
  verifyAttestation,
  sign,
  build,
  validate,
}

extension CryptographicTrustOperationX on CryptographicTrustOperation {
  String get wireName => name;

  static CryptographicTrustOperation fromWireName(String value) {
    return CryptographicTrustOperation.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustOperation: $value',
      ),
    );
  }
}

/// Operational evaluation outcome status.
enum CryptographicTrustEvaluationStatus {
  success,
  partial,
  failure,
  unavailable,
}

extension CryptographicTrustEvaluationStatusX
    on CryptographicTrustEvaluationStatus {
  String get wireName => name;

  static CryptographicTrustEvaluationStatus fromWireName(String value) {
    return CryptographicTrustEvaluationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustEvaluationStatus: $value',
      ),
    );
  }
}

/// Aggregate source resolution outcome for trust evaluation.
enum CryptographicTrustSourceResolutionStatus {
  complete,
  partial,
  failed,
  unavailable,
}

extension CryptographicTrustSourceResolutionStatusX
    on CryptographicTrustSourceResolutionStatus {
  String get wireName => name;

  static CryptographicTrustSourceResolutionStatus fromWireName(String value) {
    return CryptographicTrustSourceResolutionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustSourceResolutionStatus: $value',
      ),
    );
  }
}

/// Cryptographic primitive operation taxonomy.
enum CryptographicPrimitiveOperation {
  computeDigest,
  verifySignature,
  sign,
  resolvePublicKey,
  resolveSigningHandle,
  verifyTransparencyProof,
}

extension CryptographicPrimitiveOperationX on CryptographicPrimitiveOperation {
  String get wireName => name;

  static CryptographicPrimitiveOperation fromWireName(String value) {
    return CryptographicPrimitiveOperation.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicPrimitiveOperation: $value',
      ),
    );
  }
}

/// Capability flags exposed by cryptographic providers.
enum CryptographicProviderCapability {
  digest,
  signatureVerification,
  signing,
  publicKeyResolution,
  signingKeyResolution,
  transparencyProofVerification,
}

extension CryptographicProviderCapabilityX on CryptographicProviderCapability {
  String get wireName => name;

  static CryptographicProviderCapability fromWireName(String value) {
    return CryptographicProviderCapability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicProviderCapability: $value',
      ),
    );
  }
}

/// Structured conflict classification during trust evaluation.
enum CryptographicTrustConflictType {
  duplicateVersion,
  fingerprintMismatch,
  policyConflict,
  algorithmConflict,
  sourceConflict,
}

extension CryptographicTrustConflictTypeX on CryptographicTrustConflictType {
  String get wireName => name;

  static CryptographicTrustConflictType fromWireName(String value) {
    return CryptographicTrustConflictType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustConflictType: $value',
      ),
    );
  }
}

/// Source resolution mode for individual trust sources.
enum CryptographicTrustSourceResolutionMode {
  injected,
  byId,
  latest,
  notRequested,
}

extension CryptographicTrustSourceResolutionModeX
    on CryptographicTrustSourceResolutionMode {
  String get wireName => name;

  static CryptographicTrustSourceResolutionMode fromWireName(String value) {
    return CryptographicTrustSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustSourceResolutionMode: $value',
      ),
    );
  }
}

/// Availability state for an individual resolved trust source.
enum CryptographicTrustSourceState {
  available,
  unavailable,
  notRequested,
}

extension CryptographicTrustSourceStateX on CryptographicTrustSourceState {
  String get wireName => name;

  static CryptographicTrustSourceState fromWireName(String value) {
    return CryptographicTrustSourceState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustSourceState: $value',
      ),
    );
  }
}

enum CryptographicPrimitiveOutcome {
  valid,
  invalid,
  unsupported,
  unavailable,
  malformed,
  algorithmMismatch,
  keyNotFound,
  expired,
  revoked,
}

extension CryptographicPrimitiveOutcomeX on CryptographicPrimitiveOutcome {
  String get wireName => name;

  static CryptographicPrimitiveOutcome fromWireName(String value) {
    return CryptographicPrimitiveOutcome.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicPrimitiveOutcome: $value',
      ),
    );
  }
}
