import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_requirement.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicTrustRequirement].
class CryptographicTrustRequirementValidator {
  const CryptographicTrustRequirementValidator();

  CryptographicValidationResult validate(
    CryptographicTrustRequirement requirement,
  ) {
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

    if (requirement.requirementId.isEmpty) {
      addError(
        'CT_REQUIREMENT_ID',
        'requirementId',
        'requirementId is required',
      );
    }

    if (requirement.requiredSignatureCount != null &&
        requirement.requiredSignatureCount! < 0) {
      addError(
        'CT_REQUIREMENT_SIGNATURE_COUNT',
        'requiredSignatureCount',
        'requiredSignatureCount must be >= 0',
        relatedId: requirement.requirementId,
      );
    }

    if (requirement.requireTrustAnchor && !requirement.required) {
      addWarning(
        'CT_REQUIREMENT_TRUST_ANCHOR_OPTIONAL',
        'requireTrustAnchor',
        'requireTrustAnchor is set but requirement is not required',
        relatedId: requirement.requirementId,
      );
    }

    if (requirement.requireTransparencyLog && !requirement.required) {
      addWarning(
        'CT_REQUIREMENT_TRANSPARENCY_LOG_OPTIONAL',
        'requireTransparencyLog',
        'requireTransparencyLog is set but requirement is not required',
        relatedId: requirement.requirementId,
      );
    }

    final trustAnchorId = requirement.constraints['trustAnchorId'];
    if (trustAnchorId != null && trustAnchorId.isEmpty) {
      addError(
        'CT_REQUIREMENT_TRUST_ANCHOR_ID',
        'constraints.trustAnchorId',
        'constraints.trustAnchorId must not be empty when present',
        relatedId: requirement.requirementId,
      );
    }

    validateSensitiveMetadata(
      requirement.constraints,
      'constraints',
      addError,
      code: 'CT_REQUIREMENT_SENSITIVE_CONSTRAINT',
    );
    validateSensitiveMetadata(
      requirement.metadata,
      'metadata',
      addError,
      code: 'CT_REQUIREMENT_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
