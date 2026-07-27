import '../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../models/persistent_artifacts/persistent_artifact_validation_result.dart';

typedef PersistentArtifactValidationAddError = void Function(
  String code,
  String path,
  String message, {
  String? artifactId,
  String? versionId,
  String? locationId,
  String? policyId,
});

typedef PersistentArtifactValidationAddWarning = void Function(
  String code,
  String path,
  String message, {
  String? artifactId,
  String? versionId,
  String? locationId,
  String? policyId,
});

const sensitiveMetadataKeys = {
  'privatekey',
  'secret',
  'password',
  'token',
  'credential',
  'presigned',
  'presignedurl',
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

final _hexDigestPattern = RegExp(r'^[0-9a-fA-F]+$');

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

bool isPresignedUrlValue(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('presigned')) return true;
  if (normalized.contains('x-amz-signature')) return true;
  if (normalized.contains('x-goog-signature')) return true;
  if (normalized.contains('sig=') && normalized.contains('expires=')) {
    return true;
  }
  return false;
}

bool isStructurallyValidHexDigest(String value) {
  if (value.isEmpty) return false;
  if (!_hexDigestPattern.hasMatch(value)) return false;
  return value.length.isEven;
}

void validateSensitiveMetadata(
  Map<String, String> metadata,
  String path,
  PersistentArtifactValidationAddError addError, {
  String code = 'PA_SENSITIVE_METADATA',
}) {
  for (final key in metadata.keys) {
    if (isSensitiveMetadataKey(key)) {
      addError(
        code,
        '$path.$key',
        'sensitive metadata key is not allowed: $key',
      );
    }
  }
}

void validatePresignedMetadataValues(
  Map<String, String> metadata,
  String path,
  PersistentArtifactValidationAddError addError, {
  String code = 'PA_PRESIGNED_METADATA_VALUE',
}) {
  for (final entry in metadata.entries) {
    if (isPresignedUrlValue(entry.value)) {
      addError(
        code,
        '$path.${entry.key}',
        'presigned URL metadata value is not allowed: ${entry.key}',
      );
    }
  }
}

void validateReleaseAuthorizationMetadata(
  Map<String, String> metadata,
  String path,
  PersistentArtifactValidationAddError addError, {
  String code = 'PA_RELEASE_AUTHORIZATION_METADATA',
}) {
  for (final key in metadata.keys) {
    if (isReleaseAuthorizationMetadataKey(key)) {
      addError(
        code,
        '$path.$key',
        'release authorization metadata is not allowed: $key',
      );
    }
  }
}

bool isIso8601Coherent(String? from, String? until) {
  if (from == null || until == null) return true;
  if (from.isEmpty || until.isEmpty) return true;
  return from.compareTo(until) <= 0;
}

bool isIsoDateRangeCoherent(String? from, String? until) {
  if (from == null || until == null || from.isEmpty || until.isEmpty) {
    return true;
  }
  return from.compareTo(until) <= 0;
}

bool hasCriticalIssues(
  Iterable<PersistentArtifactIssueSeverity> severities,
) {
  return severities.any(
    (severity) => severity == PersistentArtifactIssueSeverity.critical,
  );
}

PersistentArtifactValidationResult buildPersistentArtifactValidationResult({
  required List<PersistentArtifactIssue> issues,
  required List<String> warnings,
  required List<String> errors,
  List<String> infos = const [],
}) {
  final sortedIssues = List<PersistentArtifactIssue>.from(issues)
    ..sort((a, b) => a.code.compareTo(b.code));
  return PersistentArtifactValidationResult(
    isValid: errors.isEmpty,
    issues: sortedIssues,
    warnings: List<String>.unmodifiable(warnings),
    errors: List<String>.unmodifiable(errors),
    infos: List<String>.unmodifiable(infos),
  );
}

void addPersistentArtifactValidationError(
  List<PersistentArtifactIssue> issues,
  List<String> errors, {
  required String code,
  required String path,
  required String message,
  String? artifactId,
  String? versionId,
  String? locationId,
  String? policyId,
}) {
  errors.add(message);
  issues.add(
    PersistentArtifactIssue(
      code: code,
      path: path,
      severity: PersistentArtifactIssueSeverity.critical,
      message: message,
      artifactId: artifactId,
      versionId: versionId,
      locationId: locationId,
      policyId: policyId,
    ),
  );
}

void addPersistentArtifactValidationWarning(
  List<PersistentArtifactIssue> issues,
  List<String> warnings, {
  required String code,
  required String path,
  required String message,
  String? artifactId,
  String? versionId,
  String? locationId,
  String? policyId,
}) {
  warnings.add(message);
  issues.add(
    PersistentArtifactIssue(
      code: code,
      path: path,
      severity: PersistentArtifactIssueSeverity.warning,
      message: message,
      artifactId: artifactId,
      versionId: versionId,
      locationId: locationId,
      policyId: policyId,
    ),
  );
}
