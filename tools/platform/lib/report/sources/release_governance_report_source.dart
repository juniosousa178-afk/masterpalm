import '../../models/release_governance/release_decision_snapshot.dart';
import '../../models/release_governance/release_governance_enums.dart';
import '../report_input.dart';

/// Converts [ReleaseDecisionSnapshot] into report input data.
///
/// Consumes an existing snapshot only — never executes [ReleaseGovernanceEngine].
class ReleaseGovernanceReportSource {
  const ReleaseGovernanceReportSource();

  ReleaseGovernanceReportInputData fromSnapshot(
      ReleaseDecisionSnapshot snapshot) {
    final meta = snapshot.metadata;
    final failedRules = snapshot.evaluations
        .where((e) => e.status == ReleaseGovernanceRuleStatus.failed)
        .map((e) => '${e.ruleId}: ${e.explanation.summary}')
        .toList();
    final passedRules = snapshot.evaluations
        .where((e) => e.status == ReleaseGovernanceRuleStatus.passed)
        .map((e) => e.ruleId)
        .toList();
    final waivedRules = snapshot.evaluations
        .where((e) => e.status == ReleaseGovernanceRuleStatus.waived)
        .map((e) => e.ruleId)
        .toList();
    final pendingApprovals = snapshot.approvalEvaluations
        .where(
          (a) =>
              a.status == ReleaseApprovalEvaluationStatus.missing ||
              a.status == ReleaseApprovalEvaluationStatus.partiallySatisfied,
        )
        .map((a) => '${a.requirementId}:${a.approvalType.wireName}')
        .toList();
    final rejectedApprovals = snapshot.approvalEvaluations
        .where((a) => a.status == ReleaseApprovalEvaluationStatus.rejected)
        .map((a) => a.requirementId)
        .toList();
    final activeWaivers = snapshot.waiverEvaluations
        .where(
          (w) =>
              w.status == ReleaseWaiverStatus.active ||
              w.status == ReleaseWaiverStatus.approved,
        )
        .map((w) => w.waiverId)
        .toList();
    final invalidWaivers = snapshot.waiverEvaluations
        .where(
          (w) =>
              w.status == ReleaseWaiverStatus.expired ||
              w.status == ReleaseWaiverStatus.revoked ||
              w.status == ReleaseWaiverStatus.invalid,
        )
        .map((w) => '${w.waiverId}:${w.status.wireName}')
        .toList();
    final openConditions = snapshot.conditions
        .where((c) => c.status == ReleaseConditionStatus.open)
        .map((c) => '${c.conditionId}: ${c.description}')
        .toList();

    return ReleaseGovernanceReportInputData(
      snapshotId: meta.snapshotId,
      fingerprint: snapshot.fingerprint,
      decision: snapshot.decision.wireName,
      resultStatus: meta.resultStatus?.wireName,
      policyId: meta.policyId,
      policyVersion: meta.policyVersion,
      projectId: meta.projectId,
      releaseId: meta.releaseId,
      releaseVersion: meta.releaseVersion,
      commitId: meta.commitId,
      branch: meta.branch,
      environment: meta.environment.wireName,
      releaseType: meta.releaseType.wireName,
      qualityGateSnapshotId: meta.qualityGateSnapshotId,
      qualityGateFingerprint: meta.qualityGateFingerprint,
      compatibility: snapshot.compatibility.status.wireName,
      eligibility: snapshot.eligibility.status.wireName,
      requiredRuleCoveragePercentage:
          snapshot.coverage.requiredRuleCoveragePercentage,
      overallRuleCoveragePercentage: snapshot.coverage.ruleCoveragePercentage,
      failedRules: failedRules,
      passedRules: passedRules,
      waivedRules: waivedRules,
      approvalSummaries: snapshot.approvalEvaluations
          .map((a) => '${a.requirementId}: ${a.status.wireName}')
          .toList(),
      pendingApprovals: pendingApprovals,
      rejectedApprovals: rejectedApprovals,
      waiverSummaries: snapshot.waiverEvaluations
          .map((w) => '${w.waiverId}: ${w.status.wireName}')
          .toList(),
      activeWaivers: activeWaivers,
      invalidWaivers: invalidWaivers,
      openConditions: openConditions,
      evidenceSummaries: snapshot.evidence
          .map((e) => '${e.evidenceId}:${e.evidenceType.wireName}')
          .toList(),
      sourceSummaries: snapshot.sourceReferences
          .map(
            (r) => '${r.sourceType.wireName}:${r.resolvedId ?? r.requestedId}',
          )
          .toList(),
      limitations: snapshot.limitations.map((l) => l.description).toList(),
      warnings: snapshot.warnings.map((w) => w.message).toList(),
      errors: snapshot.errors.map((e) => e.message).toList(),
    );
  }

  ReleaseGovernanceReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(ReleaseDecisionSnapshot.fromJson(json));
  }
}
