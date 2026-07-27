import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_evidence.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_governance.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';

/// Minimal deterministic snapshots for report, dashboard and golden tests.
class QualityGateSnapshotFixtures {
  static const sentinelSecret = 'SECRET_TOKEN_SHOULD_NOT_APPEAR';

  static QualityGateSnapshot minimal({
    String id = 'qg-test-1',
    String fingerprint = 'fp-test-1',
    QualityGateDecision decision = QualityGateDecision.error,
    List<QualityGateEvaluation> evaluations = const [],
    List<QualityGateError> errors = const [],
    List<QualityGateLimitation> limitations = const [],
  }) {
    return QualityGateSnapshot(
      metadata: QualityGateSnapshotMetadata(
        qualityGateSnapshotId: id,
        qualityGateFingerprint: fingerprint,
        requestFingerprint: 'req-test-1',
        policyFingerprint: 'pol-test-1',
        projectId: 'demo-project',
        schemaVersion: 1,
        calculationVersion: 1,
        canonicalizationVersion: 1,
        createdAt: '2026-01-01T00:00:00.000Z',
        evaluatedAt: '2026-01-01T00:00:01.000Z',
        decision: decision,
        policyId: QualityGateReleasePolicyV1.policyId,
        policyVersion: 1,
        totalRuleCount: evaluations.length,
        evaluatedRuleCount: evaluations.length,
        failedRuleCount: evaluations
            .where((e) => e.status == QualityGateRuleStatus.failed)
            .length,
        blockingFailureCount: evaluations
            .where(
              (e) =>
                  e.status == QualityGateRuleStatus.failed &&
                  e.severity == QualityGateRuleSeverity.blocking,
            )
            .length,
        warningCount: 0,
        errorCount: errors.length,
        sourceCount: 4,
      ),
      policyReference: const QualityGatePolicyVersion(
        policyId: QualityGateReleasePolicyV1.policyId,
        policyVersion: 1,
        schemaVersion: 1,
        calculationVersion: 1,
        canonicalizationVersion: 1,
      ),
      decision: decision,
      eligibility: const QualityGateEligibility(
        status: QualityGateEligibilityStatus.eligible,
        reasons: [],
        requiredSources: [QualityGateSourceType.metrics],
        availableSources: [
          QualityGateSourceType.metrics,
          QualityGateSourceType.guardian,
          QualityGateSourceType.score,
          QualityGateSourceType.mes,
        ],
        missingSources: [],
        incompatibleSources: [],
        eligibilityFingerprint: 'elig-test-1',
      ),
      compatibility: const QualityGateCompatibility(
        status: QualityGateCompatibilityStatus.compatible,
        checks: [],
        compatibleSources: [
          QualityGateSourceType.metrics,
          QualityGateSourceType.guardian,
          QualityGateSourceType.score,
          QualityGateSourceType.mes,
        ],
        partiallyCompatibleSources: [],
        incompatibleSources: [],
        unknownSources: [],
        reasons: [],
        compatibilityFingerprint: 'compat-test-1',
      ),
      coverage: QualityGateCoverage(
        totalRuleCount: evaluations.isEmpty ? 1 : evaluations.length,
        enabledRuleCount: evaluations.isEmpty ? 1 : evaluations.length,
        evaluatedRuleCount: evaluations.isEmpty ? 1 : evaluations.length,
        passedRuleCount: evaluations
            .where((e) => e.status == QualityGateRuleStatus.passed)
            .length,
        failedRuleCount: evaluations
            .where((e) => e.status == QualityGateRuleStatus.failed)
            .length,
        unavailableRuleCount: evaluations
            .where((e) => e.status == QualityGateRuleStatus.unavailable)
            .length,
        incompatibleRuleCount: 0,
        skippedRuleCount: 0,
        notApplicableRuleCount: 0,
        requiredRuleCount: evaluations.isEmpty ? 1 : evaluations.length,
        evaluatedRequiredRuleCount:
            evaluations.isEmpty ? 1 : evaluations.length,
        requiredRuleCoveragePercentage: 100,
        overallRuleCoveragePercentage: 100,
        evidenceCoveragePercentage: 100,
        sourceCoveragePercentage: 100,
        ruleSetCoverage: const {},
        missingRuleIds: const [],
        missingSourceTypes: const [],
        limitations: const [],
      ),
      evaluations: evaluations,
      ruleSetEvaluations: const [],
      evidence: const [],
      sourceReferences: const [],
      explanations: const [],
      warnings: const [],
      errors: errors,
      limitations: limitations,
    );
  }

  static QualityGateEvaluation evaluation({
    required String ruleId,
    QualityGateRuleStatus status = QualityGateRuleStatus.failed,
    QualityGateRuleSeverity severity = QualityGateRuleSeverity.blocking,
    QualityGateRuleRequirement requirement =
        QualityGateRuleRequirement.required,
  }) {
    return QualityGateEvaluation(
      ruleId: ruleId,
      ruleSetId: 'test-set',
      requirement: requirement,
      severity: severity,
      status: status,
      decisionImpact: status == QualityGateRuleStatus.failed
          ? QualityGateDecisionImpact.blocksApproval
          : QualityGateDecisionImpact.none,
      target: QualityGateRuleTarget.guardianDecision,
      operator: QualityGateRuleOperator.exists,
      evidence: const [],
      explanation: QualityGateExplanation(
        explanationId: '$ruleId-exp',
        summary: '$ruleId summary',
        detail: '$ruleId detail',
        ruleExplanation: '$ruleId rule',
        decisionExplanation: '$ruleId decision',
        evidenceExplanation: '$ruleId evidence',
        impactExplanation: '$ruleId impact',
        templateId: 'test',
      ),
      evaluationFingerprint: 'eval-$ruleId',
    );
  }
}
