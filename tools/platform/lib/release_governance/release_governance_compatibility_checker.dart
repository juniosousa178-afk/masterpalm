import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Checks structural compatibility between policy, request and sources.
class ReleaseGovernanceCompatibilityChecker {
  const ReleaseGovernanceCompatibilityChecker({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  ReleaseGovernanceCompatibility check({
    required ReleaseGovernanceRequest request,
    required ReleaseGovernancePolicy policy,
    required ResolvedReleaseGovernanceSources sources,
  }) {
    final checks = <ReleaseGovernanceCompatibilityCheck>[];
    final reasons = <String>[];
    final compatible = <ReleaseGovernanceSourceType>[];
    final partiallyCompatible = <ReleaseGovernanceSourceType>[];
    final incompatible = <ReleaseGovernanceSourceType>[];
    final unknown = <ReleaseGovernanceSourceType>[];

    if (policy.metadata.schemaVersion >
        ReleaseGovernancePolicy.currentSchemaVersion) {
      reasons.add('Unsupported policy schema version');
      checks.add(
        const ReleaseGovernanceCompatibilityCheck(
          checkId: 'policy-schema-unsupported',
          checkType: 'policy',
          status: ReleaseGovernanceCompatibilityStatus.incompatible,
        ),
      );
    }

    if (policy.metadata.status == ReleaseGovernancePolicyStatus.retired &&
        !request.historicalEvaluation) {
      reasons.add('Policy is retired');
      checks.add(
        const ReleaseGovernanceCompatibilityCheck(
          checkId: 'policy-retired',
          checkType: 'policy',
          status: ReleaseGovernanceCompatibilityStatus.incompatible,
        ),
      );
    }

    final compatPolicy = policy.compatibilityPolicy;
    if (compatPolicy.requireSameProject &&
        sources.qualityGateSnapshot.isAvailable) {
      final qgProject =
          sources.qualityGateSnapshot.resolvedArtifact!.metadata.projectId;
      if (qgProject != request.releaseContext.projectId) {
        reasons.add('Quality gate project mismatch');
        checks.add(
          ReleaseGovernanceCompatibilityCheck(
            checkId: 'qg-project-mismatch',
            checkType: 'project',
            status: ReleaseGovernanceCompatibilityStatus.incompatible,
            expected: request.releaseContext.projectId,
            actual: qgProject,
          ),
        );
      }
    }

    if (compatPolicy.requireSameCommit &&
        sources.qualityGateSnapshot.isAvailable) {
      final qgCommit =
          sources.qualityGateSnapshot.resolvedArtifact!.metadata.commitId;
      if (qgCommit != null &&
          qgCommit.isNotEmpty &&
          qgCommit != request.releaseContext.commitId) {
        reasons.add('Quality gate commit mismatch');
        checks.add(
          ReleaseGovernanceCompatibilityCheck(
            checkId: 'qg-commit-mismatch',
            checkType: 'commit',
            status: ReleaseGovernanceCompatibilityStatus.incompatible,
            expected: request.releaseContext.commitId,
            actual: qgCommit,
          ),
        );
      }
    }

    if (compatPolicy.requireQualityGatePolicyCompatibility &&
        sources.qualityGateSnapshot.isAvailable) {
      final qgPolicyId =
          sources.qualityGateSnapshot.resolvedArtifact!.metadata.policyId;
      if (compatPolicy.allowedQualityGatePolicyIds.isNotEmpty &&
          !compatPolicy.allowedQualityGatePolicyIds.contains(qgPolicyId)) {
        reasons.add('Quality gate policy not allowed');
        checks.add(
          ReleaseGovernanceCompatibilityCheck(
            checkId: 'qg-policy-id',
            checkType: 'qualityGatePolicy',
            status: ReleaseGovernanceCompatibilityStatus.incompatible,
            actual: qgPolicyId,
          ),
        );
      }
    }

    for (final ref in sources.sourceReferences) {
      switch (ref.compatibility) {
        case ReleaseGovernanceCompatibilityStatus.compatible:
          compatible.add(ref.sourceType);
        case ReleaseGovernanceCompatibilityStatus.partiallyCompatible:
          partiallyCompatible.add(ref.sourceType);
        case ReleaseGovernanceCompatibilityStatus.incompatible:
          incompatible.add(ref.sourceType);
          reasons.add('Incompatible source ${ref.sourceType.wireName}');
        case ReleaseGovernanceCompatibilityStatus.unknown:
          unknown.add(ref.sourceType);
      }
    }

    for (final hint in sources.compatibilityHints) {
      reasons.add(hint);
      checks.add(
        ReleaseGovernanceCompatibilityCheck(
          checkId: 'compatibility-hint',
          checkType: 'hint',
          status: ReleaseGovernanceCompatibilityStatus.partiallyCompatible,
          reasons: [hint],
        ),
      );
    }

    if (request.strictCompatibility && incompatible.isNotEmpty) {
      return _result(
        status: ReleaseGovernanceCompatibilityStatus.incompatible,
        checks: checks,
        compatible: compatible,
        partiallyCompatible: partiallyCompatible,
        incompatible: incompatible,
        unknown: unknown,
        reasons: reasons,
      );
    }

    final status = incompatible.isNotEmpty
        ? ReleaseGovernanceCompatibilityStatus.incompatible
        : partiallyCompatible.isNotEmpty || unknown.isNotEmpty
            ? ReleaseGovernanceCompatibilityStatus.partiallyCompatible
            : compatible.isNotEmpty
                ? ReleaseGovernanceCompatibilityStatus.compatible
                : ReleaseGovernanceCompatibilityStatus.unknown;

    return _result(
      status: status,
      checks: checks,
      compatible: compatible,
      partiallyCompatible: partiallyCompatible,
      incompatible: incompatible,
      unknown: unknown,
      reasons: reasons,
    );
  }

  ReleaseGovernanceCompatibility _result({
    required ReleaseGovernanceCompatibilityStatus status,
    required List<ReleaseGovernanceCompatibilityCheck> checks,
    required List<ReleaseGovernanceSourceType> compatible,
    required List<ReleaseGovernanceSourceType> partiallyCompatible,
    required List<ReleaseGovernanceSourceType> incompatible,
    required List<ReleaseGovernanceSourceType> unknown,
    required List<String> reasons,
  }) {
    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'checks': checks.map((c) => c.checkId).toList()..sort(),
        'compatible': compatible.map((e) => e.wireName).toList()..sort(),
        'incompatible': incompatible.map((e) => e.wireName).toList()..sort(),
      }.toString(),
    );
    return ReleaseGovernanceCompatibility(
      status: status,
      checks: checks..sort((a, b) => a.checkId.compareTo(b.checkId)),
      compatibleSources: compatible,
      partiallyCompatibleSources: partiallyCompatible,
      incompatibleSources: incompatible,
      unknownSources: unknown,
      reasons: reasons,
      compatibilityFingerprint: fingerprint,
    );
  }
}
