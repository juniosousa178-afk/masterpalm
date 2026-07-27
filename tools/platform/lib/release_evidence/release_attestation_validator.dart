import '../models/release_evidence/release_attestation.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_attestation_statement.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';
import '../models/release_governance/release_governance_enums.dart';

/// Validates release attestation artifacts.
class ReleaseAttestationValidator {
  const ReleaseAttestationValidator();

  ReleaseEvidenceValidationResult validate(
    ReleaseAttestation attestation, {
    ReleaseAttestationPolicy? policy,
    String? referenceTime,
    String? expectedProjectId,
    String? expectedReleaseId,
    String? expectedCommitId,
    String? releaseGovernanceDecision,
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

    void addWarning(String message) {
      warnings.add(message);
    }

    final metadata = attestation.metadata;
    if (metadata.attestationId.isEmpty) {
      addError(
        'RA_ATTESTATION_ID',
        'metadata.attestationId',
        'attestationId is required',
      );
    }
    if (attestation.fingerprint.isEmpty) {
      addError('RA_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (attestation.subjects.isEmpty) {
      addError('RA_SUBJECT_REQUIRED', 'subjects',
          'at least one subject is required');
    }

    if (attestation.issuedAt.compareTo(attestation.validFrom) < 0) {
      addError(
        'RA_ISSUED_BEFORE_VALID',
        'issuedAt',
        'issuedAt must be >= validFrom',
      );
    }
    if (attestation.expiresAt != null &&
        attestation.expiresAt!.compareTo(attestation.validFrom) <= 0) {
      addError(
        'RA_EXPIRES_BEFORE_VALID',
        'expiresAt',
        'expiresAt must be after validFrom',
      );
    }

    if (referenceTime != null &&
        attestation.expiresAt != null &&
        attestation.expiresAt!.compareTo(referenceTime) <= 0) {
      addWarning('attestation is expired at referenceTime');
    }

    if (attestation.status == ReleaseAttestationStatus.revoked) {
      addWarning('attestation is revoked');
    }
    if (attestation.status == ReleaseAttestationStatus.superseded) {
      addWarning('attestation is superseded');
    }
    if (attestation.status == ReleaseAttestationStatus.expired) {
      addWarning('attestation status is expired');
    }

    if (attestation.issuer.issuerId.isEmpty) {
      addError('RA_ISSUER_ID', 'issuer.issuerId', 'issuerId is required');
    }
    if (attestation.authority.authorityId.isEmpty) {
      addError(
        'RA_AUTHORITY_ID',
        'authority.authorityId',
        'authorityId is required',
      );
    }
    if (attestation.authority.status !=
        ReleaseAttestationAuthorityStatus.active) {
      addError(
        'RA_AUTHORITY_INACTIVE',
        'authority.status',
        'attestation authority is not active',
      );
    }

    if (expectedProjectId != null && metadata.projectId != expectedProjectId) {
      addError(
        'RA_PROJECT_MISMATCH',
        'metadata.projectId',
        'attestation projectId mismatch',
      );
    }
    for (final subject in attestation.subjects) {
      if (expectedProjectId != null && subject.projectId != expectedProjectId) {
        addError(
          'RA_SUBJECT_PROJECT_MISMATCH',
          'subjects.${subject.subjectId}.projectId',
          'subject projectId mismatch',
        );
      }
      if (expectedReleaseId != null &&
          subject.releaseId != null &&
          subject.releaseId != expectedReleaseId) {
        addError(
          'RA_SUBJECT_RELEASE_MISMATCH',
          'subjects.${subject.subjectId}.releaseId',
          'subject releaseId mismatch',
        );
      }
      if (expectedCommitId != null &&
          subject.commitId != null &&
          subject.commitId != expectedCommitId) {
        addError(
          'RA_SUBJECT_COMMIT_MISMATCH',
          'subjects.${subject.subjectId}.commitId',
          'subject commitId mismatch',
        );
      }
    }

    if (policy != null) {
      if (!policy.supportedAttestationTypes
          .contains(metadata.attestationType)) {
        addError(
          'RA_UNSUPPORTED_TYPE',
          'metadata.attestationType',
          'attestation type is not supported by policy',
        );
      }
      if (!policy.supportedPredicateTypes
          .contains(attestation.predicate.predicateType)) {
        addError(
          'RA_UNSUPPORTED_PREDICATE',
          'predicate.predicateType',
          'predicate type is not supported by policy',
        );
      }
      if (policy.evidenceRequirements.minimumEvidenceCount > 0 &&
          attestation.evidenceReferences.length <
              policy.evidenceRequirements.minimumEvidenceCount) {
        addError(
          'RA_EVIDENCE_INCOMPLETE',
          'evidenceReferences',
          'insufficient evidence references',
        );
      }
      if (policy.signaturePolicy.signatureRequired &&
          attestation.signatureReference == null &&
          !policy.signaturePolicy.allowAbsentSignature) {
        addError(
          'RA_SIGNATURE_REQUIRED',
          'signatureReference',
          'signature reference is required',
        );
      }
      if (attestation.signatureReference != null &&
          attestation.signatureReference!.verificationStatus ==
              ReleaseSignatureVerificationStatus.unverified) {
        addWarning('signature is unverified');
      }
    }

    if (metadata.attestationType ==
        ReleaseAttestationType.releaseAuthorization) {
      _validateAuthorizationConsistency(
        attestation.statement,
        releaseGovernanceDecision,
        addError,
      );
    }

    return ReleaseEvidenceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  void _validateAuthorizationConsistency(
    ReleaseAttestationStatement statement,
    String? releaseGovernanceDecision,
    void Function(String code, String path, String message, {String? relatedId})
        addError,
  ) {
    final claim = statement.claim;
    if (releaseGovernanceDecision == null) return;
    final rejected = releaseGovernanceDecision ==
            ReleaseGovernanceDecision.rejected.wireName ||
        releaseGovernanceDecision == 'rejected';
    if (rejected &&
        (claim.authorizationConsistent == true ||
            statement.outcome == 'approved')) {
      addError(
        'RA_AUTHORIZATION_CONTRADICTS_REJECTED',
        'statement.claim',
        'releaseAuthorization attestation cannot approve a rejected release',
      );
    }
  }
}
