/// Policy lifecycle for CI/CD integration domain.
enum CicdIntegrationPolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension CicdIntegrationPolicyStatusX on CicdIntegrationPolicyStatus {
  String get wireName => name;

  static CicdIntegrationPolicyStatus fromWireName(String value) {
    return CicdIntegrationPolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationPolicyStatus: $value',
      ),
    );
  }
}

/// Operational result status.
enum CicdIntegrationResultStatus {
  success,
  partial,
  failure,
  unavailable,
}

extension CicdIntegrationResultStatusX on CicdIntegrationResultStatus {
  String get wireName => name;

  static CicdIntegrationResultStatus fromWireName(String value) {
    return CicdIntegrationResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationResultStatus: $value',
      ),
    );
  }
}

/// Snapshot completeness status.
enum CicdIntegrationSnapshotStatus {
  complete,
  partial,
  invalid,
}

extension CicdIntegrationSnapshotStatusX on CicdIntegrationSnapshotStatus {
  String get wireName => name;

  static CicdIntegrationSnapshotStatus fromWireName(String value) {
    return CicdIntegrationSnapshotStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationSnapshotStatus: $value',
      ),
    );
  }
}

/// Message severity during CI/CD integration evaluation.
enum CicdIntegrationMessageSeverity {
  info,
  warning,
  error,
  critical,
}

extension CicdIntegrationMessageSeverityX on CicdIntegrationMessageSeverity {
  String get wireName => name;

  static CicdIntegrationMessageSeverity fromWireName(String value) {
    return CicdIntegrationMessageSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationMessageSeverity: $value',
      ),
    );
  }
}

/// Source artifact kinds resolvable by CI/CD integration.
enum CicdIntegrationSourceType {
  pipelineDefinition,
  pipelineExecution,
  pipelineExecutionResult,
  deploymentPlan,
  deploymentResult,
  releaseEvidenceBundle,
  releaseSupplyChainSnapshot,
  pipelineIntegrationPolicy,
  pipelineExecutionPolicy,
  deploymentIntegrationPolicy,
}

extension CicdIntegrationSourceTypeX on CicdIntegrationSourceType {
  String get wireName => name;

  static CicdIntegrationSourceType fromWireName(String value) {
    return CicdIntegrationSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CicdIntegrationSourceType: $value'),
    );
  }
}

/// Provider operation being instrumented or reported.
enum CicdIntegrationOperation {
  evaluate,
  evaluateAndPublish,
  publish,
  load,
  latest,
  query,
  invalidate,
  resolve,
  collect,
  build,
  validate,
}

extension CicdIntegrationOperationX on CicdIntegrationOperation {
  String get wireName => name;

  static CicdIntegrationOperation fromWireName(String value) {
    return CicdIntegrationOperation.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CicdIntegrationOperation: $value'),
    );
  }
}

enum CicdIntegrationPublicationStatus {
  published,
  skipped,
}

extension CicdIntegrationPublicationStatusX
    on CicdIntegrationPublicationStatus {
  String get wireName => name;

  static CicdIntegrationPublicationStatus fromWireName(String value) {
    return CicdIntegrationPublicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationPublicationStatus: $value',
      ),
    );
  }
}

enum CicdIntegrationSourceResolutionMode {
  injected,
  byId,
  latest,
  notRequested,
}

extension CicdIntegrationSourceResolutionModeX
    on CicdIntegrationSourceResolutionMode {
  String get wireName => name;

  static CicdIntegrationSourceResolutionMode fromWireName(String value) {
    return CicdIntegrationSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationSourceResolutionMode: $value',
      ),
    );
  }
}

enum CicdIntegrationSourceState {
  available,
  unavailable,
  notRequested,
}

extension CicdIntegrationSourceStateX on CicdIntegrationSourceState {
  String get wireName => name;

  static CicdIntegrationSourceState fromWireName(String value) {
    return CicdIntegrationSourceState.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CicdIntegrationSourceState: $value'),
    );
  }
}
