import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_snapshot.dart';
import 'telemetry_canonical_serializer.dart';

/// Deterministic telemetry event ID factory.
class TelemetryEventIdFactory {
  const TelemetryEventIdFactory({TelemetryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const TelemetryCanonicalSerializer();

  final TelemetryCanonicalSerializer _serializer;

  String create({
    required String component,
    required String operation,
    required String operationId,
    required String eventType,
    required TelemetryEvent event,
  }) {
    final fingerprint = _serializer.eventFingerprint(event);
    return 'telemetry-event:$component:$operation:$operationId:$eventType:$fingerprint';
  }
}

/// Deterministic telemetry snapshot ID factory.
class TelemetrySnapshotIdFactory {
  const TelemetrySnapshotIdFactory();

  String create({
    required String scopeFingerprint,
    required String telemetryFingerprint,
    int schemaVersion = TelemetrySnapshotMetadata.currentSchemaVersion,
  }) {
    return 'telemetry:$scopeFingerprint:$telemetryFingerprint:$schemaVersion';
  }
}
