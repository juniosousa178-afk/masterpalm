import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';
import '../models/release_evidence/release_verification_result.dart';

/// Validates structural consistency of verification results.
class ReleaseVerificationResultValidator {
  const ReleaseVerificationResultValidator();

  ReleaseEvidenceValidationResult validate(ReleaseVerificationResult result) {
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

    if (result.verificationId.isEmpty) {
      addError(
        'RV_RESULT_ID_REQUIRED',
        'verificationId',
        'verificationId is required',
      );
    }
    if (result.fingerprint.isEmpty) {
      addError(
          'RV_RESULT_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (result.subject.subjectId.isEmpty) {
      addError('RV_SUBJECT_ID', 'subject.subjectId', 'subjectId is required');
    }
    if (result.policyReference.policyId.isEmpty) {
      addError(
        'RV_POLICY_REFERENCE',
        'policyReference.policyId',
        'policyId is required',
      );
    }

    final checkIds = <String>{};
    for (final check in result.checks) {
      if (!checkIds.add(check.checkId)) {
        addError(
          'RV_DUPLICATE_CHECK',
          'checks',
          'duplicate checkId: ${check.checkId}',
          relatedId: check.checkId,
        );
      }
    }

    final verifiedEvidence = result.verifiedEvidenceIds.toSet();
    final rejectedEvidence = result.rejectedEvidenceIds.toSet();
    final evidenceOverlap = verifiedEvidence.intersection(rejectedEvidence);
    if (evidenceOverlap.isNotEmpty) {
      addError(
        'RV_EVIDENCE_ID_OVERLAP',
        'verifiedEvidenceIds',
        'evidence IDs cannot be both verified and rejected',
      );
    }

    final verifiedAttestations = result.verifiedAttestationIds.toSet();
    final rejectedAttestations = result.rejectedAttestationIds.toSet();
    final attestationOverlap =
        verifiedAttestations.intersection(rejectedAttestations);
    if (attestationOverlap.isNotEmpty) {
      addError(
        'RV_ATTESTATION_ID_OVERLAP',
        'verifiedAttestationIds',
        'attestation IDs cannot be both verified and rejected',
      );
    }

    final failedChecks = result.checks.where(
      (c) => c.status == ReleaseVerificationCheckStatus.failed,
    );
    final passedChecks = result.checks.where(
      (c) => c.status == ReleaseVerificationCheckStatus.passed,
    );

    switch (result.status) {
      case ReleaseVerificationStatus.verified:
        if (failedChecks.isNotEmpty) {
          addError(
            'RV_STATUS_VERIFIED_WITH_FAILURES',
            'status',
            'verified status cannot have failed checks',
          );
        }
      case ReleaseVerificationStatus.partiallyVerified:
        if (passedChecks.isEmpty && result.checks.isNotEmpty) {
          warnings.add('partiallyVerified without passed checks');
        }
      case ReleaseVerificationStatus.invalid:
        if (failedChecks.isEmpty && result.errors.isEmpty) {
          warnings.add('invalid status without failed checks or errors');
        }
      case ReleaseVerificationStatus.unverified:
      case ReleaseVerificationStatus.unavailable:
      case ReleaseVerificationStatus.incompatible:
      case ReleaseVerificationStatus.expired:
      case ReleaseVerificationStatus.error:
        break;
    }

    final coverage = result.coverage;
    for (final percentage in [
      coverage.evidenceCoveragePercentage,
      coverage.attestationCoveragePercentage,
      coverage.provenanceCoveragePercentage,
      coverage.sourceCoveragePercentage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        addError(
          'RV_COVERAGE_PERCENTAGE',
          'coverage',
          'coverage percentage out of range: $percentage',
        );
      }
    }

    return ReleaseEvidenceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
