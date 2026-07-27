import '../models/cryptographic_trust/cryptographic_revocation_record.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_algorithm_registry.dart';
import 'cryptographic_revocation_evaluator.dart';
import 'cryptographic_signature_envelope_validator.dart';
import 'interfaces/cryptographic_public_key_resolver.dart';

/// Result of signature verification — math validity does not elevate trust level.
class CryptographicSignatureVerificationServiceResult {
  const CryptographicSignatureVerificationServiceResult({
    required this.outcome,
    required this.trustLevel,
    this.issues = const [],
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Verifies signature envelopes using registered verifiers and public keys.
///
/// Cryptographic validity does not authorize release or elevate trust level.
class CryptographicSignatureVerificationService {
  CryptographicSignatureVerificationService({
    required CryptographicAlgorithmRegistry algorithmRegistry,
    CryptographicPublicKeyResolver? publicKeyResolver,
    CryptographicRevocationEvaluator? revocationEvaluator,
    CryptographicSignatureEnvelopeValidator? envelopeValidator,
  })  : _algorithmRegistry = algorithmRegistry,
        _publicKeyResolver = publicKeyResolver,
        _revocationEvaluator =
            revocationEvaluator ?? const CryptographicRevocationEvaluator(),
        _envelopeValidator = envelopeValidator ??
            const CryptographicSignatureEnvelopeValidator();

  final CryptographicAlgorithmRegistry _algorithmRegistry;
  final CryptographicPublicKeyResolver? _publicKeyResolver;
  final CryptographicRevocationEvaluator _revocationEvaluator;
  final CryptographicSignatureEnvelopeValidator _envelopeValidator;

  Future<CryptographicSignatureVerificationServiceResult> verifySignature({
    required List<int> subjectBytes,
    required CryptographicSignatureEnvelope envelope,
    List<CryptographicRevocationRecord> revocations = const [],
    String? referenceTime,
  }) async {
    final structural = _envelopeValidator.validate(envelope);
    if (!structural.isValid) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.malformed,
        trustLevel: CryptographicTrustLevel.none,
        message: 'signature envelope structurally invalid',
        issues: structural.issues
            .map(
              (issue) => CryptographicVerificationIssue(
                code: issue.code,
                severity: issue.severity,
                path: issue.path,
                message: issue.message,
                signatureId: envelope.signatureId,
                subjectId: envelope.subject.subjectId,
              ),
            )
            .toList(),
      );
    }

    if (subjectBytes.isEmpty) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.malformed,
        trustLevel: CryptographicTrustLevel.none,
        message: 'subject bytes required for verification',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIG_EMPTY_PAYLOAD',
            severity: CryptographicIssueSeverity.error,
            path: 'subjectBytes',
            message: 'Signature verification requires explicit payload bytes',
            signatureId: envelope.signatureId,
            subjectId: envelope.subject.subjectId,
          ),
        ],
      );
    }

    final keyRevocation = _revocationEvaluator.evaluateKey(
      keyId: envelope.keyReference.keyId,
      revocations: revocations,
      referenceTime: referenceTime,
    );
    if (keyRevocation.status ==
        CryptographicRevocationEvaluationStatus.revoked) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.revoked,
        trustLevel: CryptographicTrustLevel.none,
        message: keyRevocation.message,
        issues: keyRevocation.issues,
      );
    }
    if (keyRevocation.status ==
        CryptographicRevocationEvaluationStatus.conflicting) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        trustLevel: CryptographicTrustLevel.none,
        message: keyRevocation.message,
        issues: keyRevocation.issues,
      );
    }

    if (_isExpired(referenceTime, envelope.expiresAt) ||
        _isExpired(referenceTime, envelope.keyReference.validUntil)) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.expired,
        trustLevel: CryptographicTrustLevel.none,
        message: 'signature or key expired',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIG_EXPIRED',
            severity: CryptographicIssueSeverity.error,
            path: 'expiresAt',
            message: 'Signature or signing key is expired',
            signatureId: envelope.signatureId,
            subjectId: envelope.subject.subjectId,
          ),
        ],
      );
    }

    if (_publicKeyResolver == null) {
      return const CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        trustLevel: CryptographicTrustLevel.none,
        message: 'no public key resolver configured',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIG_KEY_RESOLVER_UNAVAILABLE',
            severity: CryptographicIssueSeverity.error,
            path: 'publicKeyResolver',
            message: 'No public key resolver configured',
          ),
        ],
      );
    }

    final keyResolution =
        _publicKeyResolver!.resolvePublicKey(envelope.keyReference);
    if (keyResolution.outcome != CryptographicPrimitiveOutcome.valid ||
        keyResolution.publicKeyMaterial == null) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: keyResolution.outcome,
        trustLevel: CryptographicTrustLevel.none,
        message: keyResolution.message,
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIG_KEY_RESOLUTION',
            severity: CryptographicIssueSeverity.error,
            path: 'keyReference',
            message: keyResolution.message ?? 'Public key resolution failed',
            signatureId: envelope.signatureId,
            subjectId: envelope.subject.subjectId,
          ),
        ],
      );
    }

    final verifier = _algorithmRegistry.resolveSignatureVerifier(
      algorithmId: envelope.signatureDescriptor.algorithmId,
      keyType: envelope.signatureDescriptor.keyType,
      format: envelope.signatureDescriptor.format,
    );
    if (verifier == null) {
      return CryptographicSignatureVerificationServiceResult(
        outcome: CryptographicPrimitiveOutcome.unsupported,
        trustLevel: CryptographicTrustLevel.none,
        message:
            'no verifier registered for ${envelope.signatureDescriptor.algorithmId}',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIG_UNSUPPORTED',
            severity: CryptographicIssueSeverity.error,
            path: 'signatureDescriptor.algorithmId',
            message:
                'No signature verifier registered for ${envelope.signatureDescriptor.algorithmId}',
            signatureId: envelope.signatureId,
            subjectId: envelope.subject.subjectId,
          ),
        ],
      );
    }

    final primitive = await verifier.verifySignature(
      subjectBytes: subjectBytes,
      envelope: envelope,
      publicKeyMaterial: keyResolution.publicKeyMaterial!,
    );

    return CryptographicSignatureVerificationServiceResult(
      outcome: primitive.outcome,
      trustLevel: CryptographicTrustLevel.none,
      message: primitive.message,
      issues: primitive.outcome == CryptographicPrimitiveOutcome.valid
          ? const []
          : [
              CryptographicVerificationIssue(
                code: 'CT_SIG_VERIFY_FAILED',
                severity: CryptographicIssueSeverity.error,
                path: 'verifySignature',
                message: primitive.message ?? 'Signature verification failed',
                signatureId: envelope.signatureId,
                subjectId: envelope.subject.subjectId,
              ),
            ],
    );
  }

  CryptographicVerificationStatus mapOutcomeToVerificationStatus(
    CryptographicPrimitiveOutcome outcome,
  ) {
    switch (outcome) {
      case CryptographicPrimitiveOutcome.valid:
        return CryptographicVerificationStatus.verified;
      case CryptographicPrimitiveOutcome.invalid:
      case CryptographicPrimitiveOutcome.malformed:
      case CryptographicPrimitiveOutcome.algorithmMismatch:
        return CryptographicVerificationStatus.invalid;
      case CryptographicPrimitiveOutcome.revoked:
      case CryptographicPrimitiveOutcome.expired:
        return CryptographicVerificationStatus.revoked;
      case CryptographicPrimitiveOutcome.unsupported:
      case CryptographicPrimitiveOutcome.unavailable:
      case CryptographicPrimitiveOutcome.keyNotFound:
        return CryptographicVerificationStatus.unverified;
    }
  }

  bool _isExpired(String? referenceTime, String? expiresAt) {
    if (referenceTime == null || expiresAt == null || expiresAt.isEmpty) {
      return false;
    }
    return referenceTime.compareTo(expiresAt) > 0;
  }
}
