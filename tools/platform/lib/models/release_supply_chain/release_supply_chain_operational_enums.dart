/// Policy lifecycle for release supply chain domain.
enum ReleaseSupplyChainPolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension ReleaseSupplyChainPolicyStatusX on ReleaseSupplyChainPolicyStatus {
  String get wireName => name;

  static ReleaseSupplyChainPolicyStatus fromWireName(String value) {
    return ReleaseSupplyChainPolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainPolicyStatus: $value',
      ),
    );
  }
}

/// Operational result status.
enum ReleaseSupplyChainResultStatus {
  success,
  partial,
  failure,
  unavailable,
}

extension ReleaseSupplyChainResultStatusX on ReleaseSupplyChainResultStatus {
  String get wireName => name;

  static ReleaseSupplyChainResultStatus fromWireName(String value) {
    return ReleaseSupplyChainResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainResultStatus: $value',
      ),
    );
  }
}

enum ReleaseSupplyChainPublicationStatus {
  published,
  skipped,
}

extension ReleaseSupplyChainPublicationStatusX
    on ReleaseSupplyChainPublicationStatus {
  String get wireName => name;

  static ReleaseSupplyChainPublicationStatus fromWireName(String value) {
    return ReleaseSupplyChainPublicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainPublicationStatus: $value',
      ),
    );
  }
}

enum ReleaseSupplyChainSourceResolutionMode {
  injected,
  byId,
  latest,
  notRequested,
}

extension ReleaseSupplyChainSourceResolutionModeX
    on ReleaseSupplyChainSourceResolutionMode {
  String get wireName => name;

  static ReleaseSupplyChainSourceResolutionMode fromWireName(String value) {
    return ReleaseSupplyChainSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainSourceResolutionMode: $value',
      ),
    );
  }
}

enum ReleaseSupplyChainSourceState {
  available,
  unavailable,
  notRequested,
}

extension ReleaseSupplyChainSourceStateX on ReleaseSupplyChainSourceState {
  String get wireName => name;

  static ReleaseSupplyChainSourceState fromWireName(String value) {
    return ReleaseSupplyChainSourceState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
          'Unknown ReleaseSupplyChainSourceState: $value'),
    );
  }
}

enum ReleaseSupplyChainSourceType {
  releaseContext,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  supplyChainPolicy,
  distributionPolicy,
  compliancePolicy,
}

extension ReleaseSupplyChainSourceTypeX on ReleaseSupplyChainSourceType {
  String get wireName => name;

  static ReleaseSupplyChainSourceType fromWireName(String value) {
    return ReleaseSupplyChainSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseSupplyChainSourceType: $value'),
    );
  }
}
