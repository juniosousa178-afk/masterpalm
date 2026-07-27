import '../models/cryptographic_trust/cryptographic_revocation_record.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_revocation_validator.dart';

/// Declarative revocation evaluation status.
enum CryptographicRevocationEvaluationStatus {
  nonRevoked,
  revoked,
  unknown,
  unavailable,
  conflicting,
}

/// Result of evaluating declarative revocation records.
class CryptographicRevocationEvaluationResult {
  const CryptographicRevocationEvaluationResult({
    required this.status,
    this.subjectId,
    this.keyId,
    this.matchingRevocationIds = const [],
    this.issues = const [],
    this.message,
  });

  final CryptographicRevocationEvaluationStatus status;
  final String? subjectId;
  final String? keyId;
  final List<String> matchingRevocationIds;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Evaluates declarative revocation records without external CRL/OCSP lookup.
class CryptographicRevocationEvaluator {
  const CryptographicRevocationEvaluator({
    CryptographicRevocationValidator? revocationValidator,
  }) : _revocationValidator =
            revocationValidator ?? const CryptographicRevocationValidator();

  final CryptographicRevocationValidator _revocationValidator;

  CryptographicRevocationEvaluationResult evaluateSubject({
    required String subjectId,
    required CryptographicTrustSubjectType subjectType,
    List<CryptographicRevocationRecord> revocations = const [],
    String? referenceTime,
  }) {
    return _evaluate(
      targetId: subjectId,
      subjectType: subjectType,
      revocations: revocations,
      referenceTime: referenceTime,
      subjectId: subjectId,
    );
  }

  CryptographicRevocationEvaluationResult evaluateKey({
    required String keyId,
    List<CryptographicRevocationRecord> revocations = const [],
    String? referenceTime,
  }) {
    return _evaluate(
      targetId: keyId,
      subjectType: CryptographicTrustSubjectType.key,
      revocations: revocations,
      referenceTime: referenceTime,
      keyId: keyId,
    );
  }

  CryptographicRevocationEvaluationResult _evaluate({
    required String targetId,
    required CryptographicTrustSubjectType subjectType,
    required List<CryptographicRevocationRecord> revocations,
    required String? referenceTime,
    String? subjectId,
    String? keyId,
  }) {
    if (revocations.isEmpty) {
      return CryptographicRevocationEvaluationResult(
        status: CryptographicRevocationEvaluationStatus.unknown,
        subjectId: subjectId,
        keyId: keyId,
        message: 'no revocation records available',
      );
    }

    final matches = revocations.where((record) {
      if (record.subjectType != subjectType) return false;
      if (record.subjectId != targetId) return false;
      if (!_isEffective(record, referenceTime)) return false;
      return record.status == CryptographicRevocationStatus.active;
    }).toList();

    if (matches.isEmpty) {
      return CryptographicRevocationEvaluationResult(
        status: CryptographicRevocationEvaluationStatus.nonRevoked,
        subjectId: subjectId,
        keyId: keyId,
      );
    }

    final fingerprints = <String>{};
    for (final record in matches) {
      final validation = _revocationValidator.validate(record);
      if (!validation.isValid) {
        return CryptographicRevocationEvaluationResult(
          status: CryptographicRevocationEvaluationStatus.unavailable,
          subjectId: subjectId,
          keyId: keyId,
          matchingRevocationIds: matches.map((e) => e.revocationId).toList(),
          message: 'revocation record structurally invalid',
          issues: validation.issues
              .map(
                (issue) => CryptographicVerificationIssue(
                  code: issue.code,
                  severity: issue.severity,
                  path: issue.path,
                  message: issue.message,
                  subjectId: subjectId,
                ),
              )
              .toList(),
        );
      }
      fingerprints.add(
        CryptographicTrustFingerprint.fromComparableJson(
          record.toComparableJson(),
        ),
      );
    }

    if (fingerprints.length > 1) {
      return CryptographicRevocationEvaluationResult(
        status: CryptographicRevocationEvaluationStatus.conflicting,
        subjectId: subjectId,
        keyId: keyId,
        matchingRevocationIds: matches.map((e) => e.revocationId).toList(),
        message: 'conflicting active revocation records for $targetId',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_REVOCATION_CONFLICT',
            severity: CryptographicIssueSeverity.error,
            path: 'revocations',
            message: 'Conflicting active revocation records for $targetId',
            subjectId: subjectId,
          ),
        ],
      );
    }

    return CryptographicRevocationEvaluationResult(
      status: CryptographicRevocationEvaluationStatus.revoked,
      subjectId: subjectId,
      keyId: keyId,
      matchingRevocationIds: matches.map((e) => e.revocationId).toList(),
      message: 'target revoked by declarative record',
      issues: [
        CryptographicVerificationIssue(
          code: 'CT_REVOCATION_ACTIVE',
          severity: CryptographicIssueSeverity.error,
          path: 'revocations/${matches.first.revocationId}',
          message: 'Target is revoked by declarative record',
          subjectId: subjectId,
        ),
      ],
    );
  }

  bool _isEffective(
    CryptographicRevocationRecord record,
    String? referenceTime,
  ) {
    if (referenceTime == null) return true;
    final effectiveAt = record.effectiveAt ?? record.revokedAt;
    if (effectiveAt == null || effectiveAt.isEmpty) return true;
    return referenceTime.compareTo(effectiveAt) >= 0;
  }
}
