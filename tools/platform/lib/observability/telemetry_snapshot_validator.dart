import '../models/observability/telemetry_snapshot.dart';

/// Validates telemetry snapshot invariants.
class TelemetrySnapshotValidator {
  const TelemetrySnapshotValidator();

  TelemetrySnapshotValidationResult validate(TelemetrySnapshot snapshot) {
    final errors = <String>[];
    final meta = snapshot.metadata;

    if (meta.telemetrySnapshotId.trim().isEmpty) {
      errors.add('telemetrySnapshotId must not be empty');
    }
    if (meta.scopeFingerprint.trim().isEmpty) {
      errors.add('scopeFingerprint must not be empty');
    }
    if (meta.telemetryFingerprint.trim().isEmpty) {
      errors.add('telemetryFingerprint must not be empty');
    }

    final eventIds = snapshot.events.map((e) => e.eventId).toList();
    if (eventIds.length != eventIds.toSet().length) {
      errors.add('duplicate eventId');
    }

    if (meta.eventCount != snapshot.events.length) {
      errors.add('eventCount mismatch');
    }
    if (meta.warningCount != snapshot.warnings.length) {
      errors.add('warningCount mismatch');
    }
    if (meta.errorCount != snapshot.errors.length) {
      errors.add('errorCount mismatch');
    }

    if (snapshot.summary.eventCount != snapshot.events.length) {
      errors.add('summary eventCount mismatch');
    }

    return TelemetrySnapshotValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: const [],
    );
  }
}
