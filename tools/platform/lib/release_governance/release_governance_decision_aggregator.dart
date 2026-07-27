import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';

/// Aggregates final release governance decision with explicit precedence.
class ReleaseGovernanceDecisionAggregator {
  const ReleaseGovernanceDecisionAggregator();

  ReleaseGovernanceDecision aggregate({
    required ReleaseGovernanceDecisionPolicy decisionPolicy,
    required ReleaseGovernanceCompatibility compatibility,
    required ReleaseGovernanceEligibility eligibility,
    required ReleaseGovernanceCoverage coverage,
    required List<ReleaseGovernanceEvaluation> evaluations,
    required List<ReleaseApprovalEvaluation> approvalEvaluations,
    required List<ReleaseWaiverEvaluation> waiverEvaluations,
    required List<ReleaseCondition> conditions,
    required List<ReleaseGovernanceError> errors,
  }) {
    if (errors.any((e) => !e.recoverable)) {
      return ReleaseGovernanceDecision.error;
    }
    if (evaluations.any(
      (e) => e.decisionImpact == ReleaseGovernanceDecisionImpact.internalError,
    )) {
      return ReleaseGovernanceDecision.error;
    }

    if (!decisionPolicy.partialCompatibilityAllowed &&
        compatibility.status ==
            ReleaseGovernanceCompatibilityStatus.incompatible) {
      return ReleaseGovernanceDecision.incompatible;
    }

    if (decisionPolicy.rejectedApprovalRejects &&
        approvalEvaluations.any(
          (a) => a.status == ReleaseApprovalEvaluationStatus.rejected,
        )) {
      return ReleaseGovernanceDecision.rejected;
    }

    if (decisionPolicy.missingApprovalsCreatePending &&
        approvalEvaluations.any(
          (a) =>
              a.status == ReleaseApprovalEvaluationStatus.missing ||
              a.status == ReleaseApprovalEvaluationStatus.partiallySatisfied,
        )) {
      return ReleaseGovernanceDecision.pending;
    }

    if (decisionPolicy.expiredApprovalCreatesPending &&
        approvalEvaluations.any(
          (a) => a.status == ReleaseApprovalEvaluationStatus.expired,
        )) {
      return ReleaseGovernanceDecision.pending;
    }

    if (eligibility.status == ReleaseGovernanceEligibilityStatus.ineligible &&
        eligibility.missingSources.isNotEmpty) {
      return ReleaseGovernanceDecision.unavailable;
    }

    if (decisionPolicy.criticalFailuresReject &&
        evaluations.any(
          (e) =>
              e.status == ReleaseGovernanceRuleStatus.failed &&
              e.decisionImpact ==
                  ReleaseGovernanceDecisionImpact.causesRejection,
        )) {
      return ReleaseGovernanceDecision.rejected;
    }

    if (decisionPolicy.blockingFailuresReject &&
        evaluations.any(
          (e) =>
              e.status == ReleaseGovernanceRuleStatus.failed &&
              e.decisionImpact ==
                  ReleaseGovernanceDecisionImpact.blocksApproval,
        )) {
      return ReleaseGovernanceDecision.rejected;
    }

    if (decisionPolicy.requiredFailuresReject &&
        _hasRequiredFailure(evaluations)) {
      return ReleaseGovernanceDecision.rejected;
    }

    if (coverage.requiredRuleCoveragePercentage <
        decisionPolicy.minimumRuleCoverage) {
      return ReleaseGovernanceDecision.unavailable;
    }

    if (coverage.approvalCoveragePercentage <
        decisionPolicy.minimumApprovalCoverage) {
      return decisionPolicy.missingApprovalsCreatePending
          ? ReleaseGovernanceDecision.pending
          : ReleaseGovernanceDecision.rejected;
    }

    if (conditions.isNotEmpty ||
        evaluations.any(
          (e) =>
              e.status == ReleaseGovernanceRuleStatus.waived ||
              e.decisionImpact ==
                  ReleaseGovernanceDecisionImpact.contributesToConditions,
        )) {
      return ReleaseGovernanceDecision.approvedWithConditions;
    }

    if (decisionPolicy.warningMayCreateCondition &&
        evaluations.any(
          (e) =>
              e.status == ReleaseGovernanceRuleStatus.failed &&
              e.decisionImpact == ReleaseGovernanceDecisionImpact.advisory,
        )) {
      return ReleaseGovernanceDecision.approvedWithConditions;
    }

    if (evaluations.any(
      (e) =>
          e.decisionImpact ==
          ReleaseGovernanceDecisionImpact.contributesToPending,
    )) {
      return ReleaseGovernanceDecision.pending;
    }

    if (evaluations.any(
      (e) =>
          e.decisionImpact == ReleaseGovernanceDecisionImpact.causesUnavailable,
    )) {
      return ReleaseGovernanceDecision.unavailable;
    }

    if (evaluations.any(
      (e) =>
          e.decisionImpact ==
          ReleaseGovernanceDecisionImpact.causesIncompatible,
    )) {
      return ReleaseGovernanceDecision.incompatible;
    }

    return ReleaseGovernanceDecision.approved;
  }

  bool _hasRequiredFailure(List<ReleaseGovernanceEvaluation> evaluations) {
    return evaluations.any(
      (e) =>
          e.status == ReleaseGovernanceRuleStatus.failed &&
          (e.decisionImpact == ReleaseGovernanceDecisionImpact.blocksApproval ||
              e.decisionImpact ==
                  ReleaseGovernanceDecisionImpact.causesRejection),
    );
  }
}
