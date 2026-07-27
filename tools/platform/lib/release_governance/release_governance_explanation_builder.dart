import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_rule_value.dart';

/// Builds deterministic explanations from versioned templates.
class ReleaseGovernanceExplanationBuilder {
  const ReleaseGovernanceExplanationBuilder();

  ReleaseGovernanceExplanation buildRuleExplanation({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernanceRuleStatus status,
    ReleaseGovernanceRuleValue? actualValue,
    ReleaseGovernanceRuleValue? expectedValue,
    String? operatorMessage,
  }) {
    final actualText = _formatValue(actualValue);
    final expectedText = _formatValue(expectedValue ?? rule.expectedValue);

    final (type, summary, detail) = switch (status) {
      ReleaseGovernanceRuleStatus.passed => (
          ReleaseGovernanceExplanationType.rulePassed,
          'Rule ${rule.ruleId} passed',
          'Rule "${rule.name}" passed for target ${rule.target.wireName}.',
        ),
      ReleaseGovernanceRuleStatus.failed => (
          ReleaseGovernanceExplanationType.ruleFailed,
          'Rule ${rule.ruleId} failed',
          'Rule "${rule.name}" failed for target ${rule.target.wireName}.',
        ),
      ReleaseGovernanceRuleStatus.pending => (
          ReleaseGovernanceExplanationType.rulePending,
          'Rule ${rule.ruleId} pending',
          'Rule "${rule.name}" is pending for target ${rule.target.wireName}.',
        ),
      ReleaseGovernanceRuleStatus.waived => (
          ReleaseGovernanceExplanationType.ruleWaived,
          'Rule ${rule.ruleId} waived',
          'Rule "${rule.name}" was waived for target ${rule.target.wireName}.',
        ),
      ReleaseGovernanceRuleStatus.conditionallySatisfied => (
          ReleaseGovernanceExplanationType.ruleConditional,
          'Rule ${rule.ruleId} conditionally satisfied',
          'Rule "${rule.name}" is conditionally satisfied.',
        ),
      ReleaseGovernanceRuleStatus.unavailable => (
          ReleaseGovernanceExplanationType.decisionUnavailable,
          'Rule ${rule.ruleId} unavailable',
          'Required evidence for "${rule.name}" was unavailable.',
        ),
      ReleaseGovernanceRuleStatus.incompatible => (
          ReleaseGovernanceExplanationType.compatibility,
          'Rule ${rule.ruleId} incompatible',
          'Evidence for "${rule.name}" is incompatible.',
        ),
      ReleaseGovernanceRuleStatus.skipped => (
          ReleaseGovernanceExplanationType.rulePassed,
          'Rule ${rule.ruleId} skipped',
          'Rule "${rule.name}" was skipped.',
        ),
      ReleaseGovernanceRuleStatus.notApplicable => (
          ReleaseGovernanceExplanationType.rulePassed,
          'Rule ${rule.ruleId} not applicable',
          'Rule "${rule.name}" is not applicable.',
        ),
      ReleaseGovernanceRuleStatus.expired => (
          ReleaseGovernanceExplanationType.decisionExpired,
          'Rule ${rule.ruleId} expired',
          'Rule "${rule.name}" evidence is expired.',
        ),
      ReleaseGovernanceRuleStatus.error => (
          ReleaseGovernanceExplanationType.decisionError,
          'Rule ${rule.ruleId} error',
          operatorMessage ??
              'Rule ${rule.ruleId} encountered an internal evaluation error.',
        ),
    };

    return ReleaseGovernanceExplanation(
      explanationId: 'rgx:${rule.ruleId}:${status.wireName}',
      type: type,
      summary: summary,
      detail: detail,
      templateId: 'rule.${status.wireName}',
      ruleExplanation:
          'Rule ${rule.ruleId}: observed $actualText vs expected $expectedText.',
      decisionExplanation:
          'Decision impact determined by severity and requirement.',
      evidenceExplanation:
          'Evidence derived from published artifacts for ${rule.target.wireName}.',
      impactExplanation: operatorMessage,
      parameters: {
        'ruleId': rule.ruleId,
        'target': rule.target.wireName,
        'operator': rule.operator.wireName,
        'status': status.wireName,
        if (actualText != null) 'actualValue': actualText,
        if (expectedText != null) 'expectedValue': expectedText,
      },
    );
  }

  ReleaseGovernanceExplanation buildDecisionExplanation({
    required ReleaseGovernanceDecision decision,
    required String policyId,
    required int policyVersion,
    int failedRuleCount = 0,
    int blockingFailureCount = 0,
  }) {
    final (type, summary, detail, templateId) = switch (decision) {
      ReleaseGovernanceDecision.approved => (
          ReleaseGovernanceExplanationType.decisionApproved,
          'Release approved',
          'All mandatory rules satisfied for policy $policyId v$policyVersion.',
          'decisionApproved',
        ),
      ReleaseGovernanceDecision.approvedWithConditions => (
          ReleaseGovernanceExplanationType.decisionApprovedWithConditions,
          'Release approved with conditions',
          'Policy $policyId v$policyVersion approved with compensating conditions.',
          'decisionApprovedWithConditions',
        ),
      ReleaseGovernanceDecision.rejected => (
          ReleaseGovernanceExplanationType.decisionRejected,
          'Release rejected',
          'Policy $policyId v$policyVersion rejected with $failedRuleCount failed rules.',
          'decisionRejected',
        ),
      ReleaseGovernanceDecision.pending => (
          ReleaseGovernanceExplanationType.decisionPending,
          'Release pending',
          'Policy $policyId v$policyVersion is pending additional approvals or evidence.',
          'decisionPending',
        ),
      ReleaseGovernanceDecision.unavailable => (
          ReleaseGovernanceExplanationType.decisionUnavailable,
          'Release unavailable',
          'Policy $policyId v$policyVersion could not be fully evaluated.',
          'decisionUnavailable',
        ),
      ReleaseGovernanceDecision.incompatible => (
          ReleaseGovernanceExplanationType.decisionIncompatible,
          'Release incompatible',
          'Policy $policyId v$policyVersion found incompatible source artifacts.',
          'decisionIncompatible',
        ),
      ReleaseGovernanceDecision.expired => (
          ReleaseGovernanceExplanationType.decisionExpired,
          'Release expired',
          'Policy $policyId v$policyVersion evaluation expired.',
          'decisionExpired',
        ),
      ReleaseGovernanceDecision.cancelled => (
          ReleaseGovernanceExplanationType.decisionRejected,
          'Release cancelled',
          'Release evaluation was cancelled.',
          'decisionCancelled',
        ),
      ReleaseGovernanceDecision.error => (
          ReleaseGovernanceExplanationType.decisionError,
          'Release error',
          'Policy $policyId v$policyVersion encountered an internal error.',
          'decisionError',
        ),
    };

    return ReleaseGovernanceExplanation(
      explanationId: 'rgd:$policyId:$policyVersion:${decision.wireName}',
      type: type,
      summary: summary,
      detail: detail,
      templateId: templateId,
      ruleExplanation: 'Aggregated from individual rule evaluations.',
      decisionExplanation: detail,
      evidenceExplanation: 'Based on published artifact evidence only.',
      impactExplanation:
          'Blocking failures: $blockingFailureCount; failed rules: $failedRuleCount.',
      parameters: {
        'policyId': policyId,
        'policyVersion': policyVersion.toString(),
        'decision': decision.wireName,
        'failedRuleCount': failedRuleCount.toString(),
        'blockingFailureCount': blockingFailureCount.toString(),
      },
    );
  }

  String? _formatValue(ReleaseGovernanceRuleValue? value) {
    if (value == null) return null;
    return switch (value) {
      ReleaseGovernanceBooleanValue(:final value) => value.toString(),
      ReleaseGovernanceIntegerValue(:final value) => value.toString(),
      ReleaseGovernanceDecimalValue(:final value) => value.toString(),
      ReleaseGovernancePercentageValue(:final value) => '$value%',
      ReleaseGovernanceStringValue(:final value) => value,
      ReleaseGovernanceEnumValue(:final domain, :final value) =>
        '$domain:$value',
      ReleaseGovernanceRangeValue(:final lower, :final upper) =>
        '[$lower,$upper]',
      ReleaseGovernanceSetValue(:final values) => values.join(','),
      ReleaseGovernanceDurationValue(:final iso8601Duration) => iso8601Duration,
      ReleaseGovernanceVersionValue(:final value) => value,
      ReleaseGovernanceArtifactReferenceValue(:final artifactId) => artifactId,
      ReleaseGovernanceDecisionValue(:final decision) => decision.wireName,
      ReleaseGovernanceDateTimeValue(:final value) => value,
      ReleaseGovernanceRuleValue() => null,
    };
  }
}
