import '../models/cryptographic_trust/cryptographic_signer_identity.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicSignerIdentity].
class CryptographicSignerIdentityValidator {
  const CryptographicSignerIdentityValidator();

  CryptographicValidationResult validate(CryptographicSignerIdentity identity) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

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

    if (identity.identityId.isEmpty) {
      addError('CT_SIGNER_ID', 'identityId', 'identityId is required');
    }
    if (identity.keyId.isEmpty) {
      addError('CT_SIGNER_KEY_ID', 'keyId', 'keyId is required');
    }

    validateSensitiveMetadata(
      identity.claims,
      'claims',
      addError,
      code: 'CT_SIGNER_SENSITIVE_CLAIM',
    );
    validateSensitiveMetadata(
      identity.metadata,
      'metadata',
      addError,
      code: 'CT_SIGNER_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
