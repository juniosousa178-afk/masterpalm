import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_attestation_validator.dart';
import 'cryptographic_revocation_validator.dart';
import 'cryptographic_signature_envelope_validator.dart';
import 'cryptographic_trust_anchor_validator.dart';
import 'cryptographic_trust_policy_validator.dart';
import 'cryptographic_transparency_log_reference_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicVerificationRequest].
class CryptographicVerificationRequestValidator {
  const CryptographicVerificationRequestValidator({
    CryptographicSignatureEnvelopeValidator? signatureEnvelopeValidator,
    CryptographicAttestationValidator? attestationValidator,
    CryptographicTrustPolicyValidator? trustPolicyValidator,
    CryptographicTrustAnchorValidator? trustAnchorValidator,
    CryptographicRevocationValidator? revocationValidator,
    CryptographicTransparencyLogReferenceValidator?
        transparencyLogReferenceValidator,
  })  : _signatureEnvelopeValidator = signatureEnvelopeValidator ??
            const CryptographicSignatureEnvelopeValidator(),
        _attestationValidator =
            attestationValidator ?? const CryptographicAttestationValidator(),
        _trustPolicyValidator =
            trustPolicyValidator ?? const CryptographicTrustPolicyValidator(),
        _trustAnchorValidator =
            trustAnchorValidator ?? const CryptographicTrustAnchorValidator(),
        _revocationValidator =
            revocationValidator ?? const CryptographicRevocationValidator(),
        _transparencyLogReferenceValidator =
            transparencyLogReferenceValidator ??
                const CryptographicTransparencyLogReferenceValidator();

  final CryptographicSignatureEnvelopeValidator _signatureEnvelopeValidator;
  final CryptographicAttestationValidator _attestationValidator;
  final CryptographicTrustPolicyValidator _trustPolicyValidator;
  final CryptographicTrustAnchorValidator _trustAnchorValidator;
  final CryptographicRevocationValidator _revocationValidator;
  final CryptographicTransparencyLogReferenceValidator
      _transparencyLogReferenceValidator;

  CryptographicValidationResult validate(
    CryptographicVerificationRequest request,
  ) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(CryptographicValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

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

    if (request.requestId.isEmpty) {
      addError('CT_VERIFY_REQUEST_ID', 'requestId', 'requestId is required');
    }
    if (request.projectId.isEmpty) {
      addError(
        'CT_VERIFY_REQUEST_PROJECT',
        'projectId',
        'projectId is required',
      );
    }
    if (request.requestedAt.isEmpty) {
      addError(
        'CT_VERIFY_REQUEST_REQUESTED_AT',
        'requestedAt',
        'requestedAt is required',
      );
    }
    if (request.subjects.isEmpty) {
      addError(
        'CT_VERIFY_REQUEST_SUBJECTS',
        'subjects',
        'at least one subject is required',
      );
    }

    final subjectRefs = <String, _SubjectRefSnapshot>{};
    for (final subject in request.subjects) {
      if (subject.subjectId.isEmpty) {
        addError(
          'CT_VERIFY_REQUEST_SUBJECT_ID',
          'subjects',
          'subjectId is required',
        );
        continue;
      }
      if (subject.projectId != request.projectId) {
        addError(
          'CT_VERIFY_REQUEST_PROJECT_MISMATCH',
          'subjects.${subject.subjectId}.projectId',
          'subject projectId must match request projectId',
          relatedId: subject.subjectId,
        );
      }
      _trackIncompatibleRef(
        refs: subjectRefs,
        id: subject.subjectId,
        snapshot: _SubjectRefSnapshot(
          subjectType: subject.subjectType,
          sourceFingerprint: subject.sourceFingerprint,
        ),
        path: 'subjects',
        code: 'CT_VERIFY_REQUEST_INCOMPATIBLE_REF',
        addError: addError,
      );
    }

    final signatureIds = <String>{};
    for (final signature in request.signatures) {
      if (!signatureIds.add(signature.signatureId)) {
        addError(
          'CT_VERIFY_REQUEST_DUPLICATE_SIGNATURE',
          'signatures',
          'duplicate signatureId: ${signature.signatureId}',
          relatedId: signature.signatureId,
        );
      }
      merge(_signatureEnvelopeValidator.validate(signature));
    }

    final attestationIds = <String>{};
    for (final attestation in request.attestations) {
      if (!attestationIds.add(attestation.attestationId)) {
        addError(
          'CT_VERIFY_REQUEST_DUPLICATE_ATTESTATION',
          'attestations',
          'duplicate attestationId: ${attestation.attestationId}',
          relatedId: attestation.attestationId,
        );
      }
      merge(_attestationValidator.validate(attestation));
    }

    if (request.policy != null) {
      merge(_trustPolicyValidator.validate(request.policy!));
    }

    final anchorRefs = <String, _AnchorRefSnapshot>{};
    for (final anchor in request.trustAnchors) {
      _trackIncompatibleAnchorRef(
        refs: anchorRefs,
        id: anchor.trustAnchorId,
        snapshot: _AnchorRefSnapshot(
          keyFingerprint: anchor.keyReference.publicKeyFingerprint,
        ),
        path: 'trustAnchors',
        code: 'CT_VERIFY_REQUEST_INCOMPATIBLE_REF',
        addError: addError,
      );
      merge(_trustAnchorValidator.validate(anchor));
    }

    final revocationIds = <String>{};
    for (final revocation in request.revocations) {
      if (!revocationIds.add(revocation.revocationId)) {
        addError(
          'CT_VERIFY_REQUEST_DUPLICATE_REVOCATION',
          'revocations',
          'duplicate revocationId: ${revocation.revocationId}',
          relatedId: revocation.revocationId,
        );
      }
      merge(_revocationValidator.validate(revocation));
    }

    final logEntryIds = <String>{};
    for (final logReference in request.transparencyLogReferences) {
      if (!logEntryIds.add(logReference.entryId)) {
        addError(
          'CT_VERIFY_REQUEST_DUPLICATE_LOG_ENTRY',
          'transparencyLogReferences',
          'duplicate entryId: ${logReference.entryId}',
          relatedId: logReference.entryId,
        );
      }
      merge(_transparencyLogReferenceValidator.validate(logReference));
    }

    validateSensitiveMetadata(
      request.metadata,
      'metadata',
      addError,
      code: 'CT_VERIFY_REQUEST_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

class _SubjectRefSnapshot {
  const _SubjectRefSnapshot({
    required this.subjectType,
    required this.sourceFingerprint,
  });

  final CryptographicTrustSubjectType subjectType;
  final String sourceFingerprint;
}

class _AnchorRefSnapshot {
  const _AnchorRefSnapshot({required this.keyFingerprint});

  final String keyFingerprint;
}

void _trackIncompatibleRef({
  required Map<String, _SubjectRefSnapshot> refs,
  required String id,
  required _SubjectRefSnapshot snapshot,
  required String path,
  required String code,
  required CryptographicValidationAddError addError,
}) {
  final existing = refs[id];
  if (existing == null) {
    refs[id] = snapshot;
    return;
  }
  if (existing.subjectType != snapshot.subjectType ||
      existing.sourceFingerprint != snapshot.sourceFingerprint) {
    addError(
      code,
      path,
      'incompatible duplicate reference for id: $id',
      relatedId: id,
    );
  }
}

void _trackIncompatibleAnchorRef({
  required Map<String, _AnchorRefSnapshot> refs,
  required String id,
  required _AnchorRefSnapshot snapshot,
  required String path,
  required String code,
  required CryptographicValidationAddError addError,
}) {
  final existing = refs[id];
  if (existing == null) {
    refs[id] = snapshot;
    return;
  }
  if (existing.keyFingerprint != snapshot.keyFingerprint) {
    addError(
      code,
      path,
      'incompatible duplicate reference for id: $id',
      relatedId: id,
    );
  }
}
