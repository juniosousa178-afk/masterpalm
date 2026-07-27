import '../models/cryptographic_trust/cryptographic_trust_anchor.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_key_reference_validator.dart';
import 'cryptographic_trust_validation_helper.dart';

/// Validates structural consistency of [CryptographicTrustAnchorReference].
class CryptographicTrustAnchorValidator {
  const CryptographicTrustAnchorValidator({
    CryptographicKeyReferenceValidator? keyReferenceValidator,
  }) : _keyReferenceValidator =
            keyReferenceValidator ?? const CryptographicKeyReferenceValidator();

  final CryptographicKeyReferenceValidator _keyReferenceValidator;

  CryptographicValidationResult validate(
    CryptographicTrustAnchorReference anchor,
  ) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(CryptographicValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    if (anchor.trustAnchorId.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_ANCHOR_ID',
        path: 'trustAnchorId',
        message: 'trustAnchorId is required',
      );
    }
    if (anchor.issuer.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_ANCHOR_ISSUER',
        path: 'issuer',
        message: 'issuer is required',
      );
    }
    if (!CryptographicTrustValidationHelper.isIso8601Coherent(
      anchor.validFrom,
      anchor.validUntil,
    )) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_ANCHOR_VALIDITY',
        path: 'validFrom',
        message: 'validFrom must be before or equal to validUntil',
        relatedId: anchor.trustAnchorId,
      );
    }

    merge(_keyReferenceValidator.validate(anchor.keyReference));

    return CryptographicTrustValidationHelper.buildResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
