import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Calculates evaluation coverage from rule and approval outcomes.
class ReleaseGovernanceCoverageCalculator {
  const ReleaseGovernanceCoverageCalculator({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  ReleaseGovernanceCoverage calculate({
    required ReleaseGovernancePolicy policy,
    required List<ReleaseGovernanceEvaluation> evaluations,
    required List<ReleaseApprovalEvaluation> approvalEvaluations,
    required List<ReleaseWaiverEvaluation> waiverEvaluations,
    required List<ReleaseGovernanceEvidence> evidence,
    required ResolvedReleaseGovernanceSources sources,
  }) {
    final allRules = policy.rules;
    final enabledRules = allRules.where((r) => r.enabled).toList();
    final requiredRules = enabledRules
        .where(
            (r) => r.requirement == ReleaseGovernanceRuleRequirement.required)
        .toList();

    final passed = _count(evaluations, ReleaseGovernanceRuleStatus.passed);
    final failed = _count(evaluations, ReleaseGovernanceRuleStatus.failed);
    final pending = _count(evaluations, ReleaseGovernanceRuleStatus.pending);
    final waived = _count(evaluations, ReleaseGovernanceRuleStatus.waived);
    final unavailable =
        _count(evaluations, ReleaseGovernanceRuleStatus.unavailable);
    final incompatible =
        _count(evaluations, ReleaseGovernanceRuleStatus.incompatible);
    final evaluated = passed + failed + waived;

    final requiredEvaluated = evaluations
        .where(
          (e) =>
              requiredRules.any((r) => r.ruleId == e.ruleId) &&
              (e.status == ReleaseGovernanceRuleStatus.passed ||
                  e.status == ReleaseGovernanceRuleStatus.failed ||
                  e.status == ReleaseGovernanceRuleStatus.waived),
        )
        .length;

    final applicableApprovals = approvalEvaluations
        .where((a) => a.status != ReleaseApprovalEvaluationStatus.notApplicable)
        .toList();
    final satisfiedApprovals = applicableApprovals
        .where((a) => a.status == ReleaseApprovalEvaluationStatus.satisfied)
        .length;

    final validWaivers = waiverEvaluations
        .where(
          (w) =>
              w.status == ReleaseWaiverStatus.active ||
              w.status == ReleaseWaiverStatus.approved,
        )
        .length;

    final evidenceRequired = evaluations
        .where((e) =>
            e.evidenceIds.isNotEmpty ||
            e.status != ReleaseGovernanceRuleStatus.skipped)
        .length;
    final evidencePresent =
        evaluations.where((e) => e.evidenceIds.isNotEmpty).length;

    final sourceCoverage = sources.allSources.isEmpty
        ? 100.0
        : _percentage(
            sources.allSources.where((s) => s.isAvailable).length,
            sources.allSources.length,
          );

    final fingerprint = _serializer.fingerprintFromString(
      {
        'evaluated': evaluated,
        'required': requiredRules.length,
        'approvals': satisfiedApprovals,
        'waivers': validWaivers,
      }.toString(),
    );

    return ReleaseGovernanceCoverage(
      totalRuleCount: allRules.length,
      enabledRuleCount: enabledRules.length,
      evaluatedRuleCount: evaluated,
      passedRuleCount: passed,
      failedRuleCount: failed,
      pendingRuleCount: pending,
      waivedRuleCount: waived,
      unavailableRuleCount: unavailable,
      incompatibleRuleCount: incompatible,
      requiredRuleCount: requiredRules.length,
      requiredRuleEvaluatedCount: requiredEvaluated,
      approvalRequirementCount: applicableApprovals.length,
      approvalRequirementSatisfiedCount: satisfiedApprovals,
      waiverEvaluationCount: waiverEvaluations.length,
      validWaiverCount: validWaivers,
      evidenceRequiredCount: evidenceRequired,
      evidencePresentCount: evidencePresent,
      ruleCoveragePercentage: _percentage(evaluated, enabledRules.length),
      requiredRuleCoveragePercentage: _percentage(
        requiredEvaluated,
        requiredRules.length,
        zeroDefault: 100,
      ),
      approvalCoveragePercentage: _percentage(
        satisfiedApprovals,
        applicableApprovals.length,
        zeroDefault: 100,
      ),
      evidenceCoveragePercentage: _percentage(
        evidencePresent,
        evidenceRequired,
        zeroDefault: 100,
      ),
      sourceCoveragePercentage: sourceCoverage,
      fingerprint: fingerprint,
    );
  }

  int _count(
    List<ReleaseGovernanceEvaluation> evaluations,
    ReleaseGovernanceRuleStatus status,
  ) {
    return evaluations.where((e) => e.status == status).length;
  }

  double _percentage(int numerator, int denominator, {double zeroDefault = 0}) {
    if (denominator <= 0) return zeroDefault;
    final value = (numerator / denominator) * 100;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return double.parse(value.toStringAsFixed(2));
  }
}
