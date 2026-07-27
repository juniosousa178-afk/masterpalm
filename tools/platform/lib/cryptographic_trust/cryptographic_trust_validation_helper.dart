import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_validation_helpers.dart' as helpers;

/// Shared helpers for Cryptographic Trust structural validators.
class CryptographicTrustValidationHelper {
  static const sensitiveMetadataKeys = helpers.sensitiveMetadataKeys;

  static bool isIso8601Coherent(String? from, String? until) =>
      helpers.isIso8601Coherent(from, until);

  static bool hasSensitiveMetadataKey(Map<String, String> metadata) =>
      helpers.hasSensitiveMetadataKey(metadata);

  static CryptographicValidationResult buildResult({
    required List<CryptographicValidationIssue> issues,
    required List<String> warnings,
    required List<String> errors,
  }) =>
      helpers.buildCryptographicValidationResult(
        issues: issues,
        warnings: warnings,
        errors: errors,
      );

  static void addError(
    List<CryptographicValidationIssue> issues,
    List<String> errors, {
    required String code,
    required String path,
    required String message,
    String? relatedId,
  }) =>
      helpers.addCryptographicValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        relatedId: relatedId,
      );

  static void addWarning(
    List<CryptographicValidationIssue> issues,
    List<String> warnings, {
    required String code,
    required String path,
    required String message,
    String? relatedId,
  }) =>
      helpers.addCryptographicValidationWarning(
        issues,
        warnings,
        code: code,
        path: path,
        message: message,
        relatedId: relatedId,
      );
}
