import 'telemetry_attributes.dart';
import 'telemetry_enums.dart';

/// Correlation context for telemetry events.
class TelemetryCorrelation {
  const TelemetryCorrelation({
    required this.correlationId,
    required this.operationId,
    this.causationId,
    this.parentEventId,
    this.requestId,
    this.projectId,
    this.branch,
    this.gitRef,
    this.sourceArtifactIds = const [],
    this.resultingArtifactIds = const [],
  });

  final String correlationId;
  final String? causationId;
  final String? parentEventId;
  final String? requestId;
  final String operationId;
  final String? projectId;
  final String? branch;
  final String? gitRef;
  final List<String> sourceArtifactIds;
  final List<String> resultingArtifactIds;

  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'operationId': operationId,
        if (causationId != null) 'causationId': causationId,
        if (parentEventId != null) 'parentEventId': parentEventId,
        if (requestId != null) 'requestId': requestId,
        if (projectId != null) 'projectId': projectId,
        if (branch != null) 'branch': branch,
        if (gitRef != null) 'gitRef': gitRef,
        'sourceArtifactIds': sourceArtifactIds,
        'resultingArtifactIds': resultingArtifactIds,
      };

  factory TelemetryCorrelation.fromJson(Map<String, dynamic> json) {
    return TelemetryCorrelation(
      correlationId: json['correlationId'] as String,
      operationId: json['operationId'] as String,
      causationId: json['causationId'] as String?,
      parentEventId: json['parentEventId'] as String?,
      requestId: json['requestId'] as String?,
      projectId: json['projectId'] as String?,
      branch: json['branch'] as String?,
      gitRef: json['gitRef'] as String?,
      sourceArtifactIds: (json['sourceArtifactIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      resultingArtifactIds:
          (json['resultingArtifactIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
    );
  }
}

/// Duration measurement for telemetry.
class TelemetryDuration {
  const TelemetryDuration({
    required this.durationMicroseconds,
    this.unit = 'microseconds',
    this.precision = 0,
    this.source = 'timer',
    this.availability = true,
  });

  final int durationMicroseconds;
  final String unit;
  final int precision;
  final String source;
  final bool availability;

  Map<String, dynamic> toJson() => {
        'durationMicroseconds': durationMicroseconds,
        'unit': unit,
        'precision': precision,
        'source': source,
        'availability': availability,
      };

  factory TelemetryDuration.fromJson(Map<String, dynamic> json) {
    return TelemetryDuration(
      durationMicroseconds: json['durationMicroseconds'] as int,
      unit: json['unit'] as String? ?? 'microseconds',
      precision: json['precision'] as int? ?? 0,
      source: json['source'] as String? ?? 'timer',
      availability: json['availability'] as bool? ?? true,
    );
  }
}

/// Sanitized telemetry error.
class TelemetryError {
  const TelemetryError({
    required this.errorCode,
    required this.errorType,
    required this.component,
    required this.operation,
    this.message,
    this.retryable,
    this.classification = TelemetryAttributeClassification.internal,
    this.stackTraceFingerprint,
    this.originalErrorAvailable = false,
    this.redacted = true,
  });

  final String errorCode;
  final String errorType;
  final TelemetryComponent component;
  final TelemetryOperation operation;
  final String? message;
  final bool? retryable;
  final TelemetryAttributeClassification classification;
  final String? stackTraceFingerprint;
  final bool originalErrorAvailable;
  final bool redacted;

  Map<String, dynamic> toJson() => {
        'errorCode': errorCode,
        'errorType': errorType,
        'component': component.wireName,
        'operation': operation.wireName,
        if (message != null) 'message': message,
        if (retryable != null) 'retryable': retryable,
        'classification': classification.wireName,
        if (stackTraceFingerprint != null)
          'stackTraceFingerprint': stackTraceFingerprint,
        'originalErrorAvailable': originalErrorAvailable,
        'redacted': redacted,
      };

  factory TelemetryError.fromJson(Map<String, dynamic> json) {
    return TelemetryError(
      errorCode: json['errorCode'] as String,
      errorType: json['errorType'] as String,
      component: TelemetryComponentX.fromWireName(json['component'] as String),
      operation: TelemetryOperationX.fromWireName(json['operation'] as String),
      message: json['message'] as String?,
      retryable: json['retryable'] as bool?,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'internal',
      ),
      stackTraceFingerprint: json['stackTraceFingerprint'] as String?,
      originalErrorAvailable: json['originalErrorAvailable'] as bool? ?? false,
      redacted: json['redacted'] as bool? ?? true,
    );
  }
}

class TelemetryWarning {
  const TelemetryWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory TelemetryWarning.fromJson(Map<String, dynamic> json) {
    return TelemetryWarning(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Reference to a source artifact in telemetry.
class TelemetrySourceReference {
  const TelemetrySourceReference({
    required this.referenceId,
    required this.artifactId,
    required this.sourceType,
    this.fingerprint,
  });

  final String referenceId;
  final String artifactId;
  final String sourceType;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'referenceId': referenceId,
        'artifactId': artifactId,
        'sourceType': sourceType,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory TelemetrySourceReference.fromJson(Map<String, dynamic> json) {
    return TelemetrySourceReference(
      referenceId: json['referenceId'] as String,
      artifactId: json['artifactId'] as String,
      sourceType: json['sourceType'] as String,
      fingerprint: json['fingerprint'] as String?,
    );
  }
}

class TelemetryEventMetadata {
  const TelemetryEventMetadata({
    required this.eventSchemaVersion,
    required this.eventFingerprint,
    this.extra = const {},
  });

  static const int currentSchemaVersion = 1;

  final int eventSchemaVersion;
  final String eventFingerprint;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'eventSchemaVersion': eventSchemaVersion,
        'eventFingerprint': eventFingerprint,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory TelemetryEventMetadata.fromJson(Map<String, dynamic> json) {
    return TelemetryEventMetadata(
      eventSchemaVersion:
          json['eventSchemaVersion'] as int? ?? currentSchemaVersion,
      eventFingerprint: json['eventFingerprint'] as String,
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Immutable operational telemetry event.
class TelemetryEvent {
  const TelemetryEvent({
    required this.eventId,
    required this.eventType,
    required this.component,
    required this.operation,
    required this.status,
    required this.severity,
    required this.correlation,
    required this.startedAt,
    required this.metadata,
    this.completedAt,
    this.duration,
    this.sourceReferences = const [],
    this.attributes = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  final String eventId;
  final TelemetryEventType eventType;
  final TelemetryComponent component;
  final TelemetryOperation operation;
  final TelemetryEventStatus status;
  final TelemetrySeverity severity;
  final TelemetryCorrelation correlation;
  final String startedAt;
  final String? completedAt;
  final TelemetryDuration? duration;
  final List<TelemetrySourceReference> sourceReferences;
  final List<TelemetryAttribute> attributes;
  final List<TelemetryWarning> warnings;
  final List<TelemetryError> errors;
  final TelemetryEventMetadata metadata;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'eventType': eventType.wireName,
        'component': component.wireName,
        'operation': operation.wireName,
        'status': status.wireName,
        'severity': severity.wireName,
        'correlation': correlation.toJson(),
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (duration != null) 'duration': duration!.toJson(),
        'sourceReferences': sourceReferences.map((r) => r.toJson()).toList(),
        'attributes': attributes.map((a) => a.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'metadata': metadata.toJson(),
      };

  factory TelemetryEvent.fromJson(Map<String, dynamic> json) {
    return TelemetryEvent(
      eventId: json['eventId'] as String,
      eventType: TelemetryEventTypeX.fromWireName(json['eventType'] as String),
      component: TelemetryComponentX.fromWireName(json['component'] as String),
      operation: TelemetryOperationX.fromWireName(json['operation'] as String),
      status: TelemetryEventStatusX.fromWireName(json['status'] as String),
      severity: TelemetrySeverityX.fromWireName(json['severity'] as String),
      correlation: TelemetryCorrelation.fromJson(
        json['correlation'] as Map<String, dynamic>,
      ),
      startedAt: json['startedAt'] as String,
      completedAt: json['completedAt'] as String?,
      duration: json['duration'] == null
          ? null
          : TelemetryDuration.fromJson(
              json['duration'] as Map<String, dynamic>),
      sourceReferences: (json['sourceReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => TelemetrySourceReference.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      attributes: (json['attributes'] as List<dynamic>? ?? [])
          .map((e) => TelemetryAttribute.fromJson(e as Map<String, dynamic>))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => TelemetryWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => TelemetryError.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: TelemetryEventMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final attrs = (json['attributes'] as List<dynamic>)
      ..sort((a, b) =>
          (a as Map)['key'].toString().compareTo((b as Map)['key'].toString()));
    json['attributes'] = attrs;
    final refs = (json['sourceReferences'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['referenceId']
          .toString()
          .compareTo((b as Map)['referenceId'].toString()));
    json['sourceReferences'] = refs;
    return json;
  }
}

class TelemetryEventValidationResult {
  const TelemetryEventValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
