import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_policy.dart';

/// Terminal status and impact for missing target data.
class ReleaseGovernanceMissingDataOutcome {
  const ReleaseGovernanceMissingDataOutcome({
    required this.status,
    required this.decisionImpact,
  });

  final ReleaseGovernanceRuleStatus status;
  final ReleaseGovernanceDecisionImpact decisionImpact;
}

/// Terminal status and impact for incompatible target data.
class ReleaseGovernanceIncompatibleDataOutcome {
  const ReleaseGovernanceIncompatibleDataOutcome({
    required this.status,
    required this.decisionImpact,
  });

  final ReleaseGovernanceRuleStatus status;
  final ReleaseGovernanceDecisionImpact decisionImpact;
}

/// Maps missing-data policies to rule status and decision impact.
class ReleaseGovernanceMissingDataHandler {
  const ReleaseGovernanceMissingDataHandler();

  ReleaseGovernanceMissingDataOutcome handle(ReleaseGovernanceRule rule) {
    if (rule.requirement == ReleaseGovernanceRuleRequirement.informational) {
      return const ReleaseGovernanceMissingDataOutcome(
        status: ReleaseGovernanceRuleStatus.notApplicable,
        decisionImpact: ReleaseGovernanceDecisionImpact.none,
      );
    }

    return switch (rule.missingDataPolicy) {
      ReleaseGovernanceMissingDataPolicy.reject =>
        ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.failed,
          decisionImpact: _blockingImpact(rule),
        ),
      ReleaseGovernanceMissingDataPolicy.pending =>
        const ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.pending,
          decisionImpact: ReleaseGovernanceDecisionImpact.contributesToPending,
        ),
      ReleaseGovernanceMissingDataPolicy.unavailable =>
        const ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.unavailable,
          decisionImpact: ReleaseGovernanceDecisionImpact.causesUnavailable,
        ),
      ReleaseGovernanceMissingDataPolicy.conditional =>
        const ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.conditionallySatisfied,
          decisionImpact:
              ReleaseGovernanceDecisionImpact.contributesToConditions,
        ),
      ReleaseGovernanceMissingDataPolicy.skip =>
        const ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.skipped,
          decisionImpact: ReleaseGovernanceDecisionImpact.none,
        ),
      ReleaseGovernanceMissingDataPolicy.notApplicable =>
        const ReleaseGovernanceMissingDataOutcome(
          status: ReleaseGovernanceRuleStatus.notApplicable,
          decisionImpact: ReleaseGovernanceDecisionImpact.none,
        ),
    };
  }
}

/// Maps incompatible-data policies to rule status and decision impact.
class ReleaseGovernanceIncompatibleDataHandler {
  const ReleaseGovernanceIncompatibleDataHandler();

  ReleaseGovernanceIncompatibleDataOutcome handle(ReleaseGovernanceRule rule) {
    if (rule.requirement == ReleaseGovernanceRuleRequirement.informational) {
      return const ReleaseGovernanceIncompatibleDataOutcome(
        status: ReleaseGovernanceRuleStatus.notApplicable,
        decisionImpact: ReleaseGovernanceDecisionImpact.none,
      );
    }

    return switch (rule.incompatibleDataPolicy) {
      ReleaseGovernanceIncompatibleDataPolicy.reject =>
        ReleaseGovernanceIncompatibleDataOutcome(
          status: ReleaseGovernanceRuleStatus.failed,
          decisionImpact: _blockingImpact(rule),
        ),
      ReleaseGovernanceIncompatibleDataPolicy.pending =>
        const ReleaseGovernanceIncompatibleDataOutcome(
          status: ReleaseGovernanceRuleStatus.pending,
          decisionImpact: ReleaseGovernanceDecisionImpact.contributesToPending,
        ),
      ReleaseGovernanceIncompatibleDataPolicy.incompatible =>
        const ReleaseGovernanceIncompatibleDataOutcome(
          status: ReleaseGovernanceRuleStatus.incompatible,
          decisionImpact: ReleaseGovernanceDecisionImpact.causesIncompatible,
        ),
      ReleaseGovernanceIncompatibleDataPolicy.conditional =>
        const ReleaseGovernanceIncompatibleDataOutcome(
          status: ReleaseGovernanceRuleStatus.conditionallySatisfied,
          decisionImpact:
              ReleaseGovernanceDecisionImpact.contributesToConditions,
        ),
      ReleaseGovernanceIncompatibleDataPolicy.skip =>
        const ReleaseGovernanceIncompatibleDataOutcome(
          status: ReleaseGovernanceRuleStatus.skipped,
          decisionImpact: ReleaseGovernanceDecisionImpact.none,
        ),
    };
  }
}

/// Resolves decision impact from rule evaluation outcome.
class ReleaseGovernanceDecisionImpactResolver {
  const ReleaseGovernanceDecisionImpactResolver({
    ReleaseGovernanceMissingDataHandler? missingDataHandler,
    ReleaseGovernanceIncompatibleDataHandler? incompatibleDataHandler,
  })  : _missingDataHandler =
            missingDataHandler ?? const ReleaseGovernanceMissingDataHandler(),
        _incompatibleDataHandler = incompatibleDataHandler ??
            const ReleaseGovernanceIncompatibleDataHandler();

  final ReleaseGovernanceMissingDataHandler _missingDataHandler;
  final ReleaseGovernanceIncompatibleDataHandler _incompatibleDataHandler;

  ReleaseGovernanceDecisionImpact resolve({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernanceRuleStatus status,
    required ReleaseGovernanceDecisionPolicy decisionPolicy,
    bool operatorTypeError = false,
  }) {
    if (rule.requirement == ReleaseGovernanceRuleRequirement.informational) {
      return ReleaseGovernanceDecisionImpact.none;
    }

    if (operatorTypeError || status == ReleaseGovernanceRuleStatus.error) {
      return ReleaseGovernanceDecisionImpact.internalError;
    }

    switch (status) {
      case ReleaseGovernanceRuleStatus.passed:
      case ReleaseGovernanceRuleStatus.skipped:
      case ReleaseGovernanceRuleStatus.notApplicable:
      case ReleaseGovernanceRuleStatus.waived:
        return ReleaseGovernanceDecisionImpact.none;
      case ReleaseGovernanceRuleStatus.failed:
        return _failedImpact(rule, decisionPolicy);
      case ReleaseGovernanceRuleStatus.pending:
        return ReleaseGovernanceDecisionImpact.contributesToPending;
      case ReleaseGovernanceRuleStatus.conditionallySatisfied:
        return ReleaseGovernanceDecisionImpact.contributesToConditions;
      case ReleaseGovernanceRuleStatus.unavailable:
        return _missingDataHandler.handle(rule).decisionImpact;
      case ReleaseGovernanceRuleStatus.incompatible:
        return _incompatibleDataHandler.handle(rule).decisionImpact;
      case ReleaseGovernanceRuleStatus.expired:
        return ReleaseGovernanceDecisionImpact.causesExpiration;
      case ReleaseGovernanceRuleStatus.error:
        return ReleaseGovernanceDecisionImpact.internalError;
    }
  }

  ReleaseGovernanceDecisionImpact _failedImpact(
    ReleaseGovernanceRule rule,
    ReleaseGovernanceDecisionPolicy decisionPolicy,
  ) {
    if (rule.requirement == ReleaseGovernanceRuleRequirement.optional &&
        !decisionPolicy.optionalFailuresCreateConditions) {
      return rule.severity == ReleaseGovernanceRuleSeverity.warning ||
              rule.severity == ReleaseGovernanceRuleSeverity.advisory
          ? ReleaseGovernanceDecisionImpact.advisory
          : ReleaseGovernanceDecisionImpact.contributesToConditions;
    }

    if (rule.severity == ReleaseGovernanceRuleSeverity.critical) {
      return ReleaseGovernanceDecisionImpact.causesRejection;
    }
    if (rule.severity == ReleaseGovernanceRuleSeverity.blocking ||
        rule.requirement == ReleaseGovernanceRuleRequirement.required) {
      return ReleaseGovernanceDecisionImpact.blocksApproval;
    }
    if (rule.severity == ReleaseGovernanceRuleSeverity.warning ||
        rule.severity == ReleaseGovernanceRuleSeverity.advisory) {
      return decisionPolicy.warningMayCreateCondition
          ? ReleaseGovernanceDecisionImpact.contributesToConditions
          : ReleaseGovernanceDecisionImpact.advisory;
    }
    return ReleaseGovernanceDecisionImpact.blocksApproval;
  }
}

ReleaseGovernanceDecisionImpact _blockingImpact(ReleaseGovernanceRule rule) {
  if (rule.requirement == ReleaseGovernanceRuleRequirement.optional) {
    return ReleaseGovernanceDecisionImpact.contributesToConditions;
  }
  if (rule.severity == ReleaseGovernanceRuleSeverity.critical) {
    return ReleaseGovernanceDecisionImpact.causesRejection;
  }
  if (rule.severity == ReleaseGovernanceRuleSeverity.blocking ||
      rule.requirement == ReleaseGovernanceRuleRequirement.required) {
    return ReleaseGovernanceDecisionImpact.blocksApproval;
  }
  return ReleaseGovernanceDecisionImpact.contributesToConditions;
}
