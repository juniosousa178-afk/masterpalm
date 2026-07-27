import 'telemetry_enums.dart';
import 'telemetry_event.dart';

/// Operational coverage of telemetry instrumentation.
class TelemetryCoverage {
  const TelemetryCoverage({
    this.expectedOperationCount,
    required this.observedOperationCount,
    required this.completedOperationCount,
    required this.failedOperationCount,
    required this.incompleteOperationCount,
    required this.eventCoveragePercentage,
    required this.terminalEventCoveragePercentage,
    required this.componentCoverage,
    required this.missingOperationIds,
    required this.orphanEventIds,
  });

  final int? expectedOperationCount;
  final int observedOperationCount;
  final int completedOperationCount;
  final int failedOperationCount;
  final int incompleteOperationCount;
  final double eventCoveragePercentage;
  final double terminalEventCoveragePercentage;
  final Map<String, double> componentCoverage;
  final List<String> missingOperationIds;
  final List<String> orphanEventIds;

  Map<String, dynamic> toJson() => {
        if (expectedOperationCount != null)
          'expectedOperationCount': expectedOperationCount,
        'observedOperationCount': observedOperationCount,
        'completedOperationCount': completedOperationCount,
        'failedOperationCount': failedOperationCount,
        'incompleteOperationCount': incompleteOperationCount,
        'eventCoveragePercentage': eventCoveragePercentage,
        'terminalEventCoveragePercentage': terminalEventCoveragePercentage,
        'componentCoverage': componentCoverage,
        'missingOperationIds': missingOperationIds,
        'orphanEventIds': orphanEventIds,
      };

  factory TelemetryCoverage.fromJson(Map<String, dynamic> json) {
    return TelemetryCoverage(
      expectedOperationCount: json['expectedOperationCount'] as int?,
      observedOperationCount: json['observedOperationCount'] as int,
      completedOperationCount: json['completedOperationCount'] as int,
      failedOperationCount: json['failedOperationCount'] as int,
      incompleteOperationCount: json['incompleteOperationCount'] as int,
      eventCoveragePercentage:
          (json['eventCoveragePercentage'] as num).toDouble(),
      terminalEventCoveragePercentage:
          (json['terminalEventCoveragePercentage'] as num).toDouble(),
      componentCoverage:
          (json['componentCoverage'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
      missingOperationIds: (json['missingOperationIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      orphanEventIds: (json['orphanEventIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class TelemetryLimitation {
  const TelemetryLimitation({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory TelemetryLimitation.fromJson(Map<String, dynamic> json) {
    return TelemetryLimitation(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class TelemetrySummary {
  const TelemetrySummary({
    required this.eventCount,
    required this.operationCount,
    required this.successCount,
    required this.failureCount,
    required this.unavailableCount,
    required this.cacheHitCount,
    required this.cacheMissCount,
    required this.storeReadCount,
    required this.storeWriteCount,
    required this.conflictCount,
    required this.successRatePercentage,
  });

  final int eventCount;
  final int operationCount;
  final int successCount;
  final int failureCount;
  final int unavailableCount;
  final int cacheHitCount;
  final int cacheMissCount;
  final int storeReadCount;
  final int storeWriteCount;
  final int conflictCount;
  final double successRatePercentage;

  Map<String, dynamic> toJson() => {
        'eventCount': eventCount,
        'operationCount': operationCount,
        'successCount': successCount,
        'failureCount': failureCount,
        'unavailableCount': unavailableCount,
        'cacheHitCount': cacheHitCount,
        'cacheMissCount': cacheMissCount,
        'storeReadCount': storeReadCount,
        'storeWriteCount': storeWriteCount,
        'conflictCount': conflictCount,
        'successRatePercentage': successRatePercentage,
      };

  factory TelemetrySummary.fromJson(Map<String, dynamic> json) {
    return TelemetrySummary(
      eventCount: json['eventCount'] as int,
      operationCount: json['operationCount'] as int,
      successCount: json['successCount'] as int,
      failureCount: json['failureCount'] as int,
      unavailableCount: json['unavailableCount'] as int,
      cacheHitCount: json['cacheHitCount'] as int,
      cacheMissCount: json['cacheMissCount'] as int,
      storeReadCount: json['storeReadCount'] as int,
      storeWriteCount: json['storeWriteCount'] as int,
      conflictCount: json['conflictCount'] as int,
      successRatePercentage: (json['successRatePercentage'] as num).toDouble(),
    );
  }
}

class TelemetryComponentSummary {
  const TelemetryComponentSummary({
    required this.component,
    required this.eventCount,
    required this.successCount,
    required this.failureCount,
  });

  final TelemetryComponent component;
  final int eventCount;
  final int successCount;
  final int failureCount;

  Map<String, dynamic> toJson() => {
        'component': component.wireName,
        'eventCount': eventCount,
        'successCount': successCount,
        'failureCount': failureCount,
      };

  factory TelemetryComponentSummary.fromJson(Map<String, dynamic> json) {
    return TelemetryComponentSummary(
      component: TelemetryComponentX.fromWireName(json['component'] as String),
      eventCount: json['eventCount'] as int,
      successCount: json['successCount'] as int,
      failureCount: json['failureCount'] as int,
    );
  }
}

class TelemetryOperationSummary {
  const TelemetryOperationSummary({
    required this.operation,
    required this.eventCount,
    required this.successCount,
    required this.failureCount,
  });

  final TelemetryOperation operation;
  final int eventCount;
  final int successCount;
  final int failureCount;

  Map<String, dynamic> toJson() => {
        'operation': operation.wireName,
        'eventCount': eventCount,
        'successCount': successCount,
        'failureCount': failureCount,
      };

  factory TelemetryOperationSummary.fromJson(Map<String, dynamic> json) {
    return TelemetryOperationSummary(
      operation: TelemetryOperationX.fromWireName(json['operation'] as String),
      eventCount: json['eventCount'] as int,
      successCount: json['successCount'] as int,
      failureCount: json['failureCount'] as int,
    );
  }
}

class TelemetryDurationSummary {
  const TelemetryDurationSummary({
    required this.totalMicroseconds,
    required this.averageMicroseconds,
    required this.minMicroseconds,
    required this.maxMicroseconds,
    required this.sampleCount,
  });

  final int totalMicroseconds;
  final int averageMicroseconds;
  final int minMicroseconds;
  final int maxMicroseconds;
  final int sampleCount;

  Map<String, dynamic> toJson() => {
        'totalMicroseconds': totalMicroseconds,
        'averageMicroseconds': averageMicroseconds,
        'minMicroseconds': minMicroseconds,
        'maxMicroseconds': maxMicroseconds,
        'sampleCount': sampleCount,
      };

  factory TelemetryDurationSummary.fromJson(Map<String, dynamic> json) {
    return TelemetryDurationSummary(
      totalMicroseconds: json['totalMicroseconds'] as int,
      averageMicroseconds: json['averageMicroseconds'] as int,
      minMicroseconds: json['minMicroseconds'] as int,
      maxMicroseconds: json['maxMicroseconds'] as int,
      sampleCount: json['sampleCount'] as int,
    );
  }
}

class TelemetryFailureSummary {
  const TelemetryFailureSummary({
    required this.failureCount,
    required this.errorCodes,
  });

  final int failureCount;
  final Map<String, int> errorCodes;

  Map<String, dynamic> toJson() => {
        'failureCount': failureCount,
        'errorCodes': errorCodes,
      };

  factory TelemetryFailureSummary.fromJson(Map<String, dynamic> json) {
    return TelemetryFailureSummary(
      failureCount: json['failureCount'] as int,
      errorCodes: (json['errorCodes'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as int)),
    );
  }
}

class TelemetrySnapshotMetadata {
  const TelemetrySnapshotMetadata({
    required this.telemetrySnapshotId,
    required this.telemetrySchemaVersion,
    required this.telemetryCalculationVersion,
    required this.telemetryCanonicalizationVersion,
    required this.createdAt,
    required this.scopeFingerprint,
    required this.telemetryFingerprint,
    required this.status,
    required this.compatibility,
    required this.eventCount,
    required this.warningCount,
    required this.errorCount,
    this.projectId,
    this.correlationId,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String telemetrySnapshotId;
  final int telemetrySchemaVersion;
  final int telemetryCalculationVersion;
  final int telemetryCanonicalizationVersion;
  final String createdAt;
  final String scopeFingerprint;
  final String telemetryFingerprint;
  final TelemetrySnapshotStatus status;
  final TelemetryCompatibility compatibility;
  final int eventCount;
  final int warningCount;
  final int errorCount;
  final String? projectId;
  final String? correlationId;

  Map<String, dynamic> toJson() => {
        'telemetrySnapshotId': telemetrySnapshotId,
        'telemetrySchemaVersion': telemetrySchemaVersion,
        'telemetryCalculationVersion': telemetryCalculationVersion,
        'telemetryCanonicalizationVersion': telemetryCanonicalizationVersion,
        'createdAt': createdAt,
        'scopeFingerprint': scopeFingerprint,
        'telemetryFingerprint': telemetryFingerprint,
        'status': status.wireName,
        'compatibility': compatibility.wireName,
        'eventCount': eventCount,
        'warningCount': warningCount,
        'errorCount': errorCount,
        if (projectId != null) 'projectId': projectId,
        if (correlationId != null) 'correlationId': correlationId,
      };

  factory TelemetrySnapshotMetadata.fromJson(Map<String, dynamic> json) {
    return TelemetrySnapshotMetadata(
      telemetrySnapshotId: json['telemetrySnapshotId'] as String,
      telemetrySchemaVersion:
          json['telemetrySchemaVersion'] as int? ?? currentSchemaVersion,
      telemetryCalculationVersion:
          json['telemetryCalculationVersion'] as int? ??
              currentCalculationVersion,
      telemetryCanonicalizationVersion:
          json['telemetryCanonicalizationVersion'] as int? ??
              currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      scopeFingerprint: json['scopeFingerprint'] as String,
      telemetryFingerprint: json['telemetryFingerprint'] as String,
      status: TelemetrySnapshotStatusX.fromWireName(json['status'] as String),
      compatibility: TelemetryCompatibilityX.fromWireName(
        json['compatibility'] as String,
      ),
      eventCount: json['eventCount'] as int,
      warningCount: json['warningCount'] as int,
      errorCount: json['errorCount'] as int,
      projectId: json['projectId'] as String?,
      correlationId: json['correlationId'] as String?,
    );
  }
}

/// Immutable consolidated telemetry snapshot.
class TelemetrySnapshot {
  const TelemetrySnapshot({
    required this.metadata,
    required this.events,
    required this.summary,
    required this.componentSummaries,
    required this.operationSummaries,
    required this.failureSummary,
    required this.durationSummary,
    required this.coverage,
    required this.compatibility,
    required this.sourceReferences,
    required this.warnings,
    required this.errors,
    required this.limitations,
  });

  final TelemetrySnapshotMetadata metadata;
  final List<TelemetryEvent> events;
  final TelemetrySummary summary;
  final List<TelemetryComponentSummary> componentSummaries;
  final List<TelemetryOperationSummary> operationSummaries;
  final TelemetryFailureSummary failureSummary;
  final TelemetryDurationSummary durationSummary;
  final TelemetryCoverage coverage;
  final TelemetryCompatibility compatibility;
  final List<TelemetrySourceReference> sourceReferences;
  final List<TelemetryWarning> warnings;
  final List<TelemetryError> errors;
  final List<TelemetryLimitation> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'events': events.map((e) => e.toJson()).toList(),
        'summary': summary.toJson(),
        'componentSummaries':
            componentSummaries.map((c) => c.toJson()).toList(),
        'operationSummaries':
            operationSummaries.map((o) => o.toJson()).toList(),
        'failureSummary': failureSummary.toJson(),
        'durationSummary': durationSummary.toJson(),
        'coverage': coverage.toJson(),
        'compatibility': compatibility.wireName,
        'sourceReferences': sourceReferences.map((r) => r.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
      };

  factory TelemetrySnapshot.fromJson(Map<String, dynamic> json) {
    return TelemetrySnapshot(
      metadata: TelemetrySnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      events: (json['events'] as List<dynamic>)
          .map((e) => TelemetryEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: TelemetrySummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      componentSummaries: (json['componentSummaries'] as List<dynamic>)
          .map(
            (e) =>
                TelemetryComponentSummary.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      operationSummaries: (json['operationSummaries'] as List<dynamic>)
          .map(
            (e) =>
                TelemetryOperationSummary.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      failureSummary: TelemetryFailureSummary.fromJson(
        json['failureSummary'] as Map<String, dynamic>,
      ),
      durationSummary: TelemetryDurationSummary.fromJson(
        json['durationSummary'] as Map<String, dynamic>,
      ),
      coverage: TelemetryCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      compatibility: TelemetryCompatibilityX.fromWireName(
        json['compatibility'] as String,
      ),
      sourceReferences: (json['sourceReferences'] as List<dynamic>)
          .map(
            (e) => TelemetrySourceReference.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => TelemetryWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>)
          .map((e) => TelemetryError.fromJson(e as Map<String, dynamic>))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>)
          .map((e) => TelemetryLimitation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final events = (json['events'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['eventId']
          .toString()
          .compareTo((b as Map)['eventId'].toString()));
    json['events'] = events;
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    json['metadata'] = meta;
    return json;
  }
}

class TelemetrySnapshotValidationResult {
  const TelemetrySnapshotValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
