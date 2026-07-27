import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_compatibility.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import '../models/release_evidence/release_evidence_subject.dart';
import '../models/release_evidence/release_verification_check.dart';
import '../models/release_evidence/release_verification_policy.dart';
import '../models/release_evidence/release_verification_result.dart';
import 'release_evidence_canonical_serializer.dart';
import 'release_evidence_identity_builder.dart';

/// Runs structural verification checks without approving release.
class ReleaseEvidenceVerificationEngine {
  ReleaseEvidenceVerificationEngine({
    ReleaseEvidenceCanonicalSerializer? serializer,
    ReleaseEvidenceIdentityBuilder? identityBuilder,
  })  : _serializer = serializer ?? const ReleaseEvidenceCanonicalSerializer(),
        _identityBuilder =
            identityBuilder ?? const ReleaseEvidenceIdentityBuilder();

  final ReleaseEvidenceCanonicalSerializer _serializer;
  final ReleaseEvidenceIdentityBuilder _identityBuilder;

  ReleaseVerificationResult verify({
    required ReleaseEvidenceBundle bundle,
    required ReleaseVerificationPolicy policy,
    required String evaluatedAt,
    String? referenceTime,
  }) {
    final refTime = referenceTime ?? bundle.metadata.referenceTime;
    final checks = <ReleaseVerificationCheck>[];
    final warnings = <ReleaseEvidenceWarning>[];
    final errors = <ReleaseEvidenceError>[];
    final limitations = <ReleaseEvidenceLimitation>[
      const ReleaseEvidenceLimitation(
        limitationId: 'no-release-approval',
        code: ReleaseEvidenceLimitationCode.noCryptographicVerification,
        description: 'Verification does not approve release progression',
        impact: 'Descriptive verification only',
        resolvable: false,
      ),
    ];
    final verifiedEvidenceIds = <String>[];
    final rejectedEvidenceIds = <String>[];
    final verifiedAttestationIds = <String>[];
    final rejectedAttestationIds = <String>[];

    checks.add(_fingerprintCheck(bundle));
    checks.add(_identityCheck(bundle));
    checks.add(_projectCheck(bundle, policy));
    checks.add(_commitCheck(bundle, policy));
    checks.add(_compatibilityCheck(bundle));
    checks.add(_provenanceCheck(bundle, policy));
    checks.add(_issuerCheck(bundle));
    checks.add(_authorityCheck(bundle));
    checks.add(_signatureReferenceCheck(bundle, policy));
    checks.add(_coverageCheck(bundle, policy));

    for (final artifact in bundle.evidence) {
      final id = artifact.artifactReference.artifactId;
      if (artifact.availability ==
              ReleaseEvidenceAvailabilityStatus.available &&
          artifact.compatibility ==
              ReleaseEvidenceCompatibilityStatus.compatible) {
        verifiedEvidenceIds.add(id);
      } else {
        rejectedEvidenceIds.add(id);
      }
    }

    for (final attestation in bundle.attestations) {
      final id = attestation.metadata.attestationId;
      if (attestation.status == ReleaseAttestationStatus.active ||
          attestation.status == ReleaseAttestationStatus.issued) {
        verifiedAttestationIds.add(id);
      } else {
        rejectedAttestationIds.add(id);
      }
    }

    final failedChecks = checks
        .where((c) => c.status == ReleaseVerificationCheckStatus.failed)
        .length;
    final unavailableChecks = checks
        .where((c) => c.status == ReleaseVerificationCheckStatus.unavailable)
        .length;

    final status = _deriveStatus(
      failedChecks: failedChecks,
      unavailableChecks: unavailableChecks,
      allowPartial: policy.allowPartialVerification,
    );

    if (status == ReleaseVerificationStatus.invalid) {
      errors.add(
        ReleaseEvidenceError(
          errorId: 'verification-failed',
          code: ReleaseEvidenceErrorCode.verificationFailure,
          message: 'One or more verification checks failed',
          recoverable: true,
          classification: 'verification',
        ),
      );
    }

    final policyFingerprint = policy.metadata.fingerprint ??
        _serializer.verificationPolicyFingerprint(policy);

    final provisional = ReleaseVerificationResult(
      verificationId: 'pending',
      subject: bundle.subject,
      policyReference: ReleaseVerificationPolicyReference(
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        policyFingerprint: policyFingerprint,
      ),
      status: status,
      checks: checks,
      compatibility: bundle.compatibility,
      eligibility: bundle.eligibility,
      coverage: bundle.coverage,
      verifiedEvidenceIds: verifiedEvidenceIds,
      rejectedEvidenceIds: rejectedEvidenceIds,
      verifiedAttestationIds: verifiedAttestationIds,
      rejectedAttestationIds: rejectedAttestationIds,
      explanations: _buildExplanations(status, checks),
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      evaluatedAt: evaluatedAt,
      referenceTime: refTime,
      fingerprint: 'pending',
      schemaVersion: ReleaseVerificationPolicyMetadata.currentSchemaVersion,
    );

    final fingerprint = _identityBuilder.verificationFingerprintForResult(
      provisional,
    );
    final verificationId = _identityBuilder.buildVerificationIdFromResult(
      provisional.copyWith(fingerprint: fingerprint),
    );

    return provisional.copyWith(
      verificationId: verificationId,
      fingerprint: fingerprint,
    );
  }

  ReleaseVerificationCheck _fingerprintCheck(ReleaseEvidenceBundle bundle) {
    final computed = _serializer.bundleFingerprint(bundle);
    final matches = computed == bundle.fingerprint;
    return ReleaseVerificationCheck(
      checkId: 'fingerprint',
      checkType: ReleaseVerificationCheckType.fingerprint,
      subjectId: bundle.subject.subjectId,
      expected: bundle.fingerprint,
      actual: computed,
      status: matches
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation: matches
          ? 'Bundle fingerprint matches canonical serialization'
          : 'Bundle fingerprint mismatch',
      fingerprint: computed,
    );
  }

  ReleaseVerificationCheck _identityCheck(ReleaseEvidenceBundle bundle) {
    final hasId = bundle.metadata.bundleId.isNotEmpty;
    return ReleaseVerificationCheck(
      checkId: 'identity',
      checkType: ReleaseVerificationCheckType.identity,
      subjectId: bundle.subject.subjectId,
      expected: 'non-empty bundleId',
      actual: bundle.metadata.bundleId,
      status: hasId
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation:
          hasId ? 'Bundle identity present' : 'Bundle identity missing',
    );
  }

  ReleaseVerificationCheck _projectCheck(
    ReleaseEvidenceBundle bundle,
    ReleaseVerificationPolicy policy,
  ) {
    if (!policy.requireProjectConsistency) {
      return ReleaseVerificationCheck(
        checkId: 'project',
        checkType: ReleaseVerificationCheckType.projectConsistency,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'Project consistency not required by policy',
      );
    }
    final consistent = bundle.metadata.projectId == bundle.subject.projectId &&
        bundle.releaseContextReference.projectId == bundle.metadata.projectId;
    return ReleaseVerificationCheck(
      checkId: 'project',
      checkType: ReleaseVerificationCheckType.projectConsistency,
      subjectId: bundle.subject.subjectId,
      expected: bundle.metadata.projectId,
      actual: bundle.subject.projectId,
      status: consistent
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation: consistent
          ? 'Project identifiers are consistent'
          : 'Project identifier mismatch',
    );
  }

  ReleaseVerificationCheck _commitCheck(
    ReleaseEvidenceBundle bundle,
    ReleaseVerificationPolicy policy,
  ) {
    if (!policy.requireCommitConsistency) {
      return ReleaseVerificationCheck(
        checkId: 'commit',
        checkType: ReleaseVerificationCheckType.commitConsistency,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'Commit consistency not required by policy',
      );
    }
    final consistent = bundle.metadata.commitId == bundle.subject.commitId &&
        bundle.releaseContextReference.commitId == bundle.metadata.commitId;
    return ReleaseVerificationCheck(
      checkId: 'commit',
      checkType: ReleaseVerificationCheckType.commitConsistency,
      subjectId: bundle.subject.subjectId,
      expected: bundle.metadata.commitId,
      actual: bundle.subject.commitId,
      status: consistent
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation: consistent
          ? 'Commit identifiers are consistent'
          : 'Commit identifier mismatch',
    );
  }

  ReleaseVerificationCheck _compatibilityCheck(ReleaseEvidenceBundle bundle) {
    final status = bundle.compatibility.status;
    return ReleaseVerificationCheck(
      checkId: 'compatibility',
      checkType: ReleaseVerificationCheckType.policy,
      subjectId: bundle.subject.subjectId,
      expected: ReleaseEvidenceCompatibilityStatus.compatible.wireName,
      actual: status.wireName,
      status: status == ReleaseEvidenceCompatibilityStatus.compatible
          ? ReleaseVerificationCheckStatus.passed
          : status == ReleaseEvidenceCompatibilityStatus.partiallyCompatible
              ? ReleaseVerificationCheckStatus.unavailable
              : ReleaseVerificationCheckStatus.failed,
      explanation: 'Bundle compatibility status: ${status.wireName}',
    );
  }

  ReleaseVerificationCheck _provenanceCheck(
    ReleaseEvidenceBundle bundle,
    ReleaseVerificationPolicy policy,
  ) {
    if (!policy.requireProvenance) {
      return ReleaseVerificationCheck(
        checkId: 'provenance',
        checkType: ReleaseVerificationCheckType.provenance,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'Provenance not required by policy',
      );
    }
    final present = bundle.provenance.isNotEmpty;
    return ReleaseVerificationCheck(
      checkId: 'provenance',
      checkType: ReleaseVerificationCheckType.provenance,
      subjectId: bundle.subject.subjectId,
      status: present
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation: present
          ? 'Provenance records present'
          : 'Provenance required but absent',
    );
  }

  ReleaseVerificationCheck _issuerCheck(ReleaseEvidenceBundle bundle) {
    if (bundle.attestations.isEmpty) {
      return ReleaseVerificationCheck(
        checkId: 'issuer',
        checkType: ReleaseVerificationCheckType.issuer,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'No attestations to evaluate issuer',
      );
    }
    final allValid = bundle.attestations.every(
      (a) => a.issuer.issuerId.isNotEmpty,
    );
    return ReleaseVerificationCheck(
      checkId: 'issuer',
      checkType: ReleaseVerificationCheckType.issuer,
      subjectId: bundle.subject.subjectId,
      status: allValid
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      attestationIds:
          bundle.attestations.map((a) => a.metadata.attestationId).toList(),
      explanation: allValid
          ? 'All attestation issuers structurally valid'
          : 'Invalid attestation issuer detected',
    );
  }

  ReleaseVerificationCheck _authorityCheck(ReleaseEvidenceBundle bundle) {
    if (bundle.attestations.isEmpty) {
      return ReleaseVerificationCheck(
        checkId: 'authority',
        checkType: ReleaseVerificationCheckType.authority,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'No attestations to evaluate authority',
      );
    }
    final allValid = bundle.attestations.every(
      (a) =>
          a.authority.authorityId.isNotEmpty &&
          a.authority.status == ReleaseAttestationAuthorityStatus.active,
    );
    return ReleaseVerificationCheck(
      checkId: 'authority',
      checkType: ReleaseVerificationCheckType.authority,
      subjectId: bundle.subject.subjectId,
      status: allValid
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      attestationIds:
          bundle.attestations.map((a) => a.metadata.attestationId).toList(),
      explanation: allValid
          ? 'All attestation authorities structurally valid'
          : 'Invalid attestation authority detected',
    );
  }

  ReleaseVerificationCheck _signatureReferenceCheck(
    ReleaseEvidenceBundle bundle,
    ReleaseVerificationPolicy policy,
  ) {
    if (!policy.requireSignature) {
      return ReleaseVerificationCheck(
        checkId: 'signature',
        checkType: ReleaseVerificationCheckType.signature,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.skipped,
        explanation: 'Signature not required by policy',
      );
    }
    final withSignature =
        bundle.attestations.where((a) => a.signatureReference != null).toList();
    if (withSignature.isEmpty) {
      return ReleaseVerificationCheck(
        checkId: 'signature',
        checkType: ReleaseVerificationCheckType.signature,
        subjectId: bundle.subject.subjectId,
        status: ReleaseVerificationCheckStatus.failed,
        explanation: 'Signature required but no signature references present',
      );
    }
    final structurallyValid = withSignature.every(
      (a) => a.signatureReference!.signatureId.isNotEmpty,
    );
    return ReleaseVerificationCheck(
      checkId: 'signature',
      checkType: ReleaseVerificationCheckType.signature,
      subjectId: bundle.subject.subjectId,
      status: structurallyValid
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation: 'Signature references structurally validated (not crypto)',
      limitations: const ['no cryptographic verification'],
    );
  }

  ReleaseVerificationCheck _coverageCheck(
    ReleaseEvidenceBundle bundle,
    ReleaseVerificationPolicy policy,
  ) {
    final evidenceOk = bundle.coverage.evidenceCoveragePercentage >=
        policy.minimumEvidenceCoverage;
    final attestationOk = bundle.coverage.attestationCoveragePercentage >=
        policy.minimumAttestationCoverage;
    final passed = evidenceOk && attestationOk;
    return ReleaseVerificationCheck(
      checkId: 'coverage',
      checkType: ReleaseVerificationCheckType.coverage,
      subjectId: bundle.subject.subjectId,
      expected:
          'evidence>=${policy.minimumEvidenceCoverage},attestation>=${policy.minimumAttestationCoverage}',
      actual:
          'evidence=${bundle.coverage.evidenceCoveragePercentage},attestation=${bundle.coverage.attestationCoveragePercentage}',
      status: passed
          ? ReleaseVerificationCheckStatus.passed
          : ReleaseVerificationCheckStatus.failed,
      explanation:
          passed ? 'Coverage thresholds met' : 'Coverage below policy minimums',
    );
  }

  ReleaseVerificationStatus _deriveStatus({
    required int failedChecks,
    required int unavailableChecks,
    required bool allowPartial,
  }) {
    if (failedChecks > 0) return ReleaseVerificationStatus.invalid;
    if (unavailableChecks > 0) {
      return allowPartial
          ? ReleaseVerificationStatus.partiallyVerified
          : ReleaseVerificationStatus.unverified;
    }
    return ReleaseVerificationStatus.verified;
  }

  List<ReleaseEvidenceExplanation> _buildExplanations(
    ReleaseVerificationStatus status,
    List<ReleaseVerificationCheck> checks,
  ) {
    final type = switch (status) {
      ReleaseVerificationStatus.verified =>
        ReleaseEvidenceExplanationType.verificationPassed,
      ReleaseVerificationStatus.partiallyVerified =>
        ReleaseEvidenceExplanationType.verificationPartial,
      ReleaseVerificationStatus.invalid =>
        ReleaseEvidenceExplanationType.verificationFailed,
      ReleaseVerificationStatus.unverified =>
        ReleaseEvidenceExplanationType.verificationUnavailable,
      ReleaseVerificationStatus.incompatible =>
        ReleaseEvidenceExplanationType.verificationIncompatible,
      ReleaseVerificationStatus.unavailable =>
        ReleaseEvidenceExplanationType.verificationUnavailable,
      ReleaseVerificationStatus.expired =>
        ReleaseEvidenceExplanationType.verificationExpired,
      ReleaseVerificationStatus.error =>
        ReleaseEvidenceExplanationType.verificationError,
    };
    return [
      ReleaseEvidenceExplanation(
        explanationId: 'verification-${status.wireName}',
        type: type,
        summary: 'Verification status: ${status.wireName}',
        detail:
            checks.map((c) => '${c.checkId}:${c.status.wireName}').join(', '),
        templateId: 'verification-summary',
        verificationExplanation: status.wireName,
      ),
    ];
  }
}

extension on ReleaseVerificationResult {
  ReleaseVerificationResult copyWith({
    String? verificationId,
    ReleaseEvidenceSubject? subject,
    ReleaseVerificationPolicyReference? policyReference,
    ReleaseVerificationStatus? status,
    List<ReleaseVerificationCheck>? checks,
    ReleaseEvidenceCompatibility? compatibility,
    ReleaseEvidenceEligibility? eligibility,
    ReleaseEvidenceCoverage? coverage,
    List<String>? verifiedEvidenceIds,
    List<String>? rejectedEvidenceIds,
    List<String>? verifiedAttestationIds,
    List<String>? rejectedAttestationIds,
    List<ReleaseEvidenceExplanation>? explanations,
    List<ReleaseEvidenceWarning>? warnings,
    List<ReleaseEvidenceError>? errors,
    List<ReleaseEvidenceLimitation>? limitations,
    String? evaluatedAt,
    String? referenceTime,
    String? fingerprint,
    int? schemaVersion,
  }) {
    return ReleaseVerificationResult(
      verificationId: verificationId ?? this.verificationId,
      subject: subject ?? this.subject,
      policyReference: policyReference ?? this.policyReference,
      status: status ?? this.status,
      checks: checks ?? this.checks,
      compatibility: compatibility ?? this.compatibility,
      eligibility: eligibility ?? this.eligibility,
      coverage: coverage ?? this.coverage,
      verifiedEvidenceIds: verifiedEvidenceIds ?? this.verifiedEvidenceIds,
      rejectedEvidenceIds: rejectedEvidenceIds ?? this.rejectedEvidenceIds,
      verifiedAttestationIds:
          verifiedAttestationIds ?? this.verifiedAttestationIds,
      rejectedAttestationIds:
          rejectedAttestationIds ?? this.rejectedAttestationIds,
      explanations: explanations ?? this.explanations,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      limitations: limitations ?? this.limitations,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      referenceTime: referenceTime ?? this.referenceTime,
      fingerprint: fingerprint ?? this.fingerprint,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }
}
