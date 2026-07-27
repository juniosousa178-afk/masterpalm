import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';
import 'quality_gate_canonical_serializer.dart';
import 'quality_gate_evidence_builder.dart';
import 'quality_gate_explanation_builder.dart';
import 'quality_gate_handlers.dart';
import 'quality_gate_operator_evaluator.dart';
import 'quality_gate_target_registry.dart';
import 'resolved_quality_gate_sources.dart';

/// Evaluates a single quality gate rule against resolved sources.
class QualityGateRuleEvaluator {
  QualityGateRuleEvaluator({
    QualityGateTargetRegistry? targetRegistry,
    QualityGateOperatorEvaluator? operatorEvaluator,
    QualityGateMissingDataHandler? missingDataHandler,
    QualityGateIncompatibleDataHandler? incompatibleDataHandler,
    QualityGateDecisionImpactResolver? impactResolver,
    QualityGateEvidenceBuilder? evidenceBuilder,
    QualityGateExplanationBuilder? explanationBuilder,
    QualityGateCanonicalSerializer? serializer,
  })  : _targetRegistry = targetRegistry ?? QualityGateTargetRegistry(),
        _operatorEvaluator =
            operatorEvaluator ?? const QualityGateOperatorEvaluator(),
        _missingDataHandler =
            missingDataHandler ?? const QualityGateMissingDataHandler(),
        _incompatibleDataHandler = incompatibleDataHandler ??
            const QualityGateIncompatibleDataHandler(),
        _impactResolver =
            impactResolver ?? const QualityGateDecisionImpactResolver(),
        _evidenceBuilder =
            evidenceBuilder ?? const QualityGateEvidenceBuilder(),
        _explanationBuilder =
            explanationBuilder ?? const QualityGateExplanationBuilder(),
        _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateTargetRegistry _targetRegistry;
  final QualityGateOperatorEvaluator _operatorEvaluator;
  final QualityGateMissingDataHandler _missingDataHandler;
  final QualityGateIncompatibleDataHandler _incompatibleDataHandler;
  final QualityGateDecisionImpactResolver _impactResolver;
  final QualityGateEvidenceBuilder _evidenceBuilder;
  final QualityGateExplanationBuilder _explanationBuilder;
  final QualityGateCanonicalSerializer _serializer;

  QualityGateEvaluation evaluate({
    required QualityGateRule rule,
    required QualityGatePolicy policy,
    required QualityGateRequest request,
    required ResolvedQualityGateSources sources,
    String? ruleSetId,
  }) {
    if (!rule.enabled) {
      return _buildEvaluation(
        rule: rule,
        policy: policy,
        ruleSetId: ruleSetId,
        status: QualityGateRuleStatus.skipped,
        decisionImpact: QualityGateDecisionImpact.none,
        evidence: const [],
        explanation: _explanationBuilder.buildRuleExplanation(
          rule: rule,
          status: QualityGateRuleStatus.skipped,
        ),
      );
    }

    if (_isExcluded(request, rule)) {
      return _buildEvaluation(
        rule: rule,
        policy: policy,
        ruleSetId: ruleSetId,
        status: QualityGateRuleStatus.skipped,
        decisionImpact: QualityGateDecisionImpact.none,
        evidence: const [],
        explanation: _explanationBuilder.buildRuleExplanation(
          rule: rule,
          status: QualityGateRuleStatus.skipped,
        ),
      );
    }

    final context = QualityGateEvaluationContext(
      projectId: request.projectId,
      referenceTime: request.referenceTime,
      commitId: request.commitId,
      branch: request.branch,
      strictCompatibility: request.strictCompatibility,
      requiredSourceTypes: policy.requiredSourceTypes,
    );

    final resolution = _targetRegistry.resolve(rule, sources, context);

    switch (resolution.status) {
      case QualityGateTargetResolutionStatus.notApplicable:
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId,
          status: QualityGateRuleStatus.notApplicable,
          decisionImpact: QualityGateDecisionImpact.none,
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: QualityGateRuleStatus.notApplicable,
            explanation: 'Target not applicable',
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: QualityGateRuleStatus.notApplicable,
          ),
          limitations: resolution.limitations,
          warnings: resolution.warnings,
        );
      case QualityGateTargetResolutionStatus.unavailable:
        final missing = _missingDataHandler.handle(rule);
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId,
          status: missing.status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: missing.status,
            decisionPolicy: policy.decisionPolicy,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: missing.status,
            explanation: 'Target unavailable',
            evidenceType: QualityGateEvidenceType.unavailable,
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: missing.status,
          ),
          limitations: resolution.limitations,
          warnings: resolution.warnings,
        );
      case QualityGateTargetResolutionStatus.incompatible:
        final incompatible = _incompatibleDataHandler.handle(rule);
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId,
          status: incompatible.status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: incompatible.status,
            decisionPolicy: policy.decisionPolicy,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: incompatible.status,
            explanation: 'Target incompatible',
            evidenceType: QualityGateEvidenceType.incompatible,
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: incompatible.status,
          ),
          limitations: resolution.limitations,
          warnings: resolution.warnings,
        );
      case QualityGateTargetResolutionStatus.unsupported:
      case QualityGateTargetResolutionStatus.error:
        final status = rule.requirement == QualityGateRuleRequirement.required
            ? QualityGateRuleStatus.error
            : QualityGateRuleStatus.unavailable;
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId,
          status: status,
          decisionImpact: _impactResolver.resolve(
            rule: rule,
            status: status,
            decisionPolicy: policy.decisionPolicy,
            operatorTypeError: status == QualityGateRuleStatus.error,
          ),
          evidence: _evidenceBuilder.buildUnavailable(
            rule: rule,
            observedStatus: status,
            explanation: 'Unsupported target',
          ),
          explanation: _explanationBuilder.buildRuleExplanation(
            rule: rule,
            status: status,
            operatorMessage: 'Unsupported target ${rule.target.wireName}',
          ),
          limitations: resolution.limitations,
          warnings: resolution.warnings,
        );
      case QualityGateTargetResolutionStatus.resolved:
        final operatorResult = _operatorEvaluator.evaluate(
          operator: rule.operator,
          actualValue: resolution.actualValue,
          expectedValue: rule.expectedValue,
        );
        if (operatorResult.typeError) {
          final status = QualityGateRuleStatus.error;
          return _buildEvaluation(
            rule: rule,
            policy: policy,
            ruleSetId: ruleSetId,
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
            limitations: resolution.limitations,
            warnings: resolution.warnings,
          );
        }

        final status = operatorResult.passed
            ? QualityGateRuleStatus.passed
            : QualityGateRuleStatus.failed;
        final impact =
            rule.requirement == QualityGateRuleRequirement.informational
                ? QualityGateDecisionImpact.none
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
            explanation: explanation.ruleExplanation,
          ),
        ];
        return _buildEvaluation(
          rule: rule,
          policy: policy,
          ruleSetId: ruleSetId,
          status: status,
          decisionImpact: impact,
          actualValue: resolution.actualValue,
          evidence: evidence,
          explanation: explanation,
          limitations: resolution.limitations,
          warnings: resolution.warnings,
        );
    }
  }

  bool _isExcluded(QualityGateRequest request, QualityGateRule rule) {
    if (request.requestedRuleIds != null &&
        !request.requestedRuleIds!.contains(rule.ruleId)) {
      return true;
    }
    if (request.excludedRuleIds?.contains(rule.ruleId) ?? false) {
      return true;
    }
    return false;
  }

  QualityGateEvaluation _buildEvaluation({
    required QualityGateRule rule,
    required QualityGatePolicy policy,
    required QualityGateRuleStatus status,
    required QualityGateDecisionImpact decisionImpact,
    required List<QualityGateEvidence> evidence,
    required QualityGateExplanation explanation,
    String? ruleSetId,
    QualityGateRuleValue? actualValue,
    List<QualityGateLimitation> limitations = const [],
    List<QualityGateWarning> warnings = const [],
  }) {
    final evaluation = QualityGateEvaluation(
      ruleId: rule.ruleId,
      ruleSetId: ruleSetId,
      status: status,
      decisionImpact: decisionImpact,
      severity: rule.severity,
      requirement: rule.requirement,
      target: rule.target,
      selector: rule.selector,
      operator: rule.operator,
      expectedValue: rule.expectedValue,
      actualValue: actualValue,
      evidence: evidence,
      explanation: explanation,
      warnings: warnings,
      limitations: limitations,
      evaluationFingerprint: '',
    );
    final fingerprint = _serializer.evaluationFingerprint(evaluation);
    return QualityGateEvaluation(
      ruleId: evaluation.ruleId,
      ruleSetId: evaluation.ruleSetId,
      status: evaluation.status,
      decisionImpact: evaluation.decisionImpact,
      severity: evaluation.severity,
      requirement: evaluation.requirement,
      target: evaluation.target,
      selector: evaluation.selector,
      operator: evaluation.operator,
      expectedValue: evaluation.expectedValue,
      actualValue: evaluation.actualValue,
      evidence: evaluation.evidence,
      explanation: evaluation.explanation,
      warnings: evaluation.warnings,
      errors: evaluation.errors,
      limitations: evaluation.limitations,
      evaluationFingerprint: fingerprint,
    );
  }
}
