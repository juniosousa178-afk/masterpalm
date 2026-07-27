import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_evidence.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_policy.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_decision_aggregator.dart';
import 'package:test/test.dart';

QualityGateEvaluation _eval({
  required String id,
  QualityGateRuleStatus status = QualityGateRuleStatus.passed,
  QualityGateRuleSeverity severity = QualityGateRuleSeverity.blocking,
  QualityGateRuleRequirement requirement = QualityGateRuleRequirement.required,
  QualityGateDecisionImpact impact = QualityGateDecisionImpact.none,
}) {
  return QualityGateEvaluation(
    ruleId: id,
    ruleSetId: 'rs',
    status: status,
    severity: severity,
    requirement: requirement,
    decisionImpact: impact,
    target: QualityGateRuleTarget.guardianDecision,
    operator: QualityGateRuleOperator.exists,
    explanation: QualityGateExplanation(
      explanationId: 'exp-$id',
      summary: 's',
      detail: 'd',
      ruleExplanation: 'r',
      decisionExplanation: 'de',
      evidenceExplanation: 'e',
      impactExplanation: 'i',
      templateId: 't',
    ),
    evidence: const [],
    evaluationFingerprint: 'fp-$id',
  );
}

void main() {
  const aggregator = QualityGateDecisionAggregator();
  const policy = QualityGateDecisionPolicy();
  const compatibility = QualityGateCompatibility(
    status: QualityGateCompatibilityStatus.compatible,
    checks: [],
    compatibleSources: [],
    partiallyCompatibleSources: [],
    incompatibleSources: [],
    unknownSources: [],
    reasons: [],
    compatibilityFingerprint: 'c',
  );
  const eligibility = QualityGateEligibility(
    status: QualityGateEligibilityStatus.eligible,
    reasons: [],
    requiredSources: [],
    availableSources: [],
    missingSources: [],
    incompatibleSources: [],
    eligibilityFingerprint: 'e',
  );
  const coverage = QualityGateCoverage(
    totalRuleCount: 1,
    enabledRuleCount: 1,
    evaluatedRuleCount: 1,
    passedRuleCount: 1,
    failedRuleCount: 0,
    unavailableRuleCount: 0,
    incompatibleRuleCount: 0,
    skippedRuleCount: 0,
    notApplicableRuleCount: 0,
    requiredRuleCount: 1,
    evaluatedRequiredRuleCount: 1,
    requiredRuleCoveragePercentage: 100,
    overallRuleCoveragePercentage: 100,
    evidenceCoveragePercentage: 100,
    sourceCoveragePercentage: 100,
    ruleSetCoverage: {},
    missingRuleIds: [],
    missingSourceTypes: [],
    limitations: [],
  );
  const summary = QualityGateSourceResolutionSummary(
    resolvedSources: [],
    missingSources: [],
    incompatibleSources: [],
  );

  group('QualityGateDecisionAggregator precedence', () {
    test('error beats failed', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _eval(id: 'QG003', status: QualityGateRuleStatus.failed),
          _eval(
            id: 'ERR',
            status: QualityGateRuleStatus.error,
            impact: QualityGateDecisionImpact.internalError,
          ),
        ],
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      expect(decision, QualityGateDecision.error);
    });

    test('incompatible structural beats failed', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: const QualityGateCompatibility(
          status: QualityGateCompatibilityStatus.incompatible,
          checks: [],
          compatibleSources: [],
          partiallyCompatibleSources: [],
          incompatibleSources: [QualityGateSourceType.mes],
          unknownSources: [],
          reasons: ['mismatch'],
          compatibilityFingerprint: 'c',
        ),
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _eval(id: 'QG003', status: QualityGateRuleStatus.failed),
        ],
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      expect(decision, QualityGateDecision.incompatible);
    });

    test('critical failure yields failed', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [
          _eval(
            id: 'QG003',
            status: QualityGateRuleStatus.failed,
            severity: QualityGateRuleSeverity.critical,
            impact: QualityGateDecisionImpact.blocksApproval,
          ),
        ],
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      expect(decision, QualityGateDecision.failed);
    });

    test('passed when no blocking conditions', () {
      final decision = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: [_eval(id: 'QG001')],
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      expect(decision, QualityGateDecision.passed);
    });

    test('order of evaluations does not change decision', () {
      final evals = [
        _eval(id: 'A', status: QualityGateRuleStatus.passed),
        _eval(
          id: 'B',
          status: QualityGateRuleStatus.failed,
          severity: QualityGateRuleSeverity.critical,
          impact: QualityGateDecisionImpact.blocksApproval,
        ),
      ];
      final d1 = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: evals,
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      final d2 = aggregator.aggregate(
        decisionPolicy: policy,
        compatibility: compatibility,
        eligibility: eligibility,
        coverage: coverage,
        evaluations: evals.reversed.toList(),
        ruleSetEvaluations: const [],
        sourceResolutionSummary: summary,
        errors: const [],
      );
      expect(d1, d2);
      expect(d1, QualityGateDecision.failed);
    });
  });
}
