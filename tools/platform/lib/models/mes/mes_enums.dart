/// Official lifecycle status for an MES policy version.
enum MESPolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension MESPolicyStatusX on MESPolicyStatus {
  String get wireName => name;

  static MESPolicyStatus fromWireName(String value) {
    return MESPolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MESPolicyStatus: $value'),
    );
  }
}

/// Evidence reliability tier for MES metric requirements.
enum MESEvidenceTier {
  authoritative,
  derived,
  contextual,
  experimental,
}

extension MESEvidenceTierX on MESEvidenceTier {
  String get wireName => name;

  static MESEvidenceTier fromWireName(String value) {
    return MESEvidenceTier.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MESEvidenceTier: $value'),
    );
  }
}

/// Project eligibility for official MES evaluation.
enum MESEligibilityStatus {
  eligible,
  partiallyEligible,
  ineligible,
  incompatible,
  unknown,
}

extension MESEligibilityStatusX on MESEligibilityStatus {
  String get wireName => name;

  static MESEligibilityStatus fromWireName(String value) {
    return MESEligibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown MESEligibilityStatus: $value'),
    );
  }
}

/// MES calculation outcome status.
enum MESStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension MESStatusX on MESStatus {
  String get wireName => name;

  static MESStatus fromWireName(String value) {
    return MESStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MESStatus: $value'),
    );
  }
}

/// Deterministic confidence derived from coverage and compatibility.
enum MESConfidence {
  full,
  high,
  moderate,
  low,
  insufficient,
  incompatible,
  unknown,
}

extension MESConfidenceX on MESConfidence {
  String get wireName => name;

  static MESConfidence fromWireName(String value) {
    return MESConfidence.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MESConfidence: $value'),
    );
  }
}

/// Compatibility between MES policy and input evidence.
enum MESCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension MESCompatibilityStatusX on MESCompatibilityStatus {
  String get wireName => name;

  static MESCompatibilityStatus fromWireName(String value) {
    return MESCompatibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown MESCompatibilityStatus: $value'),
    );
  }
}

/// Governance lifecycle status for policy registry.
enum MESGovernanceStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension MESGovernanceStatusX on MESGovernanceStatus {
  String get wireName => name;

  static MESGovernanceStatus fromWireName(String value) {
    return MESGovernanceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown MESGovernanceStatus: $value'),
    );
  }
}

/// Type of change recorded in MES policy governance.
enum MESPolicyChangeType {
  created,
  updated,
  deprecated,
  retired,
  statusChanged,
}

extension MESPolicyChangeTypeX on MESPolicyChangeType {
  String get wireName => name;

  static MESPolicyChangeType fromWireName(String value) {
    return MESPolicyChangeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown MESPolicyChangeType: $value'),
    );
  }
}
