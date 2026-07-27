import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Evaluates whether a policy can be applied to the current context.
class ReleaseGovernanceEligibilityEvaluator {
  const ReleaseGovernanceEligibilityEvaluator({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  ReleaseGovernanceEligibility evaluate({
    required ReleaseGovernanceRequest request,
    required ReleaseGovernancePolicy policy,
    required ResolvedReleaseGovernanceSources sources,
    required ReleaseGovernanceCompatibility compatibility,
    required List<ReleaseGovernanceRule> enabledRules,
  }) {
    final reasons = <String>[];
    final missingSources = <ReleaseGovernanceSourceType>[];
    final incompatibleSources = compatibility.incompatibleSources;

    if (policy.eligibilityPolicy.requireReleaseContext &&
        !sources.releaseContext.isAvailable) {
      missingSources.add(ReleaseGovernanceSourceType.releaseContext);
      reasons.add('Missing release context');
    }

    if (policy.eligibilityPolicy.requireQualityGate &&
        !sources.qualityGateSnapshot.isAvailable) {
      missingSources.add(ReleaseGovernanceSourceType.qualityGateSnapshot);
      reasons.add('Missing quality gate snapshot');
    }

    if (policy.eligibilityPolicy.requireApprovalsForEvaluation &&
        !sources.approvalSet.isAvailable) {
      missingSources.add(ReleaseGovernanceSourceType.approvalSet);
      reasons.add('Missing approval set');
    }

    if (policy.eligibilityPolicy.requireWaiversForEvaluation &&
        !sources.waiverSet.isAvailable) {
      missingSources.add(ReleaseGovernanceSourceType.waiverSet);
      reasons.add('Missing waiver set');
    }

    if (policy.metadata.status == ReleaseGovernancePolicyStatus.retired &&
        !request.historicalEvaluation) {
      reasons.add('Policy retired for normal evaluation');
    }

    if (enabledRules.length <
        policy.eligibilityPolicy.minimumNormativeRuleCount) {
      reasons.add('Insufficient enabled normative rules');
    }

    final status = _deriveStatus(
      reasons: reasons,
      missingSources: missingSources,
      incompatibleSources: incompatibleSources,
      compatibility: compatibility,
      enabledRules: enabledRules,
      policy: policy,
    );

    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'missing': missingSources.map((e) => e.wireName).toList()..sort(),
        'incompatible': incompatibleSources.map((e) => e.wireName).toList()
          ..sort(),
      }.toString(),
    );

    return ReleaseGovernanceEligibility(
      status: status,
      reasons: reasons,
      missingSources: missingSources,
      incompatibleSources: incompatibleSources,
      eligibilityFingerprint: fingerprint,
    );
  }

  ReleaseGovernanceEligibilityStatus _deriveStatus({
    required List<String> reasons,
    required List<ReleaseGovernanceSourceType> missingSources,
    required List<ReleaseGovernanceSourceType> incompatibleSources,
    required ReleaseGovernanceCompatibility compatibility,
    required List<ReleaseGovernanceRule> enabledRules,
    required ReleaseGovernancePolicy policy,
  }) {
    if (compatibility.status ==
            ReleaseGovernanceCompatibilityStatus.incompatible &&
        incompatibleSources.isNotEmpty) {
      return ReleaseGovernanceEligibilityStatus.ineligible;
    }
    if (missingSources.isNotEmpty) {
      return policy.eligibilityPolicy.allowPartialEligibility
          ? ReleaseGovernanceEligibilityStatus.partiallyEligible
          : ReleaseGovernanceEligibilityStatus.ineligible;
    }
    if (enabledRules.isEmpty) {
      return ReleaseGovernanceEligibilityStatus.ineligible;
    }
    if (reasons.isNotEmpty) {
      return ReleaseGovernanceEligibilityStatus.partiallyEligible;
    }
    return ReleaseGovernanceEligibilityStatus.eligible;
  }
}
