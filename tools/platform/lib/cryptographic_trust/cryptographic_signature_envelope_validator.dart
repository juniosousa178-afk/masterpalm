import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_digest_validator.dart';
import 'cryptographic_key_reference_validator.dart';
import 'cryptographic_trust_anchor_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicSignatureEnvelope].
class CryptographicSignatureEnvelopeValidator {
  const CryptographicSignatureEnvelopeValidator({
    CryptographicDigestValidator? digestValidator,
    CryptographicKeyReferenceValidator? keyReferenceValidator,
    CryptographicTrustAnchorValidator? trustAnchorValidator,
  })  : _digestValidator =
            digestValidator ?? const CryptographicDigestValidator(),
        _keyReferenceValidator =
            keyReferenceValidator ?? const CryptographicKeyReferenceValidator(),
        _trustAnchorValidator =
            trustAnchorValidator ?? const CryptographicTrustAnchorValidator();

  final CryptographicDigestValidator _digestValidator;
  final CryptographicKeyReferenceValidator _keyReferenceValidator;
  final CryptographicTrustAnchorValidator _trustAnchorValidator;

  CryptographicValidationResult validate(
    CryptographicSignatureEnvelope envelope,
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

    if (envelope.signatureId.isEmpty) {
      addError('CT_SIG_ID', 'signatureId', 'signatureId is required');
    }
    if (envelope.subject.subjectId.isEmpty) {
      addError('CT_SIG_SUBJECT', 'subject.subjectId', 'subject is required');
    }
    if (envelope.subjectDigest.subjectId != envelope.subject.subjectId) {
      addError(
        'CT_SIG_SUBJECT_DIGEST_MISMATCH',
        'subjectDigest.subjectId',
        'subjectDigest.subjectId must match subject.subjectId',
        relatedId: envelope.signatureId,
      );
    }
    if (envelope.signatureValue.isEmpty) {
      addError(
        'CT_SIG_VALUE',
        'signatureValue',
        'signatureValue must not be empty',
        relatedId: envelope.signatureId,
      );
    }
    if (envelope.signatureEncoding.isEmpty) {
      addError(
        'CT_SIG_ENCODING',
        'signatureEncoding',
        'signatureEncoding must not be empty',
        relatedId: envelope.signatureId,
      );
    }
    if (envelope.keyReference.keyId.isEmpty) {
      addError(
        'CT_SIG_KEY_REFERENCE',
        'keyReference',
        'keyReference is required',
        relatedId: envelope.signatureId,
      );
    }
    if (!isIsoDateRangeCoherent(envelope.signedAt, envelope.expiresAt)) {
      addError(
        'CT_SIG_EXPIRES_AT',
        'expiresAt',
        'expiresAt must be >= signedAt',
        relatedId: envelope.signatureId,
      );
    }
    if (envelope.signatureDescriptor.algorithmId.isEmpty) {
      addError(
        'CT_SIG_DESCRIPTOR_ALGORITHM_ID',
        'signatureDescriptor.algorithmId',
        'signatureDescriptor.algorithmId is required',
        relatedId: envelope.signatureId,
      );
    }

    merge(_digestValidator.validate(envelope.subjectDigest));
    merge(_keyReferenceValidator.validate(envelope.keyReference));
    if (envelope.trustAnchorReference != null) {
      merge(_trustAnchorValidator.validate(envelope.trustAnchorReference!));
    }

    validateSensitiveMetadata(
      envelope.metadata,
      'metadata',
      addError,
      code: 'CT_SIG_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
