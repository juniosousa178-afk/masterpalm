import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_policy.dart';

/// Terminal status and impact for missing target data.
class QualityGateMissingDataOutcome {
  const QualityGateMissingDataOutcome({
    required this.status,
    required this.decisionImpact,
  });

  final QualityGateRuleStatus status;
  final QualityGateDecisionImpact decisionImpact;
}

/// Terminal status and impact for incompatible target data.
class QualityGateIncompatibleDataOutcome {
  const QualityGateIncompatibleDataOutcome({
    required this.status,
    required this.decisionImpact,
  });

  final QualityGateRuleStatus status;
  final QualityGateDecisionImpact decisionImpact;
}

/// Maps missing-data policies to rule status and decision impact.
class QualityGateMissingDataHandler {
  const QualityGateMissingDataHandler();

  QualityGateMissingDataOutcome handle(QualityGateRule rule) {
    if (rule.requirement == QualityGateRuleRequirement.informational) {
      return const QualityGateMissingDataOutcome(
        status: QualityGateRuleStatus.notApplicable,
        decisionImpact: QualityGateDecisionImpact.none,
      );
    }

    return switch (rule.missingDataPolicy) {
      QualityGateMissingDataPolicy.fail => QualityGateMissingDataOutcome(
          status: QualityGateRuleStatus.failed,
          decisionImpact: _blockingImpact(rule),
        ),
      QualityGateMissingDataPolicy.partial =>
        const QualityGateMissingDataOutcome(
          status: QualityGateRuleStatus.unavailable,
          decisionImpact: QualityGateDecisionImpact.contributesToPartial,
        ),
      QualityGateMissingDataPolicy.unavailable =>
        const QualityGateMissingDataOutcome(
          status: QualityGateRuleStatus.unavailable,
          decisionImpact: QualityGateDecisionImpact.causesUnavailable,
        ),
      QualityGateMissingDataPolicy.skip => const QualityGateMissingDataOutcome(
          status: QualityGateRuleStatus.skipped,
          decisionImpact: QualityGateDecisionImpact.none,
        ),
      QualityGateMissingDataPolicy.notApplicable =>
        const QualityGateMissingDataOutcome(
          status: QualityGateRuleStatus.notApplicable,
          decisionImpact: QualityGateDecisionImpact.none,
        ),
    };
  }
}

/// Maps incompatible-data policies to rule status and decision impact.
class QualityGateIncompatibleDataHandler {
  const QualityGateIncompatibleDataHandler();

  QualityGateIncompatibleDataOutcome handle(QualityGateRule rule) {
    if (rule.requirement == QualityGateRuleRequirement.informational) {
      return const QualityGateIncompatibleDataOutcome(
        status: QualityGateRuleStatus.notApplicable,
        decisionImpact: QualityGateDecisionImpact.none,
      );
    }

    return switch (rule.incompatibleDataPolicy) {
      QualityGateIncompatibleDataPolicy.fail =>
        QualityGateIncompatibleDataOutcome(
          status: QualityGateRuleStatus.failed,
          decisionImpact: _blockingImpact(rule),
        ),
      QualityGateIncompatibleDataPolicy.partial =>
        const QualityGateIncompatibleDataOutcome(
          status: QualityGateRuleStatus.incompatible,
          decisionImpact: QualityGateDecisionImpact.contributesToPartial,
        ),
      QualityGateIncompatibleDataPolicy.incompatible =>
        const QualityGateIncompatibleDataOutcome(
          status: QualityGateRuleStatus.incompatible,
          decisionImpact: QualityGateDecisionImpact.causesIncompatible,
        ),
      QualityGateIncompatibleDataPolicy.skip =>
        const QualityGateIncompatibleDataOutcome(
          status: QualityGateRuleStatus.skipped,
          decisionImpact: QualityGateDecisionImpact.none,
        ),
    };
  }
}

/// Resolves decision impact from rule evaluation outcome.
class QualityGateDecisionImpactResolver {
  const QualityGateDecisionImpactResolver({
    QualityGateMissingDataHandler? missingDataHandler,
    QualityGateIncompatibleDataHandler? incompatibleDataHandler,
  })  : _missingDataHandler =
            missingDataHandler ?? const QualityGateMissingDataHandler(),
        _incompatibleDataHandler = incompatibleDataHandler ??
            const QualityGateIncompatibleDataHandler();

  final QualityGateMissingDataHandler _missingDataHandler;
  final QualityGateIncompatibleDataHandler _incompatibleDataHandler;

  QualityGateDecisionImpact resolve({
    required QualityGateRule rule,
    required QualityGateRuleStatus status,
    required QualityGateDecisionPolicy decisionPolicy,
    bool operatorTypeError = false,
  }) {
    if (rule.requirement == QualityGateRuleRequirement.informational) {
      return QualityGateDecisionImpact.none;
    }

    if (operatorTypeError || status == QualityGateRuleStatus.error) {
      return QualityGateDecisionImpact.internalError;
    }

    switch (status) {
      case QualityGateRuleStatus.passed:
      case QualityGateRuleStatus.skipped:
      case QualityGateRuleStatus.notApplicable:
        return QualityGateDecisionImpact.none;
      case QualityGateRuleStatus.failed:
        return _failedImpact(rule, decisionPolicy);
      case QualityGateRuleStatus.unavailable:
        return _missingDataHandler.handle(rule).decisionImpact;
      case QualityGateRuleStatus.incompatible:
        return _incompatibleDataHandler.handle(rule).decisionImpact;
      case QualityGateRuleStatus.error:
        return QualityGateDecisionImpact.internalError;
    }
  }

  QualityGateDecisionImpact _failedImpact(
    QualityGateRule rule,
    QualityGateDecisionPolicy decisionPolicy,
  ) {
    if (rule.requirement == QualityGateRuleRequirement.optional &&
        !decisionPolicy.optionalFailuresAffectDecision) {
      return rule.severity == QualityGateRuleSeverity.warning ||
              rule.severity == QualityGateRuleSeverity.advisory
          ? QualityGateDecisionImpact.advisory
          : QualityGateDecisionImpact.contributesToPartial;
    }

    if (rule.severity == QualityGateRuleSeverity.critical ||
        rule.severity == QualityGateRuleSeverity.blocking ||
        rule.requirement == QualityGateRuleRequirement.required) {
      return QualityGateDecisionImpact.blocksApproval;
    }

    if (rule.severity == QualityGateRuleSeverity.warning ||
        rule.severity == QualityGateRuleSeverity.advisory) {
      return decisionPolicy.warningsAffectDecision
          ? QualityGateDecisionImpact.contributesToPartial
          : QualityGateDecisionImpact.advisory;
    }

    return QualityGateDecisionImpact.blocksApproval;
  }
}

QualityGateDecisionImpact _blockingImpact(QualityGateRule rule) {
  if (rule.requirement == QualityGateRuleRequirement.optional) {
    return QualityGateDecisionImpact.contributesToPartial;
  }
  if (rule.severity == QualityGateRuleSeverity.critical ||
      rule.severity == QualityGateRuleSeverity.blocking ||
      rule.requirement == QualityGateRuleRequirement.required) {
    return QualityGateDecisionImpact.blocksApproval;
  }
  return QualityGateDecisionImpact.contributesToPartial;
}
