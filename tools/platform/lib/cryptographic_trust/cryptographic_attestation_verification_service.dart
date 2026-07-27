import '../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../models/cryptographic_trust/cryptographic_revocation_record.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_attestation_validator.dart';
import 'cryptographic_signature_verification_service.dart';

/// Result of attestation verification — predicate claims are not executed.
class CryptographicAttestationVerificationServiceResult {
  const CryptographicAttestationVerificationServiceResult({
    required this.structuralOutcome,
    required this.signatureOutcome,
    required this.trustLevel,
    this.issues = const [],
    this.message,
  });

  final CryptographicPrimitiveOutcome structuralOutcome;
  final CryptographicPrimitiveOutcome signatureOutcome;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Verifies attestation structure and bound signatures without executing claims.
class CryptographicAttestationVerificationService {
  CryptographicAttestationVerificationService({
    required CryptographicSignatureVerificationService
        signatureVerificationService,
    CryptographicAttestationValidator? attestationValidator,
  })  : _signatureVerificationService = signatureVerificationService,
        _attestationValidator =
            attestationValidator ?? const CryptographicAttestationValidator();

  final CryptographicSignatureVerificationService _signatureVerificationService;
  final CryptographicAttestationValidator _attestationValidator;

  Future<CryptographicAttestationVerificationServiceResult> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    Map<String, List<int>> subjectBytesById = const {},
    List<CryptographicRevocationRecord> revocations = const [],
    String? referenceTime,
  }) async {
    final structural = _attestationValidator.validate(attestation);
    if (!structural.isValid) {
      return CryptographicAttestationVerificationServiceResult(
        structuralOutcome: CryptographicPrimitiveOutcome.malformed,
        signatureOutcome: CryptographicPrimitiveOutcome.unavailable,
        trustLevel: CryptographicTrustLevel.none,
        message: 'attestation structurally invalid',
        issues: structural.issues
            .map(
              (issue) => CryptographicVerificationIssue(
                code: issue.code,
                severity: issue.severity,
                path: issue.path,
                message: issue.message,
                attestationId: attestation.attestationId,
              ),
            )
            .toList(),
      );
    }

    if (attestation.signatures.isEmpty) {
      return CryptographicAttestationVerificationServiceResult(
        structuralOutcome: CryptographicPrimitiveOutcome.valid,
        signatureOutcome: CryptographicPrimitiveOutcome.unavailable,
        trustLevel: CryptographicTrustLevel.none,
        message: 'attestation has no signatures to verify',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_ATTESTATION_NO_SIGNATURES',
            severity: CryptographicIssueSeverity.warning,
            path: 'signatures',
            message: 'Attestation has no bound signatures',
            attestationId: attestation.attestationId,
          ),
        ],
      );
    }

    final issues = <CryptographicVerificationIssue>[];
    var worstOutcome = CryptographicPrimitiveOutcome.valid;

    for (final signature in attestation.signatures) {
      final subjectBytes = subjectBytesById[signature.subject.subjectId];
      if (subjectBytes == null) {
        worstOutcome = _worstOutcome(
          worstOutcome,
          CryptographicPrimitiveOutcome.unavailable,
        );
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_ATTESTATION_SUBJECT_BYTES_MISSING',
            severity: CryptographicIssueSeverity.error,
            path: 'signatures/${signature.signatureId}',
            message:
                'Explicit subject bytes unavailable for signature verification',
            attestationId: attestation.attestationId,
            signatureId: signature.signatureId,
            subjectId: signature.subject.subjectId,
          ),
        );
        continue;
      }

      final result = await _signatureVerificationService.verifySignature(
        subjectBytes: subjectBytes,
        envelope: signature,
        revocations: revocations,
        referenceTime: referenceTime,
      );
      worstOutcome = _worstOutcome(worstOutcome, result.outcome);
      issues.addAll(
        result.issues.map(
          (issue) => issue.copyWith(attestationId: attestation.attestationId),
        ),
      );
    }

    return CryptographicAttestationVerificationServiceResult(
      structuralOutcome: CryptographicPrimitiveOutcome.valid,
      signatureOutcome: worstOutcome,
      trustLevel: CryptographicTrustLevel.none,
      issues: issues,
      message: worstOutcome == CryptographicPrimitiveOutcome.valid
          ? null
          : 'one or more attestation signatures failed verification',
    );
  }

  CryptographicPrimitiveOutcome _worstOutcome(
    CryptographicPrimitiveOutcome current,
    CryptographicPrimitiveOutcome next,
  ) {
    const priority = {
      CryptographicPrimitiveOutcome.valid: 0,
      CryptographicPrimitiveOutcome.unsupported: 1,
      CryptographicPrimitiveOutcome.unavailable: 2,
      CryptographicPrimitiveOutcome.malformed: 3,
      CryptographicPrimitiveOutcome.algorithmMismatch: 4,
      CryptographicPrimitiveOutcome.keyNotFound: 5,
      CryptographicPrimitiveOutcome.expired: 6,
      CryptographicPrimitiveOutcome.revoked: 7,
      CryptographicPrimitiveOutcome.invalid: 8,
    };
    final currentScore = priority[current] ?? 0;
    final nextScore = priority[next] ?? 0;
    return nextScore >= currentScore ? next : current;
  }
}
