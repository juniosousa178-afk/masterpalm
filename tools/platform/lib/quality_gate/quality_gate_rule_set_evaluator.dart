import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import 'quality_gate_canonical_serializer.dart';
import 'quality_gate_explanation_builder.dart';

/// Aggregates rule evaluations within a rule set.
class QualityGateRuleSetEvaluator {
  const QualityGateRuleSetEvaluator({
    QualityGateExplanationBuilder? explanationBuilder,
    QualityGateCanonicalSerializer? serializer,
  })  : _explanationBuilder =
            explanationBuilder ?? const QualityGateExplanationBuilder(),
        _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateExplanationBuilder _explanationBuilder;
  final QualityGateCanonicalSerializer _serializer;

  QualityGateRuleSetEvaluation evaluate({
    required QualityGateRuleSet ruleSet,
    required List<QualityGateEvaluation> memberEvaluations,
  }) {
    final participating = memberEvaluations
        .where(
          (e) =>
              e.status != QualityGateRuleStatus.skipped &&
              e.status != QualityGateRuleStatus.notApplicable,
        )
        .toList();

    final passed = participating
        .where((e) => e.status == QualityGateRuleStatus.passed)
        .length;
    final failed = participating
        .where((e) => e.status == QualityGateRuleStatus.failed)
        .length;
    final unavailable = participating
        .where((e) => e.status == QualityGateRuleStatus.unavailable)
        .length;
    final incompatible = participating
        .where((e) => e.status == QualityGateRuleStatus.incompatible)
        .length;
    final evaluated = participating
        .where(
          (e) =>
              e.status == QualityGateRuleStatus.passed ||
              e.status == QualityGateRuleStatus.failed,
        )
        .length;

    final status = _aggregateStatus(
      ruleSet: ruleSet,
      passed: passed,
      failed: failed,
      unavailable: unavailable,
      incompatible: incompatible,
      evaluated: evaluated,
      participatingCount: participating.length,
    );

    final decisionImpact = _aggregateImpact(ruleSet, memberEvaluations, status);
    final explanation = _explanationBuilder.buildRuleSetExplanation(
      ruleSet: ruleSet,
      status: status,
      passedRuleCount: passed,
      failedRuleCount: failed,
    );

    final evaluation = QualityGateRuleSetEvaluation(
      ruleSetId: ruleSet.ruleSetId,
      status: status,
      aggregationMode: ruleSet.aggregationMode,
      totalRuleCount: ruleSet.rules.length,
      evaluatedRuleCount: evaluated,
      passedRuleCount: passed,
      failedRuleCount: failed,
      unavailableRuleCount: unavailable,
      incompatibleRuleCount: incompatible,
      required: ruleSet.required,
      severity: ruleSet.severity,
      decisionImpact: decisionImpact,
      ruleEvaluationIds: memberEvaluations.map((e) => e.ruleId).toList()
        ..sort(),
      explanation: explanation,
      fingerprint: '',
    );

    return QualityGateRuleSetEvaluation(
      ruleSetId: evaluation.ruleSetId,
      status: evaluation.status,
      aggregationMode: evaluation.aggregationMode,
      totalRuleCount: evaluation.totalRuleCount,
      evaluatedRuleCount: evaluation.evaluatedRuleCount,
      passedRuleCount: evaluation.passedRuleCount,
      failedRuleCount: evaluation.failedRuleCount,
      unavailableRuleCount: evaluation.unavailableRuleCount,
      incompatibleRuleCount: evaluation.incompatibleRuleCount,
      required: evaluation.required,
      severity: evaluation.severity,
      decisionImpact: evaluation.decisionImpact,
      ruleEvaluationIds: evaluation.ruleEvaluationIds,
      explanation: evaluation.explanation,
      fingerprint: _serializer.fingerprintFromString(
        evaluation.toJson().toString(),
      ),
    );
  }

  QualityGateRuleStatus _aggregateStatus({
    required QualityGateRuleSet ruleSet,
    required int passed,
    required int failed,
    required int unavailable,
    required int incompatible,
    required int evaluated,
    required int participatingCount,
  }) {
    if (participatingCount == 0) {
      return QualityGateRuleStatus.notApplicable;
    }
    if (incompatible > 0) {
      return QualityGateRuleStatus.incompatible;
    }

    switch (ruleSet.aggregationMode) {
      case QualityGateRuleSetAggregationMode.all:
        if (failed > 0) return QualityGateRuleStatus.failed;
        if (unavailable > 0) return QualityGateRuleStatus.unavailable;
        return passed == participatingCount
            ? QualityGateRuleStatus.passed
            : QualityGateRuleStatus.failed;
      case QualityGateRuleSetAggregationMode.any:
        if (passed > 0) return QualityGateRuleStatus.passed;
        if (failed == participatingCount) return QualityGateRuleStatus.failed;
        return QualityGateRuleStatus.unavailable;
      case QualityGateRuleSetAggregationMode.minimumCount:
        final minimum = ruleSet.minimumPassCount ?? 1;
        return passed >= minimum
            ? QualityGateRuleStatus.passed
            : QualityGateRuleStatus.failed;
      case QualityGateRuleSetAggregationMode.minimumPercentage:
        final threshold = ruleSet.minimumPassPercentage ?? 100;
        if (evaluated == 0) return QualityGateRuleStatus.unavailable;
        final percentage = (passed / evaluated) * 100;
        return percentage >= threshold
            ? QualityGateRuleStatus.passed
            : QualityGateRuleStatus.failed;
    }
  }

  QualityGateDecisionImpact _aggregateImpact(
    QualityGateRuleSet ruleSet,
    List<QualityGateEvaluation> evaluations,
    QualityGateRuleStatus status,
  ) {
    if (!ruleSet.required) {
      return QualityGateDecisionImpact.advisory;
    }
    return switch (status) {
      QualityGateRuleStatus.passed => QualityGateDecisionImpact.none,
      QualityGateRuleStatus.failed =>
        ruleSet.severity == QualityGateRuleSeverity.critical ||
                ruleSet.severity == QualityGateRuleSeverity.blocking
            ? QualityGateDecisionImpact.blocksApproval
            : QualityGateDecisionImpact.blocksApproval,
      QualityGateRuleStatus.unavailable =>
        QualityGateDecisionImpact.causesUnavailable,
      QualityGateRuleStatus.incompatible =>
        QualityGateDecisionImpact.causesIncompatible,
      QualityGateRuleStatus.notApplicable ||
      QualityGateRuleStatus.skipped =>
        QualityGateDecisionImpact.none,
      QualityGateRuleStatus.error => QualityGateDecisionImpact.internalError,
    };
  }
}
