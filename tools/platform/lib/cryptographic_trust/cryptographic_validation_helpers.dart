import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';

typedef CryptographicValidationAddError = void Function(
  String code,
  String path,
  String message, {
  String? relatedId,
});

typedef CryptographicValidationAddWarning = void Function(
  String code,
  String path,
  String message, {
  String? relatedId,
});

const sensitiveMetadataKeys = {
  'privatekey',
  'secret',
  'password',
  'token',
  'seed',
};

const _releaseAuthorizationMetadataPatterns = <String>[
  'releaseauthorized',
  'releaseauthorization',
  'authorizerelease',
  'releaseapproved',
  'deployauthorized',
  'deploymentauthorized',
  'releaseauthorizationgranted',
];

bool isSensitiveMetadataKey(String key) {
  final normalized = key.toLowerCase();
  if (sensitiveMetadataKeys.contains(normalized)) return true;
  for (final sensitive in sensitiveMetadataKeys) {
    if (normalized.contains(sensitive)) return true;
  }
  return false;
}

bool hasSensitiveMetadataKey(Map<String, String> metadata) {
  for (final key in metadata.keys) {
    if (isSensitiveMetadataKey(key)) return true;
  }
  return false;
}

bool isReleaseAuthorizationMetadataKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');
  return _releaseAuthorizationMetadataPatterns.any(normalized.contains);
}

void validateSensitiveMetadata(
  Map<String, String> metadata,
  String path,
  CryptographicValidationAddError addError, {
  String code = 'CT_SENSITIVE_METADATA',
}) {
  for (final key in metadata.keys) {
    if (isSensitiveMetadataKey(key)) {
      addError(
        code,
        '$path.$key',
        'sensitive metadata key is not allowed: $key',
        relatedId: key,
      );
    }
  }
}

void validateReleaseAuthorizationMetadata(
  Map<String, String> metadata,
  String path,
  CryptographicValidationAddError addError,
) {
  for (final key in metadata.keys) {
    if (isReleaseAuthorizationMetadataKey(key)) {
      addError(
        'CT_VERIFY_RESULT_RELEASE_AUTHORIZATION',
        '$path.$key',
        'release authorization metadata is not allowed: $key',
        relatedId: key,
      );
    }
  }
}

bool isIso8601Coherent(String? from, String? until) {
  if (from == null || until == null) return true;
  return from.compareTo(until) <= 0;
}

bool isIsoDateRangeCoherent(String? from, String? until) {
  if (from == null || until == null || from.isEmpty || until.isEmpty) {
    return true;
  }
  return from.compareTo(until) <= 0;
}

bool hasCriticalIssues(
  Iterable<CryptographicIssueSeverity> severities,
) {
  return severities.any(
    (severity) => severity == CryptographicIssueSeverity.critical,
  );
}

CryptographicValidationResult buildCryptographicValidationResult({
  required List<CryptographicValidationIssue> issues,
  required List<String> warnings,
  required List<String> errors,
}) {
  final sortedIssues = List<CryptographicValidationIssue>.from(issues)
    ..sort((a, b) => a.code.compareTo(b.code));
  return CryptographicValidationResult(
    isValid: errors.isEmpty,
    issues: sortedIssues,
    warnings: List<String>.unmodifiable(warnings),
    errors: List<String>.unmodifiable(errors),
  );
}

void addCryptographicValidationError(
  List<CryptographicValidationIssue> issues,
  List<String> errors, {
  required String code,
  required String path,
  required String message,
  String? relatedId,
}) {
  errors.add(message);
  issues.add(
    CryptographicValidationIssue(
      code: code,
      path: path,
      severity: CryptographicIssueSeverity.critical,
      message: message,
      relatedId: relatedId,
    ),
  );
}

void addCryptographicValidationWarning(
  List<CryptographicValidationIssue> issues,
  List<String> warnings, {
  required String code,
  required String path,
  required String message,
  String? relatedId,
}) {
  warnings.add(message);
  issues.add(
    CryptographicValidationIssue(
      code: code,
      path: path,
      severity: CryptographicIssueSeverity.warning,
      message: message,
      relatedId: relatedId,
    ),
  );
}
