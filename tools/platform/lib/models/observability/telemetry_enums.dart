/// Observability operating mode.
enum ObservabilityMode {
  disabled,
  collectOnly,
  full,
}

extension ObservabilityModeX on ObservabilityMode {
  String get wireName => name;

  static ObservabilityMode fromWireName(String value) {
    return ObservabilityMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ObservabilityMode: $value'),
    );
  }
}

/// Telemetry event kinds.
enum TelemetryEventType {
  operationStarted,
  operationCompleted,
  operationFailed,
  artifactResolved,
  artifactPublished,
  artifactLoaded,
  artifactNotFound,
  cacheHit,
  cacheMiss,
  validationCompleted,
  compatibilityChecked,
  bootstrapStarted,
  bootstrapCompleted,
  bootstrapFailed,
  providerRegistered,
  providerResolved,
  storeRead,
  storeWrite,
  storeConflict,
  reportGenerated,
  snapshotComposed,
}

extension TelemetryEventTypeX on TelemetryEventType {
  String get wireName => name;

  static TelemetryEventType fromWireName(String value) {
    return TelemetryEventType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown TelemetryEventType: $value'),
    );
  }
}

/// Event execution status.
enum TelemetryEventStatus {
  started,
  completed,
  failed,
  unavailable,
}

extension TelemetryEventStatusX on TelemetryEventStatus {
  String get wireName => name;

  static TelemetryEventStatus fromWireName(String value) {
    return TelemetryEventStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown TelemetryEventStatus: $value'),
    );
  }
}

/// Event severity.
enum TelemetrySeverity {
  debug,
  info,
  warning,
  error,
  critical,
}

extension TelemetrySeverityX on TelemetrySeverity {
  String get wireName => name;

  static TelemetrySeverity fromWireName(String value) {
    return TelemetrySeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown TelemetrySeverity: $value'),
    );
  }
}

/// Observable platform component.
enum TelemetryComponent {
  platformCore,
  bootstrap,
  ast,
  guardian,
  graph,
  report,
  metrics,
  history,
  score,
  mes,
  dashboard,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
  observability,
  provider,
  store,
  registry,
  unknown,
}

extension TelemetryComponentX on TelemetryComponent {
  String get wireName => name;

  static TelemetryComponent fromWireName(String value) {
    return TelemetryComponent.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown TelemetryComponent: $value'),
    );
  }
}

/// Typed telemetry operation.
enum TelemetryOperation {
  initialize,
  analyze,
  build,
  calculate,
  capture,
  compare,
  compose,
  generate,
  validate,
  evaluate,
  checkCompatibility,
  checkEligibility,
  publish,
  load,
  latest,
  query,
  invalidate,
  register,
  resolve,
  save,
  delete,
  bootstrap,
}

extension TelemetryOperationX on TelemetryOperation {
  String get wireName => name;

  static TelemetryOperation fromWireName(String value) {
    return TelemetryOperation.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown TelemetryOperation: $value'),
    );
  }
}

/// Attribute classification for data policy.
enum TelemetryAttributeClassification {
  public,
  internal,
  sensitive,
  prohibited,
}

extension TelemetryAttributeClassificationX
    on TelemetryAttributeClassification {
  String get wireName => name;

  static TelemetryAttributeClassification fromWireName(String value) {
    return TelemetryAttributeClassification.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown TelemetryAttributeClassification: $value',
      ),
    );
  }
}

/// Attribute value type.
enum TelemetryAttributeType {
  string,
  integer,
  decimal,
  boolean,
  enumValue,
  duration,
  artifactReference,
  count,
}

extension TelemetryAttributeTypeX on TelemetryAttributeType {
  String get wireName => name;

  static TelemetryAttributeType fromWireName(String value) {
    return TelemetryAttributeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown TelemetryAttributeType: $value'),
    );
  }
}

/// Redaction status of an attribute.
enum TelemetryRedactionStatus {
  none,
  redacted,
  rejected,
}

extension TelemetryRedactionStatusX on TelemetryRedactionStatus {
  String get wireName => name;

  static TelemetryRedactionStatus fromWireName(String value) {
    return TelemetryRedactionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown TelemetryRedactionStatus: $value'),
    );
  }
}

/// Telemetry snapshot status.
enum TelemetrySnapshotStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension TelemetrySnapshotStatusX on TelemetrySnapshotStatus {
  String get wireName => name;

  static TelemetrySnapshotStatus fromWireName(String value) {
    return TelemetrySnapshotStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown TelemetrySnapshotStatus: $value'),
    );
  }
}

/// Telemetry compatibility between events.
enum TelemetryCompatibility {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension TelemetryCompatibilityX on TelemetryCompatibility {
  String get wireName => name;

  static TelemetryCompatibility fromWireName(String value) {
    return TelemetryCompatibility.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown TelemetryCompatibility: $value'),
    );
  }
}

/// Sink failure handling policy.
enum TelemetrySinkFailurePolicy {
  swallowAndRecord,
  propagateOnlyInStrictMode,
  collectFailure,
}

extension TelemetrySinkFailurePolicyX on TelemetrySinkFailurePolicy {
  String get wireName => name;

  static TelemetrySinkFailurePolicy fromWireName(String value) {
    return TelemetrySinkFailurePolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown TelemetrySinkFailurePolicy: $value',
      ),
    );
  }
}
