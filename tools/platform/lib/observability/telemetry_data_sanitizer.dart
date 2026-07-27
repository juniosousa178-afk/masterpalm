import '../models/observability/telemetry_attributes.dart';
import '../models/observability/telemetry_enums.dart';
import 'telemetry_exceptions.dart';

/// Result of attribute redaction.
class TelemetryRedactionResult {
  const TelemetryRedactionResult({
    required this.attribute,
    required this.wasRedacted,
    required this.wasRejected,
    this.reason,
  });

  final TelemetryAttribute? attribute;
  final bool wasRedacted;
  final bool wasRejected;
  final String? reason;
}

/// Data policy for telemetry attributes.
class TelemetryDataPolicy {
  const TelemetryDataPolicy({
    this.prohibitedKeys = const {
      'password',
      'token',
      'secret',
      'apiKey',
      'credential',
      'authorization',
      'stackTrace',
      'sourceCode',
      'fileContent',
      'astPayload',
      'graphPayload',
      'snapshotPayload',
    },
    this.sensitiveKeys = const {
      'email',
      'path',
      'filePath',
      'repoPath',
    },
  });

  final Set<String> sensitiveKeys;
  final Set<String> prohibitedKeys;

  bool isProhibitedKey(String key) {
    final lower = key.toLowerCase();
    return prohibitedKeys.any((p) => lower.contains(p.toLowerCase()));
  }

  bool isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    return sensitiveKeys.any((p) => lower.contains(p.toLowerCase()));
  }
}

/// Sanitizes telemetry attribute values.
class TelemetryDataSanitizer {
  const TelemetryDataSanitizer({TelemetryDataPolicy? policy})
      : _policy = policy ?? const TelemetryDataPolicy();

  final TelemetryDataPolicy _policy;

  TelemetryRedactionResult sanitize(TelemetryAttribute attribute) {
    if (_policy.isProhibitedKey(attribute.key)) {
      return TelemetryRedactionResult(
        attribute: null,
        wasRedacted: false,
        wasRejected: true,
        reason: 'prohibited key: ${attribute.key}',
      );
    }

    if (attribute.classification ==
        TelemetryAttributeClassification.prohibited) {
      return TelemetryRedactionResult(
        attribute: null,
        wasRedacted: false,
        wasRejected: true,
        reason: 'prohibited classification',
      );
    }

    if (_policy.isSensitiveKey(attribute.key) ||
        attribute.classification ==
            TelemetryAttributeClassification.sensitive) {
      return TelemetryRedactionResult(
        attribute: TelemetryStringAttribute(
          key: attribute.key,
          stringValue: '[REDACTED]',
          classification: TelemetryAttributeClassification.sensitive,
          redactionStatus: TelemetryRedactionStatus.redacted,
        ),
        wasRedacted: true,
        wasRejected: false,
        reason: 'sensitive key redacted',
      );
    }

    final value = attribute.value?.toString() ?? '';
    if (value.contains(':\\') || value.startsWith('/Users/')) {
      return TelemetryRedactionResult(
        attribute: TelemetryStringAttribute(
          key: attribute.key,
          stringValue: '[PATH_REDACTED]',
          classification: TelemetryAttributeClassification.sensitive,
          redactionStatus: TelemetryRedactionStatus.redacted,
        ),
        wasRedacted: true,
        wasRejected: false,
        reason: 'physical path redacted',
      );
    }

    return TelemetryRedactionResult(
      attribute: attribute,
      wasRedacted: false,
      wasRejected: false,
    );
  }

  List<TelemetryAttribute> sanitizeAll(List<TelemetryAttribute> attributes) {
    final output = <TelemetryAttribute>[];
    for (final attr in attributes) {
      final result = sanitize(attr);
      if (result.wasRejected) {
        throw TelemetryDataPolicyException(
            result.reason ?? 'rejected attribute');
      }
      if (result.attribute != null) output.add(result.attribute!);
    }
    return output;
  }
}
