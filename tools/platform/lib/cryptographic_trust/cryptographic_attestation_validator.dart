import '../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_signer_identity_validator.dart';
import 'cryptographic_signature_envelope_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicAttestationStatement].
class CryptographicAttestationValidator {
  const CryptographicAttestationValidator({
    CryptographicSignerIdentityValidator? signerIdentityValidator,
    CryptographicSignatureEnvelopeValidator? signatureEnvelopeValidator,
  })  : _signerIdentityValidator = signerIdentityValidator ??
            const CryptographicSignerIdentityValidator(),
        _signatureEnvelopeValidator = signatureEnvelopeValidator ??
            const CryptographicSignatureEnvelopeValidator();

  final CryptographicSignerIdentityValidator _signerIdentityValidator;
  final CryptographicSignatureEnvelopeValidator _signatureEnvelopeValidator;

  CryptographicValidationResult validate(
    CryptographicAttestationStatement attestation,
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

    if (attestation.attestationId.isEmpty) {
      addError(
        'CT_ATTESTATION_ID',
        'attestationId',
        'attestationId is required',
      );
    }
    if (attestation.subjects.isEmpty) {
      addError(
        'CT_ATTESTATION_SUBJECTS',
        'subjects',
        'subjects must not be empty',
      );
    }
    if (attestation.schemaVersion < 1) {
      addError(
        'CT_ATTESTATION_SCHEMA_VERSION',
        'schemaVersion',
        'schemaVersion must be >= 1',
      );
    }
    if (attestation.predicate.predicateType.isEmpty) {
      addError(
        'CT_ATTESTATION_PREDICATE_TYPE',
        'predicate.predicateType',
        'predicateType is required',
      );
    }
    if (attestation.predicate.schemaVersion < 1) {
      addError(
        'CT_ATTESTATION_PREDICATE_SCHEMA_VERSION',
        'predicate.schemaVersion',
        'predicate.schemaVersion must be >= 1',
      );
    }
    if (attestation.issuerIdentity.identityId.isEmpty) {
      addError(
        'CT_ATTESTATION_ISSUER',
        'issuerIdentity',
        'issuerIdentity is required',
      );
    }
    if (!isIsoDateRangeCoherent(attestation.issuedAt, attestation.expiresAt)) {
      addError(
        'CT_ATTESTATION_EXPIRES_AT',
        'expiresAt',
        'expiresAt must be >= issuedAt',
        relatedId: attestation.attestationId,
      );
    }

    final subjectIds = <String>{};
    for (final subject in attestation.subjects) {
      if (subject.subjectId.isEmpty) {
        addError(
          'CT_ATTESTATION_SUBJECT_ID',
          'subjects',
          'subjectId is required',
        );
        continue;
      }
      if (!subjectIds.add(subject.subjectId)) {
        addError(
          'CT_ATTESTATION_DUPLICATE_SUBJECT',
          'subjects',
          'duplicate subjectId: ${subject.subjectId}',
          relatedId: subject.subjectId,
        );
      }
      if (subject.subjectFingerprint.isEmpty) {
        addError(
          'CT_ATTESTATION_SUBJECT_FINGERPRINT',
          'subjects.${subject.subjectId}.subjectFingerprint',
          'subjectFingerprint is required',
          relatedId: subject.subjectId,
        );
      }
      if (subject.projectId.isEmpty) {
        addError(
          'CT_ATTESTATION_SUBJECT_PROJECT',
          'subjects.${subject.subjectId}.projectId',
          'projectId is required',
          relatedId: subject.subjectId,
        );
      }
    }

    final signatureIds = <String>{};
    for (final signature in attestation.signatures) {
      if (!signatureIds.add(signature.signatureId)) {
        addError(
          'CT_ATTESTATION_DUPLICATE_SIGNATURE',
          'signatures',
          'duplicate signatureId: ${signature.signatureId}',
          relatedId: signature.signatureId,
        );
      }
      merge(_signatureEnvelopeValidator.validate(signature));
    }

    merge(_signerIdentityValidator.validate(attestation.issuerIdentity));

    if (attestation.status == CryptographicAttestationStatus.revoked ||
        attestation.status == CryptographicAttestationStatus.invalid) {
      addWarning(
        'CT_ATTESTATION_STATUS',
        'status',
        'attestation status is ${attestation.status.wireName}',
        relatedId: attestation.attestationId,
      );
    }

    validateSensitiveMetadata(
      attestation.metadata,
      'metadata',
      addError,
      code: 'CT_ATTESTATION_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
