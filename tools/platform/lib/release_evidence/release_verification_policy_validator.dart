import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';
import '../models/release_evidence/release_verification_policy.dart';

/// Validates declarative verification policies.
class ReleaseVerificationPolicyValidator {
  const ReleaseVerificationPolicyValidator();

  ReleaseEvidenceValidationResult validate(
    ReleaseVerificationPolicy policy, {
    bool allowRetired = false,
  }) {
    final issues = <ReleaseEvidenceValidationIssue>[];
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
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(String code, String path, String message) {
      warnings.add(message);
      issues.add(
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          message: message,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError(
          'RV_POLICY_ID_REQUIRED', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RV_POLICY_VERSION_INVALID',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.owner.isEmpty) {
      addError('RV_OWNER_REQUIRED', 'metadata.owner', 'owner is required');
    }
    if (metadata.rationale.isEmpty) {
      addError('RV_RATIONALE_REQUIRED', 'metadata.rationale',
          'rationale is required');
    }
    if (metadata.status == ReleaseEvidencePolicyStatus.retired &&
        !allowRetired) {
      addWarning(
        'RV_RETIRED_POLICY',
        'metadata.status',
        'retired policy should only be used with historicalEvaluation',
      );
    }

    if (policy.supportedSchemas.isEmpty) {
      addError(
        'RV_SCHEMAS_EMPTY',
        'supportedSchemas',
        'supportedSchemas must not be empty',
      );
    }
    if (policy.supportedCanonicalizationVersions.isEmpty) {
      addError(
        'RV_CANONICALIZATION_EMPTY',
        'supportedCanonicalizationVersions',
        'supportedCanonicalizationVersions must not be empty',
      );
    }

    for (final percentage in [
      policy.minimumEvidenceCoverage,
      policy.minimumAttestationCoverage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        addError(
          'RV_COVERAGE_RANGE',
          'coverage',
          'coverage threshold out of range: $percentage',
        );
      }
    }

    if (policy.requireSignature && policy.allowUnverifiedSignature) {
      addWarning(
        'RV_SIGNATURE_UNVERIFIED_INCOHERENT',
        'signaturePolicy',
        'requireSignature with allowUnverifiedSignature may prevent fully verified status',
      );
    }
    if (policy.requireSignature &&
        policy.allowUnverifiedSignature &&
        !policy.allowPartialVerification) {
      addError(
        'RV_SIGNATURE_PARTIAL_INCOHERENT',
        'signaturePolicy',
        'requireSignature with allowUnverifiedSignature requires allowPartialVerification',
      );
    }

    if (!policy.requireProjectConsistency &&
        metadata.policyId.contains('production')) {
      addWarning(
        'RV_PROJECT_CONSISTENCY_DISABLED',
        'requireProjectConsistency',
        'project consistency disabled in production-oriented policy',
      );
    }
    if (!policy.requireCommitConsistency &&
        metadata.policyId.contains('production')) {
      addWarning(
        'RV_COMMIT_CONSISTENCY_DISABLED',
        'requireCommitConsistency',
        'commit consistency disabled in production-oriented policy',
      );
    }

    if (!policy.requireIssuerValidity) {
      addWarning(
        'RV_ISSUER_VALIDITY_DISABLED',
        'requireIssuerValidity',
        'issuer validity check is disabled',
      );
    }
    if (!policy.requireAuthorityValidity) {
      addWarning(
        'RV_AUTHORITY_VALIDITY_DISABLED',
        'requireAuthorityValidity',
        'authority validity check is disabled',
      );
    }

    return ReleaseEvidenceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
