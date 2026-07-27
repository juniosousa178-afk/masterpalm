import '../models/release_evidence/release_attestation.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import 'release_attestation_validator.dart';

/// Structural evaluation result for a single attestation.
class ReleaseAttestationEvaluation {
  const ReleaseAttestationEvaluation({
    required this.attestationId,
    required this.structurallyValid,
    required this.status,
    required this.predicateResult,
    required this.issuerValid,
    required this.authorityValid,
    required this.expirationValid,
    required this.evidenceRefsValid,
    required this.provenanceRefsValid,
    required this.signatureRefValid,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final String attestationId;
  final bool structurallyValid;
  final ReleaseAttestationStatus status;
  final ReleaseAttestationPredicateResult predicateResult;
  final bool issuerValid;
  final bool authorityValid;
  final bool expirationValid;
  final bool evidenceRefsValid;
  final bool provenanceRefsValid;
  final bool signatureRefValid;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;
}

/// Evaluates attestations structurally without cryptographic verification.
class ReleaseEvidenceAttestationEngine {
  ReleaseEvidenceAttestationEngine({
    ReleaseAttestationValidator? validator,
  }) : _validator = validator ?? const ReleaseAttestationValidator();

  final ReleaseAttestationValidator _validator;

  ReleaseAttestationEvaluation evaluate({
    required ReleaseAttestation attestation,
    ReleaseAttestationPolicy? policy,
    ReleaseEvidenceBundle? bundle,
    String? referenceTime,
    String? expectedProjectId,
    String? expectedReleaseId,
    String? expectedCommitId,
  }) {
    final warnings = <ReleaseEvidenceWarning>[];
    final errors = <ReleaseEvidenceError>[];
    final limitations = <ReleaseEvidenceLimitation>[
      const ReleaseEvidenceLimitation(
        limitationId: 'no-crypto-attestation',
        code: ReleaseEvidenceLimitationCode.noCryptographicVerification,
        description: 'Attestation evaluation is structural only',
        impact: 'Signatures are not cryptographically verified',
        resolvable: false,
      ),
    ];

    final validation = _validator.validate(
      attestation,
      policy: policy,
      referenceTime: referenceTime,
      expectedProjectId: expectedProjectId,
      expectedReleaseId: expectedReleaseId,
      expectedCommitId: expectedCommitId,
      releaseGovernanceDecision: null,
    );

    if (!validation.isValid) {
      for (final issue in validation.issues) {
        errors.add(
          ReleaseEvidenceError(
            errorId: 'att-${attestation.metadata.attestationId}-${issue.code}',
            code: ReleaseEvidenceErrorCode.invalidAttestation,
            message: issue.message,
            recoverable: false,
            classification: 'structural',
            attestationId: attestation.metadata.attestationId,
          ),
        );
      }
    }

    final issuerValid = _evaluateIssuer(attestation, policy, warnings);
    final authorityValid = _evaluateAuthority(attestation, policy, warnings);
    final expirationValid =
        _evaluateExpiration(attestation, referenceTime, warnings);
    final evidenceRefsValid =
        _evaluateEvidenceRefs(attestation, bundle, warnings);
    final provenanceRefsValid = _evaluateProvenanceRefs(attestation, warnings);
    final signatureRefValid = _evaluateSignatureRef(attestation, warnings);

    final predicateResult = attestation.predicate.result;
    final structurallyValid = validation.isValid &&
        issuerValid &&
        authorityValid &&
        expirationValid &&
        evidenceRefsValid &&
        provenanceRefsValid &&
        signatureRefValid &&
        predicateResult != ReleaseAttestationPredicateResult.invalid &&
        predicateResult != ReleaseAttestationPredicateResult.error;

    if (attestation.signatureReference != null &&
        attestation.signatureReference!.verificationStatus ==
            ReleaseSignatureVerificationStatus.unverified) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId: 'sig-unverified-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.signatureUnverified,
          message: 'Signature reference is present but unverified',
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          attestationId: attestation.metadata.attestationId,
        ),
      );
    }

    return ReleaseAttestationEvaluation(
      attestationId: attestation.metadata.attestationId,
      structurallyValid: structurallyValid,
      status: attestation.status,
      predicateResult: predicateResult,
      issuerValid: issuerValid,
      authorityValid: authorityValid,
      expirationValid: expirationValid,
      evidenceRefsValid: evidenceRefsValid,
      provenanceRefsValid: provenanceRefsValid,
      signatureRefValid: signatureRefValid,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
    );
  }

  List<ReleaseAttestationEvaluation> evaluateAll({
    required List<ReleaseAttestation> attestations,
    ReleaseAttestationPolicy? policy,
    ReleaseEvidenceBundle? bundle,
    String? referenceTime,
    String? expectedProjectId,
    String? expectedReleaseId,
    String? expectedCommitId,
  }) {
    final sorted = List<ReleaseAttestation>.from(attestations)
      ..sort(
        (a, b) => a.metadata.attestationId.compareTo(b.metadata.attestationId),
      );
    return sorted
        .map(
          (attestation) => evaluate(
            attestation: attestation,
            policy: policy,
            bundle: bundle,
            referenceTime: referenceTime,
            expectedProjectId: expectedProjectId,
            expectedReleaseId: expectedReleaseId,
            expectedCommitId: expectedCommitId,
          ),
        )
        .toList();
  }

  bool _evaluateIssuer(
    ReleaseAttestation attestation,
    ReleaseAttestationPolicy? policy,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    if (attestation.issuer.issuerId.isEmpty) return false;
    if (attestation.issuer.identityStatus == ReleaseIdentityStatus.unverified) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId: 'issuer-unverified-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.issuerUnverified,
          message: 'Issuer identity is unverified',
          severity: ReleaseEvidenceCollectionRuleSeverity.advisory,
          attestationId: attestation.metadata.attestationId,
        ),
      );
      return policy?.issuerRequirements.allowUnverifiedIssuer ?? false;
    }
    if (policy != null &&
        policy.issuerRequirements.allowedIssuerIds.isNotEmpty &&
        !policy.issuerRequirements.allowedIssuerIds
            .contains(attestation.issuer.issuerId)) {
      return false;
    }
    return true;
  }

  bool _evaluateAuthority(
    ReleaseAttestation attestation,
    ReleaseAttestationPolicy? policy,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    if (attestation.authority.authorityId.isEmpty) return false;
    if (attestation.authority.status !=
            ReleaseAttestationAuthorityStatus.active &&
        attestation.authority.status !=
            ReleaseAttestationAuthorityStatus.unverified) {
      return false;
    }
    if (attestation.authority.status ==
        ReleaseAttestationAuthorityStatus.unverified) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId:
              'authority-unverified-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.authorityUnverified,
          message: 'Authority is unverified',
          severity: ReleaseEvidenceCollectionRuleSeverity.advisory,
          attestationId: attestation.metadata.attestationId,
        ),
      );
    }
    if (policy != null &&
        !policy.supportedAttestationTypes
            .contains(attestation.metadata.attestationType)) {
      return false;
    }
    return true;
  }

  bool _evaluateExpiration(
    ReleaseAttestation attestation,
    String? referenceTime,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    if (referenceTime == null || attestation.expiresAt == null) {
      return true;
    }
    if (attestation.expiresAt!.compareTo(referenceTime) <= 0) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId: 'att-expired-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.attestationNearExpiration,
          message: 'Attestation is expired at reference time',
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          attestationId: attestation.metadata.attestationId,
        ),
      );
      return false;
    }
    return true;
  }

  bool _evaluateEvidenceRefs(
    ReleaseAttestation attestation,
    ReleaseEvidenceBundle? bundle,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    if (attestation.evidenceReferences.isEmpty) return true;
    if (bundle == null) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId: 'ev-ref-no-bundle-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.externalEvidenceUnverified,
          message: 'Evidence references cannot be cross-checked without bundle',
          severity: ReleaseEvidenceCollectionRuleSeverity.advisory,
          attestationId: attestation.metadata.attestationId,
        ),
      );
      return false;
    }
    final bundleArtifactIds =
        bundle.evidence.map((e) => e.artifactReference.artifactId).toSet();
    for (final ref in attestation.evidenceReferences) {
      if (!bundleArtifactIds.contains(ref.artifactId)) {
        return false;
      }
    }
    return true;
  }

  bool _evaluateProvenanceRefs(
    ReleaseAttestation attestation,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    if (attestation.provenanceReferences.isEmpty) return true;
    for (final ref in attestation.provenanceReferences) {
      if (ref.isEmpty) return false;
    }
    return true;
  }

  bool _evaluateSignatureRef(
    ReleaseAttestation attestation,
    List<ReleaseEvidenceWarning> warnings,
  ) {
    final signature = attestation.signatureReference;
    if (signature == null) return true;
    if (signature.verificationStatus ==
        ReleaseSignatureVerificationStatus.invalid) {
      return false;
    }
    if (signature.verificationStatus ==
            ReleaseSignatureVerificationStatus.unverified ||
        signature.verificationStatus ==
            ReleaseSignatureVerificationStatus.unknown) {
      warnings.add(
        ReleaseEvidenceWarning(
          warningId: 'sig-ref-${attestation.metadata.attestationId}',
          code: ReleaseEvidenceWarningCode.signatureUnverified,
          message: 'Signature reference not verified',
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          attestationId: attestation.metadata.attestationId,
        ),
      );
    }
    return signature.signatureId.isNotEmpty;
  }
}
