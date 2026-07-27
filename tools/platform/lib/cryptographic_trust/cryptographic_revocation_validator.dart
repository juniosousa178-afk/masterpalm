import '../models/cryptographic_trust/cryptographic_revocation_record.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_signer_identity_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicRevocationRecord].
class CryptographicRevocationValidator {
  const CryptographicRevocationValidator({
    CryptographicSignerIdentityValidator? signerIdentityValidator,
  }) : _signerIdentityValidator = signerIdentityValidator ??
            const CryptographicSignerIdentityValidator();

  final CryptographicSignerIdentityValidator _signerIdentityValidator;

  CryptographicValidationResult validate(CryptographicRevocationRecord record) {
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

    if (record.revocationId.isEmpty) {
      addError(
        'CT_REVOCATION_ID',
        'revocationId',
        'revocationId is required',
      );
    }
    if (record.subjectId.isEmpty) {
      addError(
        'CT_REVOCATION_SUBJECT_ID',
        'subjectId',
        'subjectId is required',
      );
    }
    if (!isIsoDateRangeCoherent(record.revokedAt, record.effectiveAt)) {
      addError(
        'CT_REVOCATION_EFFECTIVE_AT',
        'effectiveAt',
        'effectiveAt must be >= revokedAt',
        relatedId: record.revocationId,
      );
    }

    if (record.status == CryptographicRevocationStatus.superseded ||
        record.status == CryptographicRevocationStatus.cancelled) {
      addWarning(
        'CT_REVOCATION_STATUS',
        'status',
        'revocation status is ${record.status.wireName}',
        relatedId: record.revocationId,
      );
    }

    if (record.issuerIdentity != null) {
      merge(_signerIdentityValidator.validate(record.issuerIdentity!));
    }

    validateSensitiveMetadata(
      record.metadata,
      'metadata',
      addError,
      code: 'CT_REVOCATION_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
