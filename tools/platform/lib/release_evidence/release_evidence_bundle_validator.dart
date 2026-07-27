import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';

/// Validates structural consistency of release evidence bundles.
class ReleaseEvidenceBundleValidator {
  const ReleaseEvidenceBundleValidator();

  ReleaseEvidenceValidationResult validate(ReleaseEvidenceBundle bundle) {
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

    final metadata = bundle.metadata;
    if (metadata.bundleId.isEmpty) {
      addError(
          'RE_BUNDLE_ID_REQUIRED', 'metadata.bundleId', 'bundleId is required');
    }
    if (bundle.fingerprint.isEmpty) {
      addError(
          'RE_BUNDLE_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (metadata.fingerprint.isEmpty) {
      addError(
        'RE_BUNDLE_METADATA_FINGERPRINT',
        'metadata.fingerprint',
        'metadata fingerprint is required',
      );
    }

    final subject = bundle.subject;
    if (subject.subjectId.isEmpty) {
      addError('RE_SUBJECT_ID', 'subject.subjectId', 'subjectId is required');
    }
    if (subject.projectId != metadata.projectId) {
      addError(
        'RE_PROJECT_MISMATCH',
        'subject.projectId',
        'subject projectId does not match bundle metadata',
      );
    }
    if (subject.releaseId != null &&
        subject.releaseId!.isNotEmpty &&
        subject.releaseId != metadata.releaseId) {
      addError(
        'RE_RELEASE_MISMATCH',
        'subject.releaseId',
        'subject releaseId does not match bundle metadata',
      );
    }
    if (subject.commitId != null &&
        subject.commitId!.isNotEmpty &&
        subject.commitId != metadata.commitId) {
      addError(
        'RE_COMMIT_MISMATCH',
        'subject.commitId',
        'subject commitId does not match bundle metadata',
      );
    }

    if (bundle.policyReference.policyId != metadata.policyId ||
        bundle.policyReference.policyVersion != metadata.policyVersion) {
      addError(
        'RE_POLICY_REFERENCE_MISMATCH',
        'policyReference',
        'policy reference does not match bundle metadata',
      );
    }

    if (bundle.releaseContextReference.projectId != metadata.projectId) {
      addError(
        'RE_RELEASE_CONTEXT_PROJECT_MISMATCH',
        'releaseContextReference.projectId',
        'release context projectId mismatch',
      );
    }
    if (bundle.releaseContextReference.releaseId != metadata.releaseId) {
      addError(
        'RE_RELEASE_CONTEXT_RELEASE_MISMATCH',
        'releaseContextReference.releaseId',
        'release context releaseId mismatch',
      );
    }

    if (bundle.qualityGateReference.qualityGateSnapshotId.isEmpty) {
      addError(
        'RE_QG_REFERENCE_REQUIRED',
        'qualityGateReference',
        'quality gate reference is required',
      );
    }
    if (bundle.releaseDecisionReference.releaseDecisionSnapshotId.isEmpty) {
      addError(
        'RE_RG_REFERENCE_REQUIRED',
        'releaseDecisionReference',
        'release decision reference is required',
      );
    }

    final evidenceIds = <String>{};
    for (final artifact in bundle.evidence) {
      final id = artifact.artifactReference.artifactId;
      if (!evidenceIds.add(id)) {
        addError(
          'RE_DUPLICATE_EVIDENCE',
          'evidence',
          'duplicate evidence artifactId: $id',
          relatedId: id,
        );
      }
      if (artifact.artifactReference.fingerprint.isEmpty) {
        addError(
          'RE_EVIDENCE_FINGERPRINT',
          'evidence.$id.fingerprint',
          'evidence fingerprint is required',
          relatedId: id,
        );
      }
    }

    final attestationIds = <String>{};
    for (final attestation in bundle.attestations) {
      final id = attestation.metadata.attestationId;
      if (!attestationIds.add(id)) {
        addError(
          'RE_DUPLICATE_ATTESTATION',
          'attestations',
          'duplicate attestationId: $id',
          relatedId: id,
        );
      }
    }

    final provenanceIds = <String>{};
    for (final provenance in bundle.provenance) {
      if (!provenanceIds.add(provenance.provenanceId)) {
        addError(
          'RE_DUPLICATE_PROVENANCE',
          'provenance',
          'duplicate provenanceId: ${provenance.provenanceId}',
          relatedId: provenance.provenanceId,
        );
      }
    }

    final sourceKeys = <String>{};
    for (final source in bundle.sourceReferences) {
      final key = '${source.sourceType.wireName}:${source.requestedId}';
      if (!sourceKeys.add(key)) {
        addError(
          'RE_DUPLICATE_SOURCE',
          'sourceReferences',
          'duplicate source reference: $key',
          relatedId: key,
        );
      }
    }

    final coverage = bundle.coverage;
    if (coverage.presentEvidenceCount != bundle.evidence.length) {
      addError(
        'RE_COVERAGE_EVIDENCE_COUNT',
        'coverage.presentEvidenceCount',
        'presentEvidenceCount does not match evidence list length',
      );
    }
    if (coverage.presentAttestationCount != bundle.attestations.length) {
      addError(
        'RE_COVERAGE_ATTESTATION_COUNT',
        'coverage.presentAttestationCount',
        'presentAttestationCount does not match attestation list length',
      );
    }

    if (bundle.compatibility.status ==
        ReleaseEvidenceCompatibilityStatus.incompatible) {
      warnings.add('bundle compatibility is incompatible');
    }
    if (bundle.eligibility.status ==
        ReleaseEvidenceEligibilityStatus.ineligible) {
      warnings.add('bundle eligibility is ineligible');
    }

    for (final percentage in [
      coverage.evidenceCoveragePercentage,
      coverage.attestationCoveragePercentage,
      coverage.provenanceCoveragePercentage,
      coverage.sourceCoveragePercentage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        addError(
          'RE_COVERAGE_PERCENTAGE',
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
