import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'adapters/sha256_digest_provider.dart';
import 'cryptographic_algorithm_registry.dart';

/// Result of computing a digest on explicit payload bytes.
class CryptographicDigestComputationResult {
  const CryptographicDigestComputationResult({
    required this.outcome,
    this.computedDigest,
    this.issues = const [],
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final CryptographicDigest? computedDigest;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Result of comparing computed and declared digests.
class CryptographicDigestComparisonResult {
  const CryptographicDigestComparisonResult({
    required this.outcome,
    this.computedDigest,
    this.declaredDigest,
    this.issues = const [],
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final CryptographicDigest? computedDigest;
  final CryptographicDigest? declaredDigest;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Computes and compares digests using registered [CryptographicDigestProvider]s.
///
/// Never derives digest values from [CryptographicTrustSubject.sourceFingerprint].
class CryptographicDigestService {
  CryptographicDigestService({
    required CryptographicAlgorithmRegistry algorithmRegistry,
  }) : _algorithmRegistry = algorithmRegistry;

  final CryptographicAlgorithmRegistry _algorithmRegistry;

  CryptographicDigestComputationResult computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest declaredDigest,
  }) {
    if (subjectBytes.isEmpty) {
      return CryptographicDigestComputationResult(
        outcome: CryptographicPrimitiveOutcome.malformed,
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_DIGEST_EMPTY_PAYLOAD',
            severity: CryptographicIssueSeverity.error,
            path: 'subjectBytes',
            message: 'Digest computation requires explicit payload bytes',
            subjectId: declaredDigest.subjectId,
          ),
        ],
        message: 'empty payload bytes',
      );
    }

    final provider = _algorithmRegistry.resolveDigestProvider(
      declaredDigest.descriptor.algorithmId,
    );
    if (provider == null) {
      return CryptographicDigestComputationResult(
        outcome: CryptographicPrimitiveOutcome.unsupported,
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_DIGEST_UNSUPPORTED_ALGORITHM',
            severity: CryptographicIssueSeverity.error,
            path: 'descriptor.algorithmId',
            message:
                'No digest provider registered for ${declaredDigest.descriptor.algorithmId}',
            subjectId: declaredDigest.subjectId,
          ),
        ],
        message: 'unsupported digest algorithm',
      );
    }

    try {
      final computed = provider.computeDigest(
        subjectBytes: subjectBytes,
        descriptor: declaredDigest.descriptor,
        subjectId: declaredDigest.subjectId,
      );
      return CryptographicDigestComputationResult(
        outcome: CryptographicPrimitiveOutcome.valid,
        computedDigest: computed,
      );
    } catch (error) {
      return CryptographicDigestComputationResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        message: error.toString(),
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_DIGEST_COMPUTE_FAILED',
            severity: CryptographicIssueSeverity.error,
            path: 'computeDigest',
            message: 'Digest computation failed: $error',
            subjectId: declaredDigest.subjectId,
          ),
        ],
      );
    }
  }

  CryptographicDigestComparisonResult compareDigest({
    required List<int> subjectBytes,
    required CryptographicDigest declaredDigest,
  }) {
    final computation = computeDigest(
      subjectBytes: subjectBytes,
      declaredDigest: declaredDigest,
    );
    if (computation.outcome != CryptographicPrimitiveOutcome.valid ||
        computation.computedDigest == null) {
      return CryptographicDigestComparisonResult(
        outcome: computation.outcome,
        computedDigest: computation.computedDigest,
        declaredDigest: declaredDigest,
        issues: computation.issues,
        message: computation.message,
      );
    }

    final computed = computation.computedDigest!;
    final issues = <CryptographicVerificationIssue>[];

    final computedValue =
        _normalizeDigestValue(computed.value, computed.encoding);
    final declaredValue =
        _normalizeDigestValue(declaredDigest.value, declaredDigest.encoding);

    if (computedValue != declaredValue) {
      issues.add(
        CryptographicVerificationIssue(
          code: 'CT_DIGEST_VALUE_MISMATCH',
          severity: CryptographicIssueSeverity.error,
          path: 'value',
          message: 'Declared digest value does not match computed digest',
          subjectId: declaredDigest.subjectId,
          metadata: {
            'declaredValue': declaredValue,
            'computedValue': computedValue,
          },
        ),
      );
    }

    if (issues.isNotEmpty) {
      return CryptographicDigestComparisonResult(
        outcome: CryptographicPrimitiveOutcome.invalid,
        computedDigest: computed,
        declaredDigest: declaredDigest,
        issues: issues,
        message: 'digest mismatch',
      );
    }

    return CryptographicDigestComparisonResult(
      outcome: CryptographicPrimitiveOutcome.valid,
      computedDigest: computed,
      declaredDigest: declaredDigest,
    );
  }

  String _normalizeDigestValue(String value, String encoding) {
    final trimmed = value.trim().toLowerCase();
    switch (encoding) {
      case 'hex':
        return trimmed;
      case 'base64':
        return base64ToHex(trimmed).toLowerCase();
      default:
        return trimmed;
    }
  }
}
