import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_trust_validation_helper.dart';

/// Validates structural consistency of [CryptographicKeyReference].
class CryptographicKeyReferenceValidator {
  const CryptographicKeyReferenceValidator();

  CryptographicValidationResult validate(CryptographicKeyReference reference) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    if (reference.keyId.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_KEY_ID',
        path: 'keyId',
        message: 'keyId is required',
      );
    }
    if (reference.publicKeyFingerprint.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_KEY_FINGERPRINT',
        path: 'publicKeyFingerprint',
        message: 'publicKeyFingerprint is required',
      );
    }
    if (reference.usage.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_KEY_USAGE',
        path: 'usage',
        message: 'usage must not be empty',
      );
    }
    if (!CryptographicTrustValidationHelper.isIso8601Coherent(
      reference.validFrom,
      reference.validUntil,
    )) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_KEY_VALIDITY',
        path: 'validFrom',
        message: 'validFrom must be before or equal to validUntil',
        relatedId: reference.keyId,
      );
    }
    if (CryptographicTrustValidationHelper.hasSensitiveMetadataKey(
      reference.metadata,
    )) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_KEY_SENSITIVE_METADATA',
        path: 'metadata',
        message: 'metadata must not contain sensitive key material references',
        relatedId: reference.keyId,
      );
    }

    return CryptographicTrustValidationHelper.buildResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
