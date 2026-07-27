import 'package:masterpalm_platform/models/release_governance/release_approval.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_evidence.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_messages.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_policy.dart';
import 'package:masterpalm_platform/release_governance/release_governance_decision_aggregator.dart';
import 'package:test/test.dart';

ReleaseGovernanceEvaluation _ruleEval({
  required String id,
  ReleaseGovernanceRuleStatus status = ReleaseGovernanceRuleStatus.passed,
  ReleaseGovernanceRuleSeverity severity =
      ReleaseGovernanceRuleSeverity.blocking,
  ReleaseGovernanceDecisionImpact impact = ReleaseGovernanceDecisionImpact.none,
}) {
  return ReleaseGovernanceEvaluation(
    evaluationId: 'eval-$id',
    ruleId: id,
    ruleSetId: 'rs',
    target: ReleaseGovernanceRuleTarget.qualityGateDecision,
    operator: ReleaseGovernanceRuleOperator.exists,
    status: status,
    decisionImpact: impact,
    explanation: ReleaseGovernanceExplanation(
      explanationId: 'exp-$id',
      type: ReleaseGovernanceExplanationType.rulePassed,
      summary: 'summary',
      detail: 'detail',
      templateId: 't',
    ),
    fingerprint: 'fp-$id',
  );
}

ReleaseApprovalEvaluation _approvalEval({
  required String id,
  ReleaseApprovalEvaluationStatus status =
      ReleaseApprovalEvaluationStatus.satisfied,
}) {
  return ReleaseApprovalEvaluation(
    requirementId: id,
    approvalType: ReleaseApprovalType.engineering,
    requiredCount: 1,
    validCount: status == ReleaseApprovalEvaluationStatus.satisfied ? 1 : 0,
    missingCount: status == ReleaseApprovalEvaluationStatus.missing ? 1 : 0,
    expiredCount: status == ReleaseApprovalEvaluationStatus.expired ? 1 : 0,
    rejectedCount: status == ReleaseApprovalEvaluationStatus.rejected ? 1 : 0,
    duplicateCount: 0,
    authorityInvalidCount: 0,
    separationOfDutiesSatisfied: true,
    status: status,
    approvalIds: const [],
    evidenceIds: const [],
    explanation: ReleaseGovernanceExplanation(
      explanationId: 'exp-approval-$id',
      type: ReleaseGovernanceExplanationType.approvalSatisfied,
      summary: 'approval',
      detail: 'detail',
      templateId: 'approval',
    ),
    fingerprint: 'fp-approval-$id',
  );
}

void main() {
  const aggregator = ReleaseGovernanceDecisionAggregator();
  const policy = ReleaseGovernanceDecisionPolicy();
  const compatibility = ReleaseGovernanceCompatibility(
    status: ReleaseGovernanceCompatibilityStatus.compatible,
    checks: [],
    compatibleSources: [],
    partiallyCompatibleSources: [],
    incompatibleSources: [],
    unknownSources: [],
    reasons: [],
    compatibilityFingerprint: 'compat',
  );
  const eligibility = ReleaseGovernanceEligibility(
    status: ReleaseGovernanceEligibilityStatus.eligible,
    reasons: [],
    missingSources: [],
    incompatibleSources: [],
    eligibilityFingerprint: 'elig',
  );
  const coverage = ReleaseGovernanceCoverage(
    totalRuleCount: 1,
    enabledRuleCount: 1,
    evaluatedRuleCount: 1,
    passedRuleCount: 1,
    failedRuleCount: 0,
    pendingRuleCount: 0,
    waivedRuleCount: 0,
    unavailableRuleCount: 0,
    incompatibleRuleCount: 0,
    requiredRuleCount: 1,
    requiredRuleEvaluatedCount: 1,
    approvalRequirementCount: 1,
    approvalRequirementSatisfiedCount: 1,
    waiverEvaluationCount: 0,
    validWaiverCount: 0,
    evidenceRequiredCount: 0,
    evidencePresentCount: 0,
    ruleCoveragePercentage: 100,
    requiredRuleCoveragePercentage: 100,
    approvalCoveragePercentage: 100,
    evidenceCoveragePercentage: 100,
    sourceCoveragePercentage: 100,
    fingerprint: 'cov',
  );

  group('ReleaseGovernanceDecisionAggregator precedence', () {
    test('non-recoverable error beats rejected blocking failure', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG004',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.blocksApproval,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: [
          ReleaseGovernanceError(
            errorId: 'err-1',
            code: ReleaseGovernanceErrorCode.evaluationFailure,
            message: 'fatal',
            recoverable: false,
            classification: 'internal',
          ),
        ],
      );
      expect(decision, ReleaseGovernanceDecision.error);
    });

    test('internalError impact beats rejected critical failure', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG004',
            status: ReleaseGovernanceRuleStatus.failed,
            severity: ReleaseGovernanceRuleSeverity.critical,
            impact: ReleaseGovernanceDecisionImpact.causesRejection,
          ),
          _ruleEval(
            id: 'ERR',
            status: ReleaseGovernanceRuleStatus.error,
            impact: ReleaseGovernanceDecisionImpact.internalError,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.error);
    });

    test('incompatible structural beats rejected blocking failure', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: const ReleaseGovernanceCompatibility(
          status: ReleaseGovernanceCompatibilityStatus.incompatible,
          checks: [],
          compatibleSources: [],
          partiallyCompatibleSources: [],
          incompatibleSources: [
            ReleaseGovernanceSourceType.qualityGateSnapshot
          ],
          unknownSources: [],
          reasons: ['mismatch'],
          compatibilityFingerprint: 'c',
        ),
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG007',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.blocksApproval,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.incompatible);
    });

    test('rejected approval beats missing approval pending', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: const [],
        approvalEvaluations: [
          _approvalEval(
            id: 'eng',
            status: ReleaseApprovalEvaluationStatus.rejected,
          ),
          _approvalEval(
            id: 'qa',
            status: ReleaseApprovalEvaluationStatus.missing,
          ),
        ],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.rejected);
    });

    test('missing approval pending beats blocking rule failure', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG007',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.blocksApproval,
          ),
        ],
        approvalEvaluations: [
          _approvalEval(
            id: 'eng',
            status: ReleaseApprovalEvaluationStatus.missing,
          ),
        ],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.pending);
    });

    test('expired approval pending beats rejected blocking failure', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG007',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.blocksApproval,
          ),
        ],
        approvalEvaluations: [
          _approvalEval(
            id: 'eng',
            status: ReleaseApprovalEvaluationStatus.expired,
          ),
        ],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.pending);
    });

    test('ineligible with missing sources unavailable beats advisory failure',
        () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: const ReleaseGovernanceEligibility(
          status: ReleaseGovernanceEligibilityStatus.ineligible,
          reasons: ['missing'],
          missingSources: [ReleaseGovernanceSourceType.qualityGateSnapshot],
          incompatibleSources: [],
          eligibilityFingerprint: 'elig-bad',
        ),
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG010',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.advisory,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.unavailable);
    });

    test('critical failure rejection beats waived contributesToConditions', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG004',
            status: ReleaseGovernanceRuleStatus.failed,
            severity: ReleaseGovernanceRuleSeverity.critical,
            impact: ReleaseGovernanceDecisionImpact.causesRejection,
          ),
          _ruleEval(
            id: 'RG007',
            status: ReleaseGovernanceRuleStatus.waived,
            impact: ReleaseGovernanceDecisionImpact.contributesToConditions,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.rejected);
    });

    test('blocking failure rejection beats approvedWithConditions from waiver',
        () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG007',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.blocksApproval,
          ),
          _ruleEval(
            id: 'RG008',
            status: ReleaseGovernanceRuleStatus.waived,
            impact: ReleaseGovernanceDecisionImpact.contributesToConditions,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.rejected);
    });

    test('low required coverage unavailable beats satisfied approvals', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: ReleaseGovernanceCoverage(
          totalRuleCount: coverage.totalRuleCount,
          enabledRuleCount: coverage.enabledRuleCount,
          evaluatedRuleCount: coverage.evaluatedRuleCount,
          passedRuleCount: coverage.passedRuleCount,
          failedRuleCount: coverage.failedRuleCount,
          pendingRuleCount: coverage.pendingRuleCount,
          waivedRuleCount: coverage.waivedRuleCount,
          unavailableRuleCount: coverage.unavailableRuleCount,
          incompatibleRuleCount: coverage.incompatibleRuleCount,
          requiredRuleCount: coverage.requiredRuleCount,
          requiredRuleEvaluatedCount: coverage.requiredRuleEvaluatedCount,
          approvalRequirementCount: coverage.approvalRequirementCount,
          approvalRequirementSatisfiedCount:
              coverage.approvalRequirementSatisfiedCount,
          waiverEvaluationCount: coverage.waiverEvaluationCount,
          validWaiverCount: coverage.validWaiverCount,
          evidenceRequiredCount: coverage.evidenceRequiredCount,
          evidencePresentCount: coverage.evidencePresentCount,
          ruleCoveragePercentage: 50,
          requiredRuleCoveragePercentage: 50,
          approvalCoveragePercentage: coverage.approvalCoveragePercentage,
          evidenceCoveragePercentage: coverage.evidenceCoveragePercentage,
          sourceCoveragePercentage: coverage.sourceCoveragePercentage,
          fingerprint: 'cov-low',
        ),
        evaluations: const [],
        approvalEvaluations: [
          _approvalEval(id: 'eng'),
        ],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.unavailable);
    });

    test('advisory failure with warningMayCreateCondition yields conditional',
        () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _ruleEval(
            id: 'RG010',
            status: ReleaseGovernanceRuleStatus.failed,
            impact: ReleaseGovernanceDecisionImpact.advisory,
          ),
        ],
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(decision, ReleaseGovernanceDecision.approvedWithConditions);
    });

    test('evaluation order does not change final decision', () {
      final evals = [
        _ruleEval(id: 'A', status: ReleaseGovernanceRuleStatus.passed),
        _ruleEval(
          id: 'B',
          status: ReleaseGovernanceRuleStatus.failed,
          severity: ReleaseGovernanceRuleSeverity.critical,
          impact: ReleaseGovernanceDecisionImpact.causesRejection,
        ),
      ];
      final d1 = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: evals,
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      final d2 = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: evals.reversed.toList(),
        approvalEvaluations: const [],
        waiverEvaluations: const [],
        conditions: const [],
        errors: const [],
      );
      expect(d1, d2);
      expect(d1, ReleaseGovernanceDecision.rejected);
    });
  });
}
