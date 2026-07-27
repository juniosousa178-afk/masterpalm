import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_trust_validation_helper.dart';

/// Validates structural consistency of [CryptographicDigest].
class CryptographicDigestValidator {
  const CryptographicDigestValidator();

  CryptographicValidationResult validate(CryptographicDigest digest) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    if (digest.subjectId.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_DIGEST_SUBJECT_ID',
        path: 'subjectId',
        message: 'subjectId is required',
      );
    }
    if (digest.value.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_DIGEST_VALUE',
        path: 'value',
        message: 'digest value is required',
      );
    }
    if (digest.encoding.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_DIGEST_ENCODING',
        path: 'encoding',
        message: 'encoding is required',
      );
    }
    if (digest.descriptor.algorithmId.isEmpty) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_DIGEST_DESCRIPTOR',
        path: 'descriptor.algorithmId',
        message: 'descriptor algorithmId is required',
      );
    }
    if (digest.descriptor.outputSizeBits != null &&
        digest.descriptor.outputSizeBits! <= 0) {
      CryptographicTrustValidationHelper.addError(
        issues,
        errors,
        code: 'CT_DIGEST_OUTPUT_SIZE',
        path: 'descriptor.outputSizeBits',
        message: 'outputSizeBits must be > 0 when present',
      );
    }

    return CryptographicTrustValidationHelper.buildResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
