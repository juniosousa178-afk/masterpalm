import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import 'release_governance_canonical_serializer.dart';

/// Builds release conditions from evaluations, approvals and waivers.
class ReleaseGovernanceConditionBuilder {
  const ReleaseGovernanceConditionBuilder({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  List<ReleaseCondition> build({
    required ReleaseGovernancePolicy policy,
    required List<ReleaseGovernanceEvaluation> evaluations,
    required List<ReleaseApprovalEvaluation> approvalEvaluations,
    required List<ReleaseWaiverEvaluation> waiverEvaluations,
    required String referenceTime,
  }) {
    final conditions = <ReleaseCondition>[];

    for (final evaluation in evaluations) {
      if (evaluation.status == ReleaseGovernanceRuleStatus.failed &&
          evaluation.decisionImpact ==
              ReleaseGovernanceDecisionImpact.contributesToConditions) {
        conditions.add(
          _condition(
            id: 'cond:rule:${evaluation.ruleId}',
            type: ReleaseConditionType.followUp,
            description: 'Resolve failed rule ${evaluation.ruleId}',
            owner: policy.governance.policyOwner,
            severity: ReleaseGovernanceRuleSeverity.blocking,
            sourceRuleId: evaluation.ruleId,
          ),
        );
      }
    }

    for (final approval in approvalEvaluations) {
      if (approval.status == ReleaseApprovalEvaluationStatus.expired) {
        conditions.add(
          _condition(
            id: 'cond:approval:${approval.requirementId}',
            type: ReleaseConditionType.manualVerification,
            description:
                'Renew expired approval for ${approval.approvalType.wireName}',
            owner: policy.governance.releaseApprovalAuthority ??
                policy.governance.policyOwner,
            severity: ReleaseGovernanceRuleSeverity.blocking,
            sourceApprovalRequirementId: approval.requirementId,
          ),
        );
      }
    }

    for (final waiver in waiverEvaluations) {
      if (waiver.status == ReleaseWaiverStatus.active &&
          policy.decisionPolicy.validWaiverMayCreateConditionalApproval) {
        conditions.add(
          _condition(
            id: 'cond:waiver:${waiver.waiverId}',
            type: ReleaseConditionType.compensatingControl,
            description:
                'Satisfy compensating controls for waiver ${waiver.waiverId}',
            owner: policy.governance.waiverGrantAuthority ??
                policy.governance.policyOwner,
            severity: ReleaseGovernanceRuleSeverity.warning,
            sourceWaiverId: waiver.waiverId,
          ),
        );
      }
    }

    conditions.sort((a, b) => a.conditionId.compareTo(b.conditionId));
    return conditions;
  }

  ReleaseCondition _condition({
    required String id,
    required ReleaseConditionType type,
    required String description,
    required String owner,
    required ReleaseGovernanceRuleSeverity severity,
    String? sourceRuleId,
    String? sourceWaiverId,
    String? sourceApprovalRequirementId,
  }) {
    final body = ReleaseCondition(
      conditionId: id,
      type: type,
      description: description,
      owner: owner,
      severity: severity,
      status: ReleaseConditionStatus.open,
      evidenceRequired: true,
      sourceRuleId: sourceRuleId,
      sourceWaiverId: sourceWaiverId,
      sourceApprovalRequirementId: sourceApprovalRequirementId,
      fingerprint: '',
    );
    return ReleaseCondition(
      conditionId: body.conditionId,
      type: body.type,
      description: body.description,
      owner: body.owner,
      severity: body.severity,
      status: body.status,
      evidenceRequired: body.evidenceRequired,
      sourceRuleId: body.sourceRuleId,
      sourceWaiverId: body.sourceWaiverId,
      sourceApprovalRequirementId: body.sourceApprovalRequirementId,
      fingerprint: _serializer.conditionFingerprint(body),
    );
  }
}
