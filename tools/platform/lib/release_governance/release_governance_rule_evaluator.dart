import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import '../models/release_governance/release_governance_rule_value.dart';
import 'release_governance_canonical_serializer.dart';
import 'release_governance_evidence_builder.dart';
import 'release_governance_explanation_builder.dart';
import 'release_governance_handlers.dart';
import 'release_governance_operator_evaluator.dart';
import 'release_governance_target_registry.dart';
import 'resolved_release_governance_sources.dart';

/// Outcome of a single rule evaluation including evidence artifacts.
class ReleaseGovernanceRuleEvaluationOutcome {
  const ReleaseGovernanceRuleEvaluationOutcome({
    required this.evaluation,
    required this.evidence,
  });

  final ReleaseGovernanceEvaluation evaluation;
  final List<ReleaseGovernanceEvidence> evidence;
}

/// Evaluates a single release governance rule against resolved sources.
class ReleaseGovernanceRuleEvaluator {
  ReleaseGovernanceRuleEvaluator({
    ReleaseGovernanceTargetRegistry? targetRegistry,
    ReleaseGovernanceOperatorEvaluator? operatorEvaluator,
    ReleaseGovernanceMissingDataHandler? missingDataHandler,
    ReleaseGovernanceIncompatibleDataHandler? incompatibleDataHandler,
    ReleaseGovernanceDecisionImpactResolver? impactResolver,
    ReleaseGovernanceEvidenceBuilder? evidenceBuilder,
    ReleaseGovernanceExplanationBuilder? explanationBuilder,
    ReleaseGovernanceCanonicalSerializer? serializer,
  })  : _targetRegistry =
            targetRegistry ?? const ReleaseGovernanceTargetRegistry(),
        _operatorEvaluator =
            operatorEvaluator ?? const ReleaseGovernanceOperatorEvaluator(),
        _missingDataHandler =
            missingDataHandler ?? const ReleaseGovernanceMissingDataHandler(),
        _incompatibleDataHandler = incompatibleDataHandler ??
            const ReleaseGovernanceIncompatibleDataHandler(),
        _impactResolver =
            impactResolver ?? const ReleaseGovernanceDecisionImpactResolver(),
        _evidenceBuilder =
            evidenceBuilder ?? const ReleaseGovernanceEvidenceBuilder(),
        _explanationBuilder =
            explanationBuilder ?? const ReleaseGovernanceExplanationBuilder(),
        _serializer =
            serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceTargetRegistry _targetRegistry;
  final ReleaseGovernanceOperatorEvaluator _operatorEvaluator;
  final ReleaseGovernanceMissingDataHandler _missingDataHandler;
  final ReleaseGovernanceIncompatibleDataHandler _incompatibleDataHandler;
  final ReleaseGovernanceDecisionImpactResolver _impactResolver;
  final ReleaseGovernanceEvidenceBuilder _evidenceBuilder;
  final ReleaseGovernanceExplanationBuilder _explanationBuilder;
  final ReleaseGovernanceCanonicalSerializer _serializer;

  ReleaseGovernanceEvaluation evaluate({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernancePolicy policy,
    required ReleaseGovernanceRequest request,
    required ResolvedReleaseGovernanceSources sources,
    String? ruleSetId,
  }) {
    return evaluateOutcome(
      rule: rule,
      policy: policy,
      request: request,
      sources: sources,
      ruleSetId: ruleSetId,
    ).evaluation;
  }

  ReleaseGovernanceRuleEvaluationOutcome evaluateOutcome({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernancePolicy policy,
    required ReleaseGovernanceRequest request,
    required ResolvedReleaseGovernanceSources sources,
    String? ruleSetId,
  }) {
    if (!rule.enabled) {
      return _buildEvaluation(
        rule: rule,
        policy: policy,
        ruleSetId: ruleSetId ?? rule.ruleSetId,
        request: request,
        status: ReleaseGovernanceRuleStatus.skipped,
        decisionImpact: ReleaseGovernanceDecisionImpact.none,
        evidence: const [],
        explanation: _explanationBuilder.buildRuleExplanation(
          rule: rule,
          status: ReleaseGovernanceRuleStatus.skipped,
        ),
      );
    }

    final context = ReleaseGovernanceEvaluationContext(
      releaseContext: request.releaseContext,
      referenceTime: request.referenceTime,
      policy: policy,
      strictCompatibility: request.strictCompatibility,
    );

    final resolution = _targetRegistry.resolve(rule, sources, context);

    switch (resolution.status) {
      case ReleaseGovernanceTargetResolutionStatus.notApplicable:
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId ?? rule.ruleSetId,
          request: request,
          status: ReleaseGovernanceRuleStatus.notApplicable,
          decisionImpact: ReleaseGovernanceDecisionImpact.none,
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: ReleaseGovernanceRuleStatus.notApplicable,
            referenceTime: request.referenceTime,
            explanation: 'Target not applicable',
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: ReleaseGovernanceRuleStatus.notApplicable,
          ),
        );
      case ReleaseGovernanceTargetResolutionStatus.unavailable:
        final missing = _missingDataHandler.handle(rule);
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId ?? rule.ruleSetId,
          request: request,
          status: missing.status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: missing.status,
            decisionPolicy: policy.decisionPolicy,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: missing.status,
            referenceTime: request.referenceTime,
            explanation: 'Target unavailable',
            evidenceType: ReleaseGovernanceEvidenceType.unavailable,
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: missing.status,
          ),
        );
      case ReleaseGovernanceTargetResolutionStatus.incompatible:
        final incompatible = _incompatibleDataHandler.handle(rule);
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId ?? rule.ruleSetId,
          request: request,
          status: incompatible.status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: incompatible.status,
            decisionPolicy: policy.decisionPolicy,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: incompatible.status,
            referenceTime: request.referenceTime,
            explanation: 'Target incompatible',
            evidenceType: ReleaseGovernanceEvidenceType.incompatible,
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: incompatible.status,
          ),
        );
      case ReleaseGovernanceTargetResolutionStatus.unsupported:
      case ReleaseGovernanceTargetResolutionStatus.error:
        final status =
            rule.requirement == ReleaseGovernanceRuleRequirement.required
                ? ReleaseGovernanceRuleStatus.error
                : ReleaseGovernanceRuleStatus.unavailable;
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId ?? rule.ruleSetId,
          request: request,
          status: status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: status,
            decisionPolicy: policy.decisionPolicy,
            operatorTypeError: status == ReleaseGovernanceRuleStatus.error,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: status,
            referenceTime: request.referenceTime,
            explanation: 'Unsupported target',
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: status,
            operatorMessage: 'Unsupported target ${rule.target.wireName}',
          ),
        );
      case ReleaseGovernanceTargetResolutionStatus.resolved:
        final operatorResult = _operatorEvaluator.evaluate(
          operator: rule.operator,
          actualValue: resolution.actualValue,
          expectedValue: rule.expectedValue,
          referenceTime: request.referenceTime,
        );
        if (operatorResult.typeError) {
          final status = ReleaseGovernanceRuleStatus.error;
          return _buildEvaluation(
            rule: rule,
            policy: policy,
            ruleSetId: ruleSetId ?? rule.ruleSetId,
            request: request,
            status: status,
            decisionImpact: _impactResolver.resolve(
              rule: rule,
              status: status,
              decisionPolicy: policy.decisionPolicy,
              operatorTypeError: true,
            ),
            actualValue: resolution.actualValue,
            evidence: [
              _evidenceBuilder.build(
                rule: rule,
                resolution: resolution,
                observedStatus: status,
                referenceTime: request.referenceTime,
                explanation: operatorResult.message ?? 'Operator type error',
              ),
            ],
            explanation: _explanationBuilder.buildRuleExplanation(
              rule: rule,
              status: status,
              actualValue: resolution.actualValue,
              expectedValue: rule.expectedValue,
              operatorMessage: operatorResult.message,
            ),
          );
        }

        final status = operatorResult.passed
            ? ReleaseGovernanceRuleStatus.passed
            : ReleaseGovernanceRuleStatus.failed;
        final impact =
            rule.requirement == ReleaseGovernanceRuleRequirement.informational
                ? ReleaseGovernanceDecisionImpact.none
                : _impactResolver.resolve(
                    rule: rule,
                    status: status,
                    decisionPolicy: policy.decisionPolicy,
                  );
        final explanation = _explanationBuilder.buildRuleExplanation(
          rule: rule,
          status: status,
          actualValue: resolution.actualValue,
          expectedValue: rule.expectedValue,
          operatorMessage: operatorResult.message,
        );
        final evidence = [
          _evidenceBuilder.build(
            rule: rule,
            resolution: resolution,
            observedStatus: status,
            referenceTime: request.referenceTime,
            explanation: explanation.ruleExplanation ?? explanation.summary,
          ),
        ];
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId ?? rule.ruleSetId,
          request: request,
          status: status,
          decisionImpact: impact,
          actualValue: resolution.actualValue,
          evidence: evidence,
          explanation: explanation,
        );
    }
  }

  ReleaseGovernanceRuleEvaluationOutcome _buildEvaluation({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernancePolicy policy,
    required ReleaseGovernanceRequest request,
    required ReleaseGovernanceRuleStatus status,
    required ReleaseGovernanceDecisionImpact decisionImpact,
    required List<ReleaseGovernanceEvidence> evidence,
    required ReleaseGovernanceExplanation explanation,
    String? ruleSetId,
    ReleaseGovernanceRuleValue? actualValue,
  }) {
    final evaluation = ReleaseGovernanceEvaluation(
      evaluationId: 'rgeval:${rule.ruleId}:${status.wireName}',
      ruleId: rule.ruleId,
      ruleSetId: ruleSetId ?? rule.ruleSetId,
      target: rule.target,
      operator: rule.operator,
      selector: rule.selector,
      expectedValue: rule.expectedValue,
      actualValue: actualValue,
      status: status,
      decisionImpact: decisionImpact,
      evidenceIds: evidence.map((e) => e.evidenceId).toList(),
      explanation: explanation,
      fingerprint: '',
    );
    final fingerprint = _serializer.evaluationFingerprint(evaluation);
    final finalEvaluation = ReleaseGovernanceEvaluation(
      evaluationId: evaluation.evaluationId,
      ruleId: evaluation.ruleId,
      ruleSetId: evaluation.ruleSetId,
      target: evaluation.target,
      operator: evaluation.operator,
      selector: evaluation.selector,
      expectedValue: evaluation.expectedValue,
      actualValue: evaluation.actualValue,
      status: evaluation.status,
      decisionImpact: evaluation.decisionImpact,
      evidenceIds: evaluation.evidenceIds,
      explanation: evaluation.explanation,
      fingerprint: fingerprint,
    );
    return ReleaseGovernanceRuleEvaluationOutcome(
      evaluation: finalEvaluation,
      evidence: evidence,
    );
  }
}
