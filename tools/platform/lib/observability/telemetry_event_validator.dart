import '../models/observability/telemetry_attributes.dart';
import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';

/// Validates telemetry event invariants.
class TelemetryEventValidator {
  const TelemetryEventValidator();

  TelemetryEventValidationResult validate(TelemetryEvent event) {
    final errors = <String>[];
    final warnings = <String>[];

    if (event.eventId.trim().isEmpty) errors.add('eventId must not be empty');
    if (event.correlation.correlationId.trim().isEmpty) {
      errors.add('correlationId must not be empty');
    }
    if (event.correlation.operationId.trim().isEmpty) {
      errors.add('operationId must not be empty');
    }
    if (event.startedAt.trim().isEmpty)
      errors.add('startedAt must not be empty');

    if (event.completedAt != null &&
        event.completedAt!.compareTo(event.startedAt) < 0) {
      errors.add('completedAt must not be before startedAt');
    }

    if (event.duration != null && event.duration!.durationMicroseconds < 0) {
      errors.add('duration must not be negative');
    }

    if (event.status == TelemetryEventStatus.failed && event.errors.isEmpty) {
      errors.add('failed event must include error');
    }
    if (event.status == TelemetryEventStatus.completed &&
        event.errors.isNotEmpty) {
      errors.add('completed event must not include errors');
    }

    final keys = event.attributes.map((a) => a.key).toList();
    if (keys.length != keys.toSet().length) {
      errors.add('duplicate attribute key');
    }

    for (final attr in event.attributes) {
      if (attr.classification == TelemetryAttributeClassification.prohibited) {
        errors.add('prohibited attribute: ${attr.key}');
      }
      if (attr is TelemetryDecimalAttribute) {
        final v = attr.decimalValue;
        if (v.isNaN || v.isInfinite) errors.add('NaN/Infinity in attribute');
        if (v == -0.0) warnings.add('-0.0 normalized');
      }
    }

    if (event.metadata.eventFingerprint.trim().isEmpty) {
      errors.add('eventFingerprint must not be empty');
    }

    return TelemetryEventValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
