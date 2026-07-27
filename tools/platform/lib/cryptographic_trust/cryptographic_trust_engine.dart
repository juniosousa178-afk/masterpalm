import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_trust_chain.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'cryptographic_trust_chain_builder.dart';
import 'cryptographic_trust_policy_evaluators.dart';

/// Input bundle for trust engine consolidation.
class CryptographicTrustEngineInput {
  const CryptographicTrustEngineInput({
    required this.material,
    required this.sources,
    required this.evaluationId,
    required this.projectId,
    this.releaseId,
    this.policy,
    this.verificationResult,
    this.policyEvaluation,
    this.chainBuildResult,
    this.structuralValidation,
    this.additionalIssues = const [],
    this.warnings = const [],
    this.limitations = const [],
  });

  final CollectedCryptographicTrustMaterial material;
  final ResolvedCryptographicTrustSources sources;
  final String evaluationId;
  final String projectId;
  final String? releaseId;
  final CryptographicTrustPolicy? policy;
  final CryptographicVerificationResult? verificationResult;
  final CryptographicTrustPolicyEvaluationResult? policyEvaluation;
  final CryptographicTrustChainBuildResult? chainBuildResult;
  final CryptographicValidationResult? structuralValidation;
  final List<CryptographicVerificationIssue> additionalIssues;
  final List<String> warnings;
  final List<String> limitations;
}

/// Consolidated trust engine output.
class CryptographicTrustEngineResult {
  const CryptographicTrustEngineResult({
    required this.evaluationStatus,
    required this.verificationResult,
    required this.snapshotStatus,
    required this.trustLevel,
    required this.issues,
    required this.warnings,
    required this.limitations,
    required this.trustChains,
    required this.policyEvaluation,
  });

  final CryptographicTrustEvaluationStatus evaluationStatus;
  final CryptographicVerificationResult verificationResult;
  final CryptographicTrustStatus snapshotStatus;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final List<String> warnings;
  final List<String> limitations;
  final List<CryptographicTrustChain> trustChains;
  final CryptographicTrustPolicyEvaluationResult? policyEvaluation;
}

/// Consolidates cryptographic trust evaluation results.
///
/// Verified status does not authorize release or deployment.
class CryptographicTrustEngine {
  const CryptographicTrustEngine();

  CryptographicTrustEngineResult evaluate(CryptographicTrustEngineInput input) {
    final issues = <CryptographicVerificationIssue>[
      ...input.additionalIssues,
      ...?input.chainBuildResult?.issues,
      ...?input.policyEvaluation?.issues,
    ];

    if (input.structuralValidation != null &&
        !input.structuralValidation!.isValid) {
      for (final validationIssue in input.structuralValidation!.issues) {
        issues.add(
          CryptographicVerificationIssue(
            code: validationIssue.code,
            severity: validationIssue.severity,
            path: validationIssue.path,
            message: validationIssue.message,
            metadata: validationIssue.relatedId == null
                ? const {}
                : {'relatedId': validationIssue.relatedId!},
          ),
        );
      }
    }

    final verificationResult = _mergeVerificationResult(input, issues);
    final snapshotStatus = _deriveSnapshotStatus(
      verificationResult: verificationResult,
      issues: issues,
      sourceSummary: input.sources.resolutionSummary,
    );
    final trustLevel = verificationResult.trustLevel;
    final evaluationStatus = _deriveEvaluationStatus(
      verificationResult: verificationResult,
      sourceSummary: input.sources.resolutionSummary,
      structuralValidation: input.structuralValidation,
    );

    final warnings = <String>[
      ...input.warnings,
      ...?input.chainBuildResult?.warnings,
      if (verificationResult.status == CryptographicVerificationStatus.verified)
        'verified-does-not-authorize-release',
    ];

    final limitations = <String>[
      ...input.limitations,
      ...?input.chainBuildResult?.limitations,
      ...?input.policyEvaluation?.limitations,
      'no-release-authorization',
      'no-deployment-authorization',
    ];

    return CryptographicTrustEngineResult(
      evaluationStatus: evaluationStatus,
      verificationResult: verificationResult,
      snapshotStatus: snapshotStatus,
      trustLevel: trustLevel,
      issues: List.unmodifiable(issues),
      warnings: List.unmodifiable(warnings.toSet().toList()..sort()),
      limitations: List.unmodifiable(limitations.toSet().toList()..sort()),
      trustChains: input.chainBuildResult?.chains ?? input.material.trustChains,
      policyEvaluation: input.policyEvaluation,
    );
  }

  /// Explicit status decision table for aggregate verification status.
  ///
  /// | Condition | Result |
  /// |---|---|
  /// | fatal/critical issue | invalid |
  /// | conflict detected | invalid |
  /// | invalid component | invalid |
  /// | unsupported component | partiallyVerified (never valid) |
  /// | unavailable component | partiallyVerified (never invalid) |
  /// | all verified, no fatal | verified (no release auth) |
  CryptographicVerificationStatus deriveVerificationStatus({
    required List<CryptographicVerificationIssue> issues,
    required CryptographicVerificationResult? baseResult,
  }) {
    if (issues.any((i) => i.severity == CryptographicIssueSeverity.critical)) {
      return CryptographicVerificationStatus.invalid;
    }

    final hasConflict = issues.any((i) => i.code.contains('CONFLICT'));
    if (hasConflict) {
      return CryptographicVerificationStatus.invalid;
    }

    final baseStatus =
        baseResult?.status ?? CryptographicVerificationStatus.pending;

    if (baseStatus == CryptographicVerificationStatus.invalid ||
        baseStatus == CryptographicVerificationStatus.error ||
        baseStatus == CryptographicVerificationStatus.revoked) {
      return CryptographicVerificationStatus.invalid;
    }

    if (_containsOutcome(baseResult, CryptographicVerificationStatus.invalid)) {
      return CryptographicVerificationStatus.invalid;
    }

    if (_containsOutcome(baseResult, CryptographicVerificationStatus.unknown) ||
        issues.any((i) => i.code.contains('UNSUPPORTED'))) {
      return CryptographicVerificationStatus.partiallyVerified;
    }

    if (baseStatus == CryptographicVerificationStatus.pending ||
        issues.any((i) => i.code.contains('UNAVAILABLE'))) {
      return CryptographicVerificationStatus.partiallyVerified;
    }

    if (baseStatus == CryptographicVerificationStatus.partiallyVerified) {
      return CryptographicVerificationStatus.partiallyVerified;
    }

    if (baseStatus == CryptographicVerificationStatus.verified &&
        issues.isEmpty) {
      return CryptographicVerificationStatus.verified;
    }

    if (baseStatus == CryptographicVerificationStatus.verified) {
      return CryptographicVerificationStatus.partiallyVerified;
    }

    return CryptographicVerificationStatus.unverified;
  }

  CryptographicVerificationResult _mergeVerificationResult(
    CryptographicTrustEngineInput input,
    List<CryptographicVerificationIssue> issues,
  ) {
    final base = input.verificationResult;
    final requestId = input.material.verificationRequests.isNotEmpty
        ? input.material.verificationRequests.first.requestId
        : input.sources.verificationRequest.resolvedId ?? 'unknown';

    final status = deriveVerificationStatus(issues: issues, baseResult: base);
    final trustLevel = _deriveAggregateTrustLevel(
      status: status,
      baseResult: base,
      policyEvaluation: input.policyEvaluation,
    );

    final policyResults = <CryptographicPolicyVerificationResult>[
      if (input.policyEvaluation != null) input.policyEvaluation!.policyResult,
      ...?base?.policyResults,
    ];

    return CryptographicVerificationResult(
      verificationId: base?.verificationId ??
          'ct-verify:${input.evaluationId}:${requestId}',
      requestId: requestId,
      projectId: input.projectId,
      releaseId: input.releaseId,
      status: status,
      trustLevel: trustLevel,
      subjectResults: base?.subjectResults ?? const [],
      signatureResults: base?.signatureResults ?? const [],
      attestationResults: base?.attestationResults ?? const [],
      policyResults: policyResults,
      issues: issues,
      metadata: {
        ...?base?.metadata,
        'noReleaseAuthorization': 'true',
      },
    );
  }

  CryptographicTrustStatus _deriveSnapshotStatus({
    required CryptographicVerificationResult verificationResult,
    required List<CryptographicVerificationIssue> issues,
    required CryptographicTrustSourceResolutionSummary sourceSummary,
  }) {
    if (sourceSummary.status ==
        CryptographicTrustSourceResolutionStatus.failed) {
      return CryptographicTrustStatus.invalid;
    }

    switch (verificationResult.status) {
      case CryptographicVerificationStatus.verified:
        return CryptographicTrustStatus.provisional;
      case CryptographicVerificationStatus.partiallyVerified:
        return CryptographicTrustStatus.provisional;
      case CryptographicVerificationStatus.revoked:
        return CryptographicTrustStatus.revoked;
      case CryptographicVerificationStatus.expired:
        return CryptographicTrustStatus.expired;
      case CryptographicVerificationStatus.invalid:
      case CryptographicVerificationStatus.error:
        return CryptographicTrustStatus.invalid;
      case CryptographicVerificationStatus.unverified:
      case CryptographicVerificationStatus.pending:
      case CryptographicVerificationStatus.unknown:
        if (sourceSummary.status ==
            CryptographicTrustSourceResolutionStatus.unavailable) {
          return CryptographicTrustStatus.unknown;
        }
        return CryptographicTrustStatus.untrusted;
    }
  }

  CryptographicTrustEvaluationStatus _deriveEvaluationStatus({
    required CryptographicVerificationResult verificationResult,
    required CryptographicTrustSourceResolutionSummary sourceSummary,
    required CryptographicValidationResult? structuralValidation,
  }) {
    if (sourceSummary.status ==
        CryptographicTrustSourceResolutionStatus.unavailable) {
      return CryptographicTrustEvaluationStatus.unavailable;
    }

    if (structuralValidation != null && !structuralValidation.isValid) {
      return CryptographicTrustEvaluationStatus.failure;
    }

    if (sourceSummary.status ==
        CryptographicTrustSourceResolutionStatus.partial) {
      return CryptographicTrustEvaluationStatus.partial;
    }

    if (verificationResult.status == CryptographicVerificationStatus.invalid ||
        verificationResult.status == CryptographicVerificationStatus.error) {
      return CryptographicTrustEvaluationStatus.failure;
    }

    if (verificationResult.status ==
        CryptographicVerificationStatus.partiallyVerified) {
      return CryptographicTrustEvaluationStatus.partial;
    }

    return CryptographicTrustEvaluationStatus.success;
  }

  CryptographicTrustLevel _deriveAggregateTrustLevel({
    required CryptographicVerificationStatus status,
    required CryptographicVerificationResult? baseResult,
    required CryptographicTrustPolicyEvaluationResult? policyEvaluation,
  }) {
    if (status == CryptographicVerificationStatus.invalid ||
        status == CryptographicVerificationStatus.unverified) {
      return CryptographicTrustLevel.none;
    }

    final candidates = <CryptographicTrustLevel>[
      if (baseResult != null) baseResult.trustLevel,
      if (policyEvaluation != null) policyEvaluation.policyResult.trustLevel,
    ];

    if (candidates.isEmpty) {
      return CryptographicTrustLevel.none;
    }

    candidates.sort(
      (a, b) => _levelRank(a).compareTo(_levelRank(b)),
    );
    return candidates.first;
  }

  bool _containsOutcome(
    CryptographicVerificationResult? result,
    CryptographicVerificationStatus status,
  ) {
    if (result == null) return false;
    if (result.status == status) return true;
    return result.signatureResults.any((r) => r.status == status) ||
        result.attestationResults.any((r) => r.status == status) ||
        result.subjectResults.any((r) => r.status == status);
  }

  int _levelRank(CryptographicTrustLevel level) {
    switch (level) {
      case CryptographicTrustLevel.none:
        return 0;
      case CryptographicTrustLevel.low:
        return 1;
      case CryptographicTrustLevel.moderate:
        return 2;
      case CryptographicTrustLevel.high:
        return 3;
      case CryptographicTrustLevel.critical:
        return 4;
      case CryptographicTrustLevel.unknown:
        return -1;
    }
  }
}
