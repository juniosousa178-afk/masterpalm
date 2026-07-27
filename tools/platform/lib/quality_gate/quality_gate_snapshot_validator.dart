import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';

/// Validates structural consistency of a quality gate snapshot.
class QualityGateSnapshotValidator {
  const QualityGateSnapshotValidator();

  QualityGateValidationResult validate(QualityGateSnapshot snapshot) {
    final errors = <String>[];
    final warnings = <String>[];

    final metadata = snapshot.metadata;
    if (metadata.qualityGateSnapshotId.isEmpty) {
      errors.add('qualityGateSnapshotId is required');
    }
    if (metadata.qualityGateFingerprint.isEmpty) {
      errors.add('qualityGateFingerprint is required');
    }
    if (metadata.policyFingerprint.isEmpty) {
      errors.add('policyFingerprint is required');
    }
    if (snapshot.decision != metadata.decision) {
      errors.add('snapshot decision differs from metadata decision');
    }

    final ruleIds = snapshot.evaluations.map((e) => e.ruleId).toList();
    if (ruleIds.length != ruleIds.toSet().length) {
      errors.add('duplicate rule evaluations detected');
    }

    final evidenceIds = snapshot.evidence.map((e) => e.evidenceId).toList();
    if (evidenceIds.length != evidenceIds.toSet().length) {
      errors.add('duplicate evidence IDs detected');
    }

    for (final evaluation in snapshot.evaluations) {
      if (evaluation.evaluationFingerprint.isEmpty) {
        errors.add('evaluation ${evaluation.ruleId} missing fingerprint');
      }
    }

    final coverage = snapshot.coverage;
    for (final percentage in [
      coverage.requiredRuleCoveragePercentage,
      coverage.overallRuleCoveragePercentage,
      coverage.evidenceCoveragePercentage,
      coverage.sourceCoveragePercentage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        errors.add('coverage percentage out of range: $percentage');
      }
    }

    if (metadata.failedRuleCount !=
        snapshot.evaluations
            .where((e) => e.status == QualityGateRuleStatus.failed)
            .length) {
      warnings.add('metadata.failedRuleCount differs from evaluations');
    }

    if (snapshot.decision == QualityGateDecision.passed) {
      final blockingFailures = snapshot.evaluations.where(
        (e) =>
            e.status == QualityGateRuleStatus.failed &&
            e.decisionImpact == QualityGateDecisionImpact.blocksApproval,
      );
      if (blockingFailures.isNotEmpty) {
        errors.add('passed decision with blocking failures');
      }
    }

    if (snapshot.decision == QualityGateDecision.failed) {
      final hasFailure = snapshot.evaluations.any(
        (e) => e.status == QualityGateRuleStatus.failed,
      );
      final hasBlockingRuleSet = snapshot.ruleSetEvaluations.any(
        (s) => s.required && s.status == QualityGateRuleStatus.failed,
      );
      if (!hasFailure && !hasBlockingRuleSet) {
        warnings.add('failed decision without explicit rule failure');
      }
    }

    if (snapshot.decision == QualityGateDecision.partial &&
        snapshot.limitations.isEmpty &&
        snapshot.coverage.limitations.isEmpty) {
      warnings.add('partial decision without explicit limitation');
    }

    if (snapshot.decision == QualityGateDecision.unavailable &&
        snapshot.coverage.missingSourceTypes.isEmpty &&
        snapshot.eligibility.missingSources.isEmpty) {
      warnings.add('unavailable decision without missing source evidence');
    }

    if (snapshot.decision == QualityGateDecision.incompatible &&
        snapshot.compatibility.incompatibleSources.isEmpty) {
      warnings.add('incompatible decision without incompatible sources');
    }

    if (snapshot.decision == QualityGateDecision.error &&
        snapshot.errors.isEmpty) {
      warnings.add('error decision without registered errors');
    }

    return QualityGateValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
