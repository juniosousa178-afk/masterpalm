/// Dashboard composition outcome status.
enum DashboardStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension DashboardStatusX on DashboardStatus {
  String get wireName => name;

  static DashboardStatus fromWireName(String value) {
    return DashboardStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown DashboardStatus: $value'),
    );
  }
}

/// Availability of a dashboard section or widget.
enum DashboardAvailability {
  available,
  partial,
  unavailable,
}

extension DashboardAvailabilityX on DashboardAvailability {
  String get wireName => name;

  static DashboardAvailability fromWireName(String value) {
    return DashboardAvailability.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardAvailability: $value'),
    );
  }
}

/// Freshness of source artifacts relative to reference time.
enum DashboardFreshness {
  current,
  recent,
  stale,
  mixed,
  unknown,
}

extension DashboardFreshnessX on DashboardFreshness {
  String get wireName => name;

  static DashboardFreshness fromWireName(String value) {
    return DashboardFreshness.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown DashboardFreshness: $value'),
    );
  }
}

/// Compatibility between dashboard sources.
enum DashboardCompatibility {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension DashboardCompatibilityX on DashboardCompatibility {
  String get wireName => name;

  static DashboardCompatibility fromWireName(String value) {
    return DashboardCompatibility.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardCompatibility: $value'),
    );
  }
}

/// Typed dashboard section kinds.
enum DashboardSectionType {
  overview,
  mes,
  score,
  metrics,
  history,
  guardian,
  architecture,
  dataAccess,
  callable,
  coverage,
  compatibility,
  sources,
  limitations,
  observability,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  supplyChain,
  sbom,
  compliance,
  cicdPipeline,
  cicdExecution,
  cicdDeployment,
  cryptographicTrustSummary,
  cryptographicTrustSignatures,
  cryptographicTrustAttestations,
  cryptographicTrustChains,
  cryptographicTrustPolicyEvaluation,
  cryptographicTrustRevocation,
  cryptographicTrustTransparency,
  persistentArtifactsSummary,
}

extension DashboardSectionTypeX on DashboardSectionType {
  String get wireName => name;

  static DashboardSectionType fromWireName(String value) {
    return DashboardSectionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardSectionType: $value'),
    );
  }
}

/// Presentation widget kinds (semantic, not visual).
enum DashboardWidgetType {
  scalar,
  percentage,
  status,
  band,
  distribution,
  rankedList,
  keyValueList,
  comparison,
  delta,
  timelineSummary,
  table,
  textSummary,
  sourceList,
  limitationList,
}

extension DashboardWidgetTypeX on DashboardWidgetType {
  String get wireName => name;

  static DashboardWidgetType fromWireName(String value) {
    return DashboardWidgetType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardWidgetType: $value'),
    );
  }
}

/// How a dashboard source was resolved.
enum DashboardSourceResolutionMode {
  injected,
  byId,
  latest,
  derivedReference,
}

extension DashboardSourceResolutionModeX on DashboardSourceResolutionMode {
  String get wireName => name;

  static DashboardSourceResolutionMode fromWireName(String value) {
    return DashboardSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown DashboardSourceResolutionMode: $value',
      ),
    );
  }
}

/// Source artifact type reference.
enum DashboardSourceType {
  metrics,
  score,
  mes,
  history,
  historyDiff,
  guardian,
  graph,
  telemetry,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
}

extension DashboardSourceTypeX on DashboardSourceType {
  String get wireName => name;

  static DashboardSourceType fromWireName(String value) {
    return DashboardSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardSourceType: $value'),
    );
  }
}

/// Provider that supplied a source artifact.
enum DashboardProviderType {
  metrics,
  history,
  score,
  mes,
  guardian,
  graph,
  observability,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
}

extension DashboardProviderTypeX on DashboardProviderType {
  String get wireName => name;

  static DashboardProviderType fromWireName(String value) {
    return DashboardProviderType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardProviderType: $value'),
    );
  }
}

/// Layout presentation hints (semantic only).
enum DashboardPresentationHint {
  primary,
  secondary,
  compact,
  detailed,
  collapsible,
}

extension DashboardPresentationHintX on DashboardPresentationHint {
  String get wireName => name;

  static DashboardPresentationHint fromWireName(String value) {
    return DashboardPresentationHint.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown DashboardPresentationHint: $value',
      ),
    );
  }
}

/// Dashboard comparison mode.
enum DashboardComparisonMode {
  none,
  baseline,
}

extension DashboardComparisonModeX on DashboardComparisonMode {
  String get wireName => name;

  static DashboardComparisonMode fromWireName(String value) {
    return DashboardComparisonMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DashboardComparisonMode: $value'),
    );
  }
}
