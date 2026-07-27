import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';

/// Validates structural consistency of a release decision snapshot.
class DefaultReleaseDecisionSnapshotValidator
    implements ReleaseDecisionSnapshotValidator {
  const DefaultReleaseDecisionSnapshotValidator();

  @override
  ReleaseGovernanceValidationResult validate(dynamic snapshot) {
    if (snapshot is! ReleaseDecisionSnapshot) {
      return const ReleaseGovernanceValidationResult(
        isValid: false,
        errors: ['Snapshot is not a ReleaseDecisionSnapshot'],
      );
    }

    final errors = <String>[];
    final warnings = <String>[];

    final metadata = snapshot.metadata;
    if (metadata.snapshotId.isEmpty) {
      errors.add('snapshotId is required');
    }
    if (metadata.policyFingerprint.isEmpty) {
      errors.add('policyFingerprint is required');
    }
    if (metadata.qualityGateSnapshotId.isEmpty) {
      errors.add('qualityGateSnapshotId is required');
    }
    if (snapshot.decision != metadata.decision) {
      errors.add('snapshot decision differs from metadata decision');
    }
    if (snapshot.fingerprint.isEmpty) {
      errors.add('fingerprint is required');
    }

    final ruleIds = snapshot.evaluations.map((e) => e.ruleId).toList();
    if (ruleIds.length != ruleIds.toSet().length) {
      errors.add('duplicate rule evaluations detected');
    }

    for (final percentage in [
      snapshot.coverage.ruleCoveragePercentage,
      snapshot.coverage.requiredRuleCoveragePercentage,
      snapshot.coverage.approvalCoveragePercentage,
      snapshot.coverage.evidenceCoveragePercentage,
      snapshot.coverage.sourceCoveragePercentage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        errors.add('coverage percentage out of range: $percentage');
      }
    }

    if (snapshot.decision == ReleaseGovernanceDecision.approved) {
      final blockingFailures = snapshot.evaluations.where(
        (e) =>
            e.status == ReleaseGovernanceRuleStatus.failed &&
            e.decisionImpact == ReleaseGovernanceDecisionImpact.blocksApproval,
      );
      if (blockingFailures.isNotEmpty) {
        errors.add('approved decision with blocking failures');
      }
    }

    if (snapshot.decision == ReleaseGovernanceDecision.rejected) {
      final hasFailure = snapshot.evaluations.any(
        (e) => e.status == ReleaseGovernanceRuleStatus.failed,
      );
      final hasRejectedApproval = snapshot.approvalEvaluations.any(
        (a) => a.status == ReleaseApprovalEvaluationStatus.rejected,
      );
      if (!hasFailure && !hasRejectedApproval) {
        warnings.add('rejected decision without explicit failure');
      }
    }

    if (snapshot.decision == ReleaseGovernanceDecision.approvedWithConditions &&
        snapshot.conditions.isEmpty) {
      warnings.add('approvedWithConditions without conditions');
    }

    return ReleaseGovernanceValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
