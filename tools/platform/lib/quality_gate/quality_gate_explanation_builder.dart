import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';

/// Builds deterministic explanations from versioned templates.
class QualityGateExplanationBuilder {
  const QualityGateExplanationBuilder();

  QualityGateExplanation buildRuleExplanation({
    required QualityGateRule rule,
    required QualityGateRuleStatus status,
    QualityGateRuleValue? actualValue,
    QualityGateRuleValue? expectedValue,
    String? operatorMessage,
  }) {
    final templateId = rule.explanationTemplateId;
    final actualText = _formatValue(actualValue);
    final expectedText = _formatValue(expectedValue ?? rule.expectedValue);

    final (summary, detail, ruleExplanation, impactExplanation) =
        switch (status) {
      QualityGateRuleStatus.passed => (
          'Rule ${rule.ruleId} passed',
          'Rule "${rule.name}" passed for target ${rule.target.wireName}.',
          'Rule ${rule.ruleId} passed. Observed value $actualText satisfies operator ${rule.operator.wireName}.',
          'No blocking impact.',
        ),
      QualityGateRuleStatus.failed => (
          'Rule ${rule.ruleId} failed',
          'Rule "${rule.name}" failed for target ${rule.target.wireName}.',
          'Rule ${rule.ruleId} failed. Observed value $actualText did not satisfy operator ${rule.operator.wireName} against expected $expectedText.',
          rule.severity == QualityGateRuleSeverity.critical ||
                  rule.severity == QualityGateRuleSeverity.blocking
              ? 'Failure may block approval.'
              : 'Failure contributes to gate outcome.',
        ),
      QualityGateRuleStatus.unavailable => (
          'Rule ${rule.ruleId} unavailable',
          'Required evidence for "${rule.name}" was unavailable.',
          'Rule ${rule.ruleId} could not be evaluated because target ${rule.target.wireName} is unavailable.',
          'Missing evidence may cause partial or unavailable gate decision.',
        ),
      QualityGateRuleStatus.incompatible => (
          'Rule ${rule.ruleId} incompatible',
          'Evidence for "${rule.name}" is incompatible with policy requirements.',
          'Rule ${rule.ruleId} found incompatible data for target ${rule.target.wireName}.',
          'Incompatible evidence may block structural approval.',
        ),
      QualityGateRuleStatus.skipped => (
          'Rule ${rule.ruleId} skipped',
          'Rule "${rule.name}" was skipped.',
          'Rule ${rule.ruleId} was skipped by policy or configuration.',
          'No impact on final decision.',
        ),
      QualityGateRuleStatus.notApplicable => (
          'Rule ${rule.ruleId} not applicable',
          'Rule "${rule.name}" is not applicable in this context.',
          'Rule ${rule.ruleId} does not apply to the current request context.',
          'No impact on final decision.',
        ),
      QualityGateRuleStatus.error => (
          'Rule ${rule.ruleId} error',
          'Rule "${rule.name}" encountered an internal evaluation error.',
          operatorMessage ??
              'Rule ${rule.ruleId} failed due to an internal evaluation error.',
          'Internal error may prevent reliable approval.',
        ),
    };

    return QualityGateExplanation(
      explanationId: 'qgx:${rule.ruleId}:${status.wireName}',
      summary: summary,
      detail: detail,
      ruleExplanation: ruleExplanation,
      decisionExplanation:
          'Decision impact determined by rule severity and requirement.',
      evidenceExplanation:
          'Evidence derived from published artifact values for ${rule.target.wireName}.',
      impactExplanation: impactExplanation,
      templateId: templateId,
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

  QualityGateExplanation buildDecisionExplanation({
    required QualityGateDecision decision,
    required String policyId,
    required int policyVersion,
    int failedRuleCount = 0,
    int blockingFailureCount = 0,
  }) {
    final (summary, detail, templateId) = switch (decision) {
      QualityGateDecision.passed => (
          'Quality gate passed',
          'All mandatory rules and rule sets passed for policy $policyId v$policyVersion.',
          'decisionPassed',
        ),
      QualityGateDecision.failed => (
          'Quality gate failed',
          'Policy $policyId v$policyVersion failed with $failedRuleCount failed rules and $blockingFailureCount blocking failures.',
          'decisionFailed',
        ),
      QualityGateDecision.partial => (
          'Quality gate partial',
          'Policy $policyId v$policyVersion completed with partial coverage or unavailable required evidence.',
          'decisionPartial',
        ),
      QualityGateDecision.unavailable => (
          'Quality gate unavailable',
          'Policy $policyId v$policyVersion could not be fully evaluated due to missing required sources or evidence.',
          'decisionUnavailable',
        ),
      QualityGateDecision.incompatible => (
          'Quality gate incompatible',
          'Policy $policyId v$policyVersion found incompatible source artifacts.',
          'decisionIncompatible',
        ),
      QualityGateDecision.error => (
          'Quality gate error',
          'Policy $policyId v$policyVersion encountered an internal evaluation error.',
          'decisionError',
        ),
    };

    return QualityGateExplanation(
      explanationId: 'qgd:$policyId:$policyVersion:${decision.wireName}',
      summary: summary,
      detail: detail,
      ruleExplanation: 'Aggregated from individual rule evaluations.',
      decisionExplanation: detail,
      evidenceExplanation: 'Based on published artifact evidence only.',
      impactExplanation: 'Final gate decision for release approval.',
      templateId: templateId,
      parameters: {
        'policyId': policyId,
        'policyVersion': policyVersion.toString(),
        'decision': decision.wireName,
        'failedRuleCount': failedRuleCount.toString(),
        'blockingFailureCount': blockingFailureCount.toString(),
      },
    );
  }

  QualityGateExplanation buildRuleSetExplanation({
    required QualityGateRuleSet ruleSet,
    required QualityGateRuleStatus status,
    required int passedRuleCount,
    required int failedRuleCount,
  }) {
    return QualityGateExplanation(
      explanationId: 'qgrs:${ruleSet.ruleSetId}:${status.wireName}',
      summary: 'Rule set ${ruleSet.ruleSetId} ${status.wireName}',
      detail:
          'Rule set "${ruleSet.name}" aggregated $passedRuleCount passed and $failedRuleCount failed rules using ${ruleSet.aggregationMode.wireName}.',
      ruleExplanation: ruleSet.description,
      decisionExplanation: 'Rule set aggregation result: ${status.wireName}.',
      evidenceExplanation: 'Derived from member rule evaluations.',
      impactExplanation: ruleSet.required
          ? 'Required rule set influences final decision.'
          : 'Optional rule set provides advisory signal only.',
      templateId: 'ruleSet.${status.wireName}',
      parameters: {
        'ruleSetId': ruleSet.ruleSetId,
        'status': status.wireName,
        'passedRuleCount': passedRuleCount.toString(),
        'failedRuleCount': failedRuleCount.toString(),
      },
    );
  }

  String? _formatValue(QualityGateRuleValue? value) {
    if (value == null) return null;
    return switch (value) {
      QualityGateBooleanValue(:final value) => value.toString(),
      QualityGateIntegerValue(:final value) => value.toString(),
      QualityGateDecimalValue(:final value) => value.toString(),
      QualityGatePercentageValue(:final value) => '$value%',
      QualityGateStringValue(:final value) => value,
      QualityGateEnumValue(:final domain, :final value) => '$domain:$value',
      QualityGateRangeValue(:final lower, :final upper) => '[$lower,$upper]',
      QualityGateSetValue(:final values) => values.join(','),
      QualityGateVersionValue(:final major, :final minor, :final patch) =>
        '$major.$minor.$patch',
      QualityGateArtifactReferenceValue(:final artifactId) => artifactId,
      QualityGateRuleValue() => null,
    };
  }
}
