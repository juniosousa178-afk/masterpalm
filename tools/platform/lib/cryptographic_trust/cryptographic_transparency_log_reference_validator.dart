import '../models/cryptographic_trust/cryptographic_transparency_log_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_digest_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicTransparencyLogReference].
class CryptographicTransparencyLogReferenceValidator {
  const CryptographicTransparencyLogReferenceValidator({
    CryptographicDigestValidator? digestValidator,
  }) : _digestValidator =
            digestValidator ?? const CryptographicDigestValidator();

  final CryptographicDigestValidator _digestValidator;

  CryptographicValidationResult validate(
    CryptographicTransparencyLogReference reference,
  ) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(CryptographicValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
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

    void addWarning(
      String code,
      String path,
      String message, {
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

    if (reference.logId.isEmpty) {
      addError('CT_LOG_ID', 'logId', 'logId is required');
    }
    if (reference.entryId.isEmpty) {
      addError('CT_LOG_ENTRY_ID', 'entryId', 'entryId is required');
    }
    if (reference.logType.isEmpty) {
      addError('CT_LOG_TYPE', 'logType', 'logType is required');
    }

    if (reference.status == CryptographicTransparencyLogStatus.rejected ||
        reference.status == CryptographicTransparencyLogStatus.unknown) {
      addWarning(
        'CT_LOG_STATUS',
        'status',
        'transparency log status is ${reference.status.wireName}',
        relatedId: reference.entryId,
      );
    }

    merge(_digestValidator.validate(reference.entryDigest));

    validateSensitiveMetadata(
      reference.metadata,
      'metadata',
      addError,
      code: 'CT_LOG_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
