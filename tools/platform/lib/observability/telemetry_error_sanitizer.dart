import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_event.dart';

/// Sanitizes errors for telemetry storage.
class TelemetryErrorSanitizer {
  const TelemetryErrorSanitizer();

  TelemetryError sanitize({
    required Object error,
    required TelemetryComponent component,
    required TelemetryOperation operation,
    StackTrace? stackTrace,
  }) {
    final type = error.runtimeType.toString();
    final message = _sanitizeMessage(error.toString());
    final fingerprint = stackTrace == null
        ? null
        : sha256.convert(utf8.encode(stackTrace.toString())).toString();

    return TelemetryError(
      errorCode: type,
      errorType: type,
      component: component,
      operation: operation,
      message: message,
      classification: TelemetryAttributeClassification.internal,
      stackTraceFingerprint: fingerprint,
      originalErrorAvailable: true,
      redacted: true,
    );
  }

  String _sanitizeMessage(String message) {
    if (message.length > 200) {
      return '${message.substring(0, 200)}...[truncated]';
    }
    return message;
  }
}
