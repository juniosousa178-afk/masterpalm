import '../../models/quality_gate/quality_gate_enums.dart';
import '../../models/quality_gate/quality_gate_snapshot.dart';
import '../report_input.dart';

/// Converts [QualityGateSnapshot] into report input data.
class QualityGateReportSource {
  const QualityGateReportSource();

  QualityGateReportInputData fromSnapshot(QualityGateSnapshot snapshot) {
    final failedRules = snapshot.evaluations
        .where((e) => e.status == QualityGateRuleStatus.failed)
        .map((e) => '${e.ruleId}: ${e.explanation.summary}')
        .toList();
    final passedRules = snapshot.evaluations
        .where((e) => e.status == QualityGateRuleStatus.passed)
        .map((e) => e.ruleId)
        .toList();
    final unavailableRules = snapshot.evaluations
        .where((e) => e.status == QualityGateRuleStatus.unavailable)
        .map((e) => e.ruleId)
        .toList();

    return QualityGateReportInputData(
      qualityGateSnapshotId: snapshot.metadata.qualityGateSnapshotId,
      qualityGateFingerprint: snapshot.metadata.qualityGateFingerprint,
      decision: snapshot.decision.wireName,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      eligibility: snapshot.eligibility.status.wireName,
      compatibility: snapshot.compatibility.status.wireName,
      evaluatedRuleCount: snapshot.metadata.evaluatedRuleCount,
      failedRuleCount: snapshot.metadata.failedRuleCount,
      blockingFailureCount: snapshot.metadata.blockingFailureCount,
      requiredRuleCoveragePercentage:
          snapshot.coverage.requiredRuleCoveragePercentage,
      overallRuleCoveragePercentage:
          snapshot.coverage.overallRuleCoveragePercentage,
      failedRules: failedRules,
      passedRules: passedRules,
      unavailableRules: unavailableRules,
      ruleSetSummaries: snapshot.ruleSetEvaluations
          .map(
            (r) =>
                '${r.ruleSetId}: ${r.status.wireName} (${r.passedRuleCount}/${r.evaluatedRuleCount})',
          )
          .toList(),
      sourceSummaries: snapshot.sourceReferences
          .map((r) =>
              '${r.sourceType.wireName}:${r.resolvedId ?? r.requestedId}')
          .toList(),
      limitations: snapshot.limitations.map((l) => l.description).toList(),
      warnings: snapshot.warnings.map((w) => w.message).toList(),
      errors: snapshot.errors.map((e) => e.message).toList(),
    );
  }

  QualityGateReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(QualityGateSnapshot.fromJson(json));
  }
}
