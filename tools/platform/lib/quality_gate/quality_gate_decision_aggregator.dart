import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';

/// Aggregates final gate decision with explicit precedence order.
class QualityGateDecisionAggregator {
  const QualityGateDecisionAggregator();

  QualityGateDecision aggregate({
    required QualityGateDecisionPolicy decisionPolicy,
    required QualityGateCompatibility compatibility,
    required QualityGateEligibility eligibility,
    required QualityGateCoverage coverage,
    required List<QualityGateEvaluation> evaluations,
    required List<QualityGateRuleSetEvaluation> ruleSetEvaluations,
    required QualityGateSourceResolutionSummary sourceResolutionSummary,
    required List<QualityGateError> errors,
  }) {
    if (errors.any((e) => !e.recoverable)) {
      return QualityGateDecision.error;
    }
    if (evaluations.any(
      (e) => e.decisionImpact == QualityGateDecisionImpact.internalError,
    )) {
      return QualityGateDecision.error;
    }

    if (decisionPolicy.incompatibleOnSourceMismatch &&
        compatibility.status == QualityGateCompatibilityStatus.incompatible) {
      return QualityGateDecision.incompatible;
    }

    if (decisionPolicy.unavailableOnMissingRequiredSources &&
        eligibility.status == QualityGateEligibilityStatus.ineligible &&
        eligibility.missingSources.isNotEmpty) {
      return QualityGateDecision.unavailable;
    }

    if (decisionPolicy.failOnCriticalFailure &&
        _hasFailure(evaluations, QualityGateRuleSeverity.critical)) {
      return QualityGateDecision.failed;
    }

    if (decisionPolicy.failOnBlockingFailure &&
        _hasFailure(evaluations, QualityGateRuleSeverity.blocking)) {
      return QualityGateDecision.failed;
    }

    if (_hasRequiredFailure(evaluations, decisionPolicy)) {
      return QualityGateDecision.failed;
    }

    if (_hasRequiredRuleSetFailure(ruleSetEvaluations)) {
      return QualityGateDecision.failed;
    }

    if (evaluations.any(
      (e) =>
          e.requirement == QualityGateRuleRequirement.required &&
          e.decisionImpact == QualityGateDecisionImpact.causesUnavailable,
    )) {
      return QualityGateDecision.unavailable;
    }

    if (evaluations.any(
      (e) =>
          e.requirement == QualityGateRuleRequirement.required &&
          e.decisionImpact == QualityGateDecisionImpact.causesIncompatible,
    )) {
      return QualityGateDecision.incompatible;
    }

    if (decisionPolicy.partialOnRequiredUnavailable &&
        evaluations.any(
          (e) =>
              e.requirement == QualityGateRuleRequirement.required &&
              e.decisionImpact ==
                  QualityGateDecisionImpact.contributesToPartial,
        )) {
      return QualityGateDecision.partial;
    }

    if (coverage.requiredRuleCoveragePercentage <
        decisionPolicy.minimumCoveragePercentage) {
      return decisionPolicy.partialOnRequiredUnavailable
          ? QualityGateDecision.partial
          : QualityGateDecision.unavailable;
    }

    if (coverage.evaluatedRequiredRuleCount <
        decisionPolicy.minimumEvaluatedRequiredRules) {
      return decisionPolicy.partialOnRequiredUnavailable
          ? QualityGateDecision.partial
          : QualityGateDecision.unavailable;
    }

    if (decisionPolicy.warningsAffectDecision &&
        evaluations.any(
          (e) =>
              e.status == QualityGateRuleStatus.failed &&
              e.severity == QualityGateRuleSeverity.warning,
        )) {
      return QualityGateDecision.partial;
    }

    if (evaluations.any(
      (e) => e.decisionImpact == QualityGateDecisionImpact.contributesToPartial,
    )) {
      return QualityGateDecision.partial;
    }

    if (sourceResolutionSummary.unavailableSourceCount > 0 &&
        eligibility.status == QualityGateEligibilityStatus.partiallyEligible) {
      return QualityGateDecision.partial;
    }

    return QualityGateDecision.passed;
  }

  bool _hasFailure(
    List<QualityGateEvaluation> evaluations,
    QualityGateRuleSeverity severity,
  ) {
    return evaluations.any(
      (e) =>
          e.status == QualityGateRuleStatus.failed &&
          e.severity == severity &&
          e.requirement != QualityGateRuleRequirement.informational,
    );
  }

  bool _hasRequiredFailure(
    List<QualityGateEvaluation> evaluations,
    QualityGateDecisionPolicy decisionPolicy,
  ) {
    return evaluations.any((e) {
      if (e.status != QualityGateRuleStatus.failed) return false;
      if (e.requirement == QualityGateRuleRequirement.informational) {
        return decisionPolicy.informationalRulesAffectDecision;
      }
      if (e.requirement == QualityGateRuleRequirement.optional) {
        return decisionPolicy.optionalFailuresAffectDecision;
      }
      return e.requirement == QualityGateRuleRequirement.required;
    });
  }

  bool _hasRequiredRuleSetFailure(
    List<QualityGateRuleSetEvaluation> ruleSetEvaluations,
  ) {
    return ruleSetEvaluations.any(
      (set) =>
          set.required &&
          (set.status == QualityGateRuleStatus.failed ||
              set.status == QualityGateRuleStatus.incompatible),
    );
  }
}
