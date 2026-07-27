import '../models/cryptographic_trust/cryptographic_transparency_log_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_transparency_log_reference_validator.dart';
import 'interfaces/cryptographic_transparency_proof_verifier.dart';

/// Transparency log evaluation status.
enum CryptographicTransparencyEvaluationStatus {
  structurallyValid,
  verified,
  invalid,
  unsupported,
  unavailable,
}

/// Result of evaluating a transparency log reference.
class CryptographicTransparencyEvaluationResult {
  const CryptographicTransparencyEvaluationResult({
    required this.status,
    this.reference,
    this.proofOutcome,
    this.issues = const [],
    this.message,
  });

  final CryptographicTransparencyEvaluationStatus status;
  final CryptographicTransparencyLogReference? reference;
  final CryptographicPrimitiveOutcome? proofOutcome;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Evaluates transparency log references structurally and optionally via proof.
class CryptographicTransparencyEvaluator {
  CryptographicTransparencyEvaluator({
    CryptographicTransparencyLogReferenceValidator? referenceValidator,
    CryptographicTransparencyProofVerifier? proofVerifier,
  })  : _referenceValidator = referenceValidator ??
            const CryptographicTransparencyLogReferenceValidator(),
        _proofVerifier = proofVerifier;

  final CryptographicTransparencyLogReferenceValidator _referenceValidator;
  final CryptographicTransparencyProofVerifier? _proofVerifier;

  CryptographicTransparencyEvaluationResult evaluate({
    required CryptographicTransparencyLogReference reference,
    List<int>? leafDigestBytes,
    List<int>? proofBytes,
    List<int>? rootHashBytes,
  }) {
    final structural = _referenceValidator.validate(reference);
    if (!structural.isValid) {
      return CryptographicTransparencyEvaluationResult(
        status: CryptographicTransparencyEvaluationStatus.invalid,
        reference: reference,
        issues: structural.issues
            .map(
              (issue) => CryptographicVerificationIssue(
                code: issue.code,
                severity: issue.severity,
                path: issue.path,
                message: issue.message,
                metadata: {
                  'entryId': reference.entryId,
                  if (issue.relatedId != null) 'relatedId': issue.relatedId!,
                },
              ),
            )
            .toList(),
        message: 'transparency log reference structurally invalid',
      );
    }

    if (reference.status == CryptographicTransparencyLogStatus.rejected ||
        reference.status == CryptographicTransparencyLogStatus.expired) {
      return CryptographicTransparencyEvaluationResult(
        status: CryptographicTransparencyEvaluationStatus.invalid,
        reference: reference,
        message:
            'transparency log entry status is ${reference.status.wireName}',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_LOG_STATUS_INVALID',
            severity: CryptographicIssueSeverity.error,
            path: 'status',
            message:
                'Transparency log entry status is ${reference.status.wireName}',
            metadata: {'entryId': reference.entryId},
          ),
        ],
      );
    }

    if (_proofVerifier == null) {
      return CryptographicTransparencyEvaluationResult(
        status: CryptographicTransparencyEvaluationStatus.structurallyValid,
        reference: reference,
        message: 'no transparency proof verifier configured',
      );
    }

    if (leafDigestBytes == null ||
        proofBytes == null ||
        rootHashBytes == null) {
      return CryptographicTransparencyEvaluationResult(
        status: CryptographicTransparencyEvaluationStatus.unavailable,
        reference: reference,
        message: 'proof bytes unavailable for verification',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_LOG_PROOF_UNAVAILABLE',
            severity: CryptographicIssueSeverity.warning,
            path: 'proof',
            message:
                'Transparency proof verification requires explicit proof bytes',
            metadata: {'entryId': reference.entryId},
          ),
        ],
      );
    }

    if (_proofVerifier!.logId != reference.logId) {
      return CryptographicTransparencyEvaluationResult(
        status: CryptographicTransparencyEvaluationStatus.unsupported,
        reference: reference,
        proofOutcome: CryptographicPrimitiveOutcome.unsupported,
        message: 'configured proof verifier does not match logId',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_LOG_VERIFIER_MISMATCH',
            severity: CryptographicIssueSeverity.error,
            path: 'logId',
            message:
                'Proof verifier logId ${_proofVerifier!.logId} does not match reference ${reference.logId}',
            metadata: {'entryId': reference.entryId},
          ),
        ],
      );
    }

    final proof = _proofVerifier!.verifyProof(
      leafDigest: leafDigestBytes,
      proofBytes: proofBytes,
      rootHash: rootHashBytes,
    );

    switch (proof.outcome) {
      case CryptographicPrimitiveOutcome.valid:
        return CryptographicTransparencyEvaluationResult(
          status: CryptographicTransparencyEvaluationStatus.verified,
          reference: reference,
          proofOutcome: proof.outcome,
        );
      case CryptographicPrimitiveOutcome.unsupported:
        return CryptographicTransparencyEvaluationResult(
          status: CryptographicTransparencyEvaluationStatus.unsupported,
          reference: reference,
          proofOutcome: proof.outcome,
          message: proof.message,
        );
      case CryptographicPrimitiveOutcome.unavailable:
        return CryptographicTransparencyEvaluationResult(
          status: CryptographicTransparencyEvaluationStatus.unavailable,
          reference: reference,
          proofOutcome: proof.outcome,
          message: proof.message,
        );
      default:
        return CryptographicTransparencyEvaluationResult(
          status: CryptographicTransparencyEvaluationStatus.invalid,
          reference: reference,
          proofOutcome: proof.outcome,
          message: proof.message,
          issues: [
            CryptographicVerificationIssue(
              code: 'CT_LOG_PROOF_INVALID',
              severity: CryptographicIssueSeverity.error,
              path: 'proof',
              message:
                  proof.message ?? 'Transparency proof verification failed',
              metadata: {'entryId': reference.entryId},
            ),
          ],
        );
    }
  }
}
