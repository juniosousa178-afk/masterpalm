enum PersistentArtifactEvaluationStatus {
  success,
  partial,
  failure,
  unavailable,
}

extension PersistentArtifactEvaluationStatusX
    on PersistentArtifactEvaluationStatus {
  String get wireName => name;

  static PersistentArtifactEvaluationStatus fromWireName(String value) {
    return PersistentArtifactEvaluationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactEvaluationStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactSourceResolutionStatus {
  complete,
  partial,
  unavailable,
  failed,
}

extension PersistentArtifactSourceResolutionStatusX
    on PersistentArtifactSourceResolutionStatus {
  String get wireName => name;

  static PersistentArtifactSourceResolutionStatus fromWireName(String value) {
    return PersistentArtifactSourceResolutionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactSourceResolutionStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactSourceResolutionMode {
  injected,
  byId,
  latest,
  notRequested,
}

extension PersistentArtifactSourceResolutionModeX
    on PersistentArtifactSourceResolutionMode {
  String get wireName => name;

  static PersistentArtifactSourceResolutionMode fromWireName(String value) {
    return PersistentArtifactSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactSourceResolutionMode: $value',
      ),
    );
  }
}

enum PersistentArtifactSourceState {
  available,
  unavailable,
  notRequested,
}

extension PersistentArtifactSourceStateX on PersistentArtifactSourceState {
  String get wireName => name;

  static PersistentArtifactSourceState fromWireName(String value) {
    return PersistentArtifactSourceState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactSourceState: $value',
      ),
    );
  }
}

enum PersistentArtifactOperationalConflictType {
  fingerprintMismatch,
  duplicatedIdentity,
  incompatibleSource,
  unsupportedPolicy,
}

extension PersistentArtifactOperationalConflictTypeX
    on PersistentArtifactOperationalConflictType {
  String get wireName => name;

  static PersistentArtifactOperationalConflictType fromWireName(String value) {
    return PersistentArtifactOperationalConflictType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactOperationalConflictType: $value',
      ),
    );
  }
}

enum PersistentArtifactDeletionDecision {
  allow,
  block,
}

extension PersistentArtifactDeletionDecisionX
    on PersistentArtifactDeletionDecision {
  String get wireName => name;

  static PersistentArtifactDeletionDecision fromWireName(String value) {
    return PersistentArtifactDeletionDecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactDeletionDecision: $value',
      ),
    );
  }
}

enum PersistentArtifactRequirementStatus {
  satisfied,
  unmet,
  unknown,
}

extension PersistentArtifactRequirementStatusX
    on PersistentArtifactRequirementStatus {
  String get wireName => name;

  static PersistentArtifactRequirementStatus fromWireName(String value) {
    return PersistentArtifactRequirementStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactRequirementStatus: $value',
      ),
    );
  }
}
