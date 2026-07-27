import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_requirement.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import '../models/cryptographic_trust/policies/attestation_trust_policy_v1.dart';
import '../models/cryptographic_trust/policies/release_trust_policy_v1.dart';

/// Result of policy evaluation — does not authorize release.
class CryptographicTrustPolicyEvaluationResult {
  const CryptographicTrustPolicyEvaluationResult({
    required this.policyResult,
    this.requirementResults = const {},
    this.issues = const [],
    this.limitations = const [
      'policy-evaluation-only',
      'no-release-authorization',
    ],
  });

  final CryptographicPolicyVerificationResult policyResult;
  final Map<String, CryptographicVerificationStatus> requirementResults;
  final List<CryptographicVerificationIssue> issues;
  final List<String> limitations;
}

/// Evaluates artifact-signature-trust-v1 requirements.
class ArtifactSignatureTrustPolicyEvaluator {
  const ArtifactSignatureTrustPolicyEvaluator();

  CryptographicTrustPolicyEvaluationResult evaluate({
    required CryptographicTrustPolicy policy,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicVerificationResult? verificationResult,
    required CryptographicTrustPolicyReference? policyReference,
  }) {
    return _evaluatePolicy(
      policy: policy,
      material: material,
      verificationResult: verificationResult,
      policyReference: policyReference,
      expectedPolicyId: ArtifactSignatureTrustPolicyV1.policyId,
    );
  }
}

/// Evaluates attestation-trust-v1 requirements.
class AttestationTrustPolicyEvaluator {
  const AttestationTrustPolicyEvaluator();

  CryptographicTrustPolicyEvaluationResult evaluate({
    required CryptographicTrustPolicy policy,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicVerificationResult? verificationResult,
    required CryptographicTrustPolicyReference? policyReference,
  }) {
    return _evaluatePolicy(
      policy: policy,
      material: material,
      verificationResult: verificationResult,
      policyReference: policyReference,
      expectedPolicyId: AttestationTrustPolicyV1.policyId,
    );
  }
}

/// Evaluates release-trust-v1 requirements.
///
/// Evaluates release-related trust signals only — does not authorize release.
class ReleaseTrustPolicyEvaluator {
  const ReleaseTrustPolicyEvaluator();

  CryptographicTrustPolicyEvaluationResult evaluate({
    required CryptographicTrustPolicy policy,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicVerificationResult? verificationResult,
    required CryptographicTrustPolicyReference? policyReference,
  }) {
    return _evaluatePolicy(
      policy: policy,
      material: material,
      verificationResult: verificationResult,
      policyReference: policyReference,
      expectedPolicyId: ReleaseTrustPolicyV1.policyId,
    );
  }
}

/// Dispatches policy evaluation by policyId.
class CryptographicTrustPolicyEvaluationService {
  CryptographicTrustPolicyEvaluationService({
    ArtifactSignatureTrustPolicyEvaluator? artifactSignatureEvaluator,
    AttestationTrustPolicyEvaluator? attestationEvaluator,
    ReleaseTrustPolicyEvaluator? releaseTrustEvaluator,
  })  : _artifactSignatureEvaluator = artifactSignatureEvaluator ??
            const ArtifactSignatureTrustPolicyEvaluator(),
        _attestationEvaluator =
            attestationEvaluator ?? const AttestationTrustPolicyEvaluator(),
        _releaseTrustEvaluator =
            releaseTrustEvaluator ?? const ReleaseTrustPolicyEvaluator();

  final ArtifactSignatureTrustPolicyEvaluator _artifactSignatureEvaluator;
  final AttestationTrustPolicyEvaluator _attestationEvaluator;
  final ReleaseTrustPolicyEvaluator _releaseTrustEvaluator;

  CryptographicTrustPolicyEvaluationResult evaluate({
    required CryptographicTrustPolicy policy,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicVerificationResult? verificationResult,
    required CryptographicTrustPolicyReference? policyReference,
  }) {
    switch (policy.policyId) {
      case ArtifactSignatureTrustPolicyV1.policyId:
        return _artifactSignatureEvaluator.evaluate(
          policy: policy,
          material: material,
          verificationResult: verificationResult,
          policyReference: policyReference,
        );
      case AttestationTrustPolicyV1.policyId:
        return _attestationEvaluator.evaluate(
          policy: policy,
          material: material,
          verificationResult: verificationResult,
          policyReference: policyReference,
        );
      case ReleaseTrustPolicyV1.policyId:
        return _releaseTrustEvaluator.evaluate(
          policy: policy,
          material: material,
          verificationResult: verificationResult,
          policyReference: policyReference,
        );
      default:
        return CryptographicTrustPolicyEvaluationResult(
          policyResult: CryptographicPolicyVerificationResult(
            policyId: policy.policyId,
            status: CryptographicVerificationStatus.unknown,
            trustLevel: CryptographicTrustLevel.none,
            issues: const [
              CryptographicVerificationIssue(
                code: 'CT_POLICY_UNSUPPORTED',
                severity: CryptographicIssueSeverity.warning,
                path: 'policy.policyId',
                message: 'Unsupported policy evaluator',
              ),
            ],
          ),
        );
    }
  }
}

CryptographicTrustPolicyEvaluationResult _evaluatePolicy({
  required CryptographicTrustPolicy policy,
  required CollectedCryptographicTrustMaterial material,
  required CryptographicVerificationResult? verificationResult,
  required CryptographicTrustPolicyReference? policyReference,
  required String expectedPolicyId,
}) {
  final issues = <CryptographicVerificationIssue>[];
  final requirementResults = <String, CryptographicVerificationStatus>{};
  final satisfied = <String>[];

  if (policy.policyId != expectedPolicyId) {
    issues.add(
      CryptographicVerificationIssue(
        code: 'CT_POLICY_ID_MISMATCH',
        severity: CryptographicIssueSeverity.critical,
        path: 'policy.policyId',
        message: 'Policy id mismatch for evaluator',
        policyId: policy.policyId,
      ),
    );
  }

  if (policy.status == CryptographicPolicyStatus.candidate &&
      (policyReference == null || !policyReference.explicitSelection)) {
    issues.add(
      CryptographicVerificationIssue(
        code: 'CT_POLICY_CANDIDATE_NOT_SELECTED',
        severity: CryptographicIssueSeverity.critical,
        path: 'policyReference.explicitSelection',
        message: 'Candidate policy requires explicit selection',
        policyId: policy.policyId,
      ),
    );
    return CryptographicTrustPolicyEvaluationResult(
      policyResult: CryptographicPolicyVerificationResult(
        policyId: policy.policyId,
        status: CryptographicVerificationStatus.unverified,
        trustLevel: CryptographicTrustLevel.none,
        issues: issues,
        metadata: const {'noReleaseAuthorization': 'true'},
      ),
      requirementResults: requirementResults,
      issues: issues,
    );
  }

  if (policy.status == CryptographicPolicyStatus.retired) {
    issues.add(
      CryptographicVerificationIssue(
        code: 'CT_POLICY_RETIRED',
        severity: CryptographicIssueSeverity.critical,
        path: 'policy.status',
        message: 'Retired policy cannot start new evaluation',
        policyId: policy.policyId,
      ),
    );
    return CryptographicTrustPolicyEvaluationResult(
      policyResult: CryptographicPolicyVerificationResult(
        policyId: policy.policyId,
        status: CryptographicVerificationStatus.invalid,
        trustLevel: CryptographicTrustLevel.none,
        issues: issues,
        metadata: const {'noReleaseAuthorization': 'true'},
      ),
      requirementResults: requirementResults,
      issues: issues,
    );
  }

  for (final requirement in policy.requirements) {
    final result = _evaluateRequirement(
      requirement: requirement,
      material: material,
      verificationResult: verificationResult,
      policyId: policy.policyId,
    );
    requirementResults[requirement.requirementId] = result.status;
    issues.addAll(result.issues);
    if (result.satisfied) {
      satisfied.add(requirement.requirementId);
    }
  }

  final requiredFailures = policy.requirements
      .where((r) => r.required)
      .where(
        (r) =>
            requirementResults[r.requirementId] !=
            CryptographicVerificationStatus.verified,
      )
      .length;

  final hasCritical = issues.any(
    (i) => i.severity == CryptographicIssueSeverity.critical,
  );

  final status = hasCritical
      ? CryptographicVerificationStatus.invalid
      : requiredFailures == 0
          ? CryptographicVerificationStatus.verified
          : requiredFailures <
                  policy.requirements.where((r) => r.required).length
              ? CryptographicVerificationStatus.partiallyVerified
              : CryptographicVerificationStatus.unverified;

  final trustLevel = _deriveTrustLevel(
    status: status,
    policy: policy,
    satisfiedCount: satisfied.length,
  );

  return CryptographicTrustPolicyEvaluationResult(
    policyResult: CryptographicPolicyVerificationResult(
      policyId: policy.policyId,
      status: status,
      trustLevel: trustLevel,
      satisfiedRequirementIds: satisfied,
      issues: issues,
      metadata: const {
        'noReleaseAuthorization': 'true',
        'candidateExplicitOnly': 'true',
      },
    ),
    requirementResults: requirementResults,
    issues: issues,
  );
}

class _RequirementEvaluation {
  const _RequirementEvaluation({
    required this.status,
    required this.satisfied,
    this.issues = const [],
  });

  final CryptographicVerificationStatus status;
  final bool satisfied;
  final List<CryptographicVerificationIssue> issues;
}

_RequirementEvaluation _evaluateRequirement({
  required CryptographicTrustRequirement requirement,
  required CollectedCryptographicTrustMaterial material,
  required CryptographicVerificationResult? verificationResult,
  required String policyId,
}) {
  final issues = <CryptographicVerificationIssue>[];

  switch (requirement.requirementType) {
    case CryptographicRequirementType.signature:
      final signatureCount = material.signatures.length;
      final requiredCount = requirement.requiredSignatureCount ?? 1;
      if (signatureCount < requiredCount) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_REQ_SIGNATURE_COUNT',
            severity: requirement.required
                ? CryptographicIssueSeverity.critical
                : CryptographicIssueSeverity.warning,
            path: 'requirements.${requirement.requirementId}',
            message:
                'Insufficient signatures: expected $requiredCount, found $signatureCount',
            policyId: policyId,
          ),
        );
      }
      if (requirement.requireTrustAnchor &&
          material.signatures.any((s) => s.trustAnchorReference == null)) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_REQ_TRUST_ANCHOR',
            severity: CryptographicIssueSeverity.warning,
            path: 'requirements.${requirement.requirementId}',
            message: 'Trust anchor required but missing on signature',
            policyId: policyId,
          ),
        );
      }
      final verifiedSignatures = verificationResult?.signatureResults
              .where(
                (r) => r.status == CryptographicVerificationStatus.verified,
              )
              .length ??
          0;
      final satisfied = signatureCount >= requiredCount &&
          (!requirement.required ||
              verifiedSignatures > 0 ||
              verificationResult == null);
      return _RequirementEvaluation(
        status: satisfied
            ? CryptographicVerificationStatus.verified
            : CryptographicVerificationStatus.unverified,
        satisfied: satisfied,
        issues: issues,
      );

    case CryptographicRequirementType.digest:
      final satisfied = material.digests.isNotEmpty;
      if (!satisfied && requirement.required) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_REQ_DIGEST_MISSING',
            severity: CryptographicIssueSeverity.critical,
            path: 'requirements.${requirement.requirementId}',
            message: 'Required digest not present in collected material',
            policyId: policyId,
          ),
        );
      }
      return _RequirementEvaluation(
        status: satisfied
            ? CryptographicVerificationStatus.verified
            : CryptographicVerificationStatus.unverified,
        satisfied: satisfied,
        issues: issues,
      );

    case CryptographicRequirementType.attestation:
      final matching = material.attestations.where(
        (a) =>
            requirement.requiredAttestationTypes.isEmpty ||
            requirement.requiredAttestationTypes.contains(a.attestationType),
      );
      final satisfied = matching.isNotEmpty;
      if (!satisfied && requirement.required) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_REQ_ATTESTATION_MISSING',
            severity: CryptographicIssueSeverity.critical,
            path: 'requirements.${requirement.requirementId}',
            message: 'Required attestation type not present',
            policyId: policyId,
          ),
        );
      }
      return _RequirementEvaluation(
        status: satisfied
            ? CryptographicVerificationStatus.verified
            : CryptographicVerificationStatus.unverified,
        satisfied: satisfied,
        issues: issues,
      );

    case CryptographicRequirementType.transparencyLog:
      final satisfied = material.transparencyLogReferences.isNotEmpty;
      if (requirement.requireTransparencyLog && !satisfied) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_REQ_TRANSPARENCY_MISSING',
            severity: requirement.required
                ? CryptographicIssueSeverity.critical
                : CryptographicIssueSeverity.warning,
            path: 'requirements.${requirement.requirementId}',
            message: 'Transparency log reference required but missing',
            policyId: policyId,
          ),
        );
      }
      return _RequirementEvaluation(
        status: satisfied
            ? CryptographicVerificationStatus.verified
            : CryptographicVerificationStatus.unverified,
        satisfied: satisfied || !requirement.required,
        issues: issues,
      );

    default:
      return _RequirementEvaluation(
        status: CryptographicVerificationStatus.unknown,
        satisfied: !requirement.required,
        issues: issues,
      );
  }
}

CryptographicTrustLevel _deriveTrustLevel({
  required CryptographicVerificationStatus status,
  required CryptographicTrustPolicy policy,
  required int satisfiedCount,
}) {
  if (status == CryptographicVerificationStatus.invalid ||
      status == CryptographicVerificationStatus.unverified) {
    return CryptographicTrustLevel.none;
  }
  final minimum = policy.requirements
      .map((r) => r.minimumTrustLevel)
      .whereType<CryptographicTrustLevel>()
      .fold<CryptographicTrustLevel?>(
        null,
        (prev, level) =>
            prev == null || _levelRank(level) < _levelRank(prev) ? level : prev,
      );
  if (status == CryptographicVerificationStatus.verified) {
    return minimum ?? CryptographicTrustLevel.moderate;
  }
  if (status == CryptographicVerificationStatus.partiallyVerified) {
    return satisfiedCount > 0
        ? CryptographicTrustLevel.low
        : CryptographicTrustLevel.none;
  }
  return CryptographicTrustLevel.none;
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
