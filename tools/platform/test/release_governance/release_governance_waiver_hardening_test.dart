import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_evidence.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_messages.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/models/release_governance/release_waiver.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_engine.dart';
import 'package:masterpalm_platform/release_governance/release_governance_source_resolver.dart';
import 'package:masterpalm_platform/release_governance/release_governance_waiver_evaluator.dart';
import 'package:masterpalm_platform/release_governance/release_waiver_validator.dart';
import 'package:test/test.dart';

import 'release_governance_source_resolver_test.dart';
import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance waiver hardening', () {
    const validator = ReleaseWaiverValidator();
    const waiverEvaluator = ReleaseGovernanceWaiverEvaluator();
    final policy = ReleaseGovernancePolicyV1.create();
    final context = ReleaseGovernanceTestFixtures.validContext();

    test('critical forbidden waiver for RG005 is rejected by validator', () {
      final waiver = ReleaseGovernanceTestFixtures.validWaiver();
      final bad = ReleaseWaiver(
        waiverId: waiver.waiverId,
        releaseId: waiver.releaseId,
        policyId: waiver.policyId,
        policyVersion: waiver.policyVersion,
        status: waiver.status,
        scope: ReleaseWaiverScope(
          projectId: context.projectId,
          releaseId: context.releaseId,
          commitId: context.commitId,
          environment: context.environment,
          releaseType: context.releaseType,
          policyId: policy.metadata.policyId,
          policyVersion: policy.metadata.policyVersion,
          ruleIds: const ['RG005'],
        ),
        authority: waiver.authority,
        issuerId: waiver.issuerId,
        issuedAt: waiver.issuedAt,
        expiration: waiver.expiration,
        justification: waiver.justification,
        compensatingControls: waiver.compensatingControls,
        evidence: waiver.evidence,
        affectedRuleIds: const ['RG005'],
        fingerprint: waiver.fingerprint,
        schemaVersion: waiver.schemaVersion,
      );

      final result = validator.validate(
        bad,
        releaseContext: context,
        policy: policy,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('RG005')),
        isTrue,
      );
    });

    test('waiverCapability forbidden prevents waiver application on RG005',
        () async {
      final rg005 = policy.rules.firstWhere((r) => r.ruleId == 'RG005');
      expect(
          rg005.waiverCapability, ReleaseGovernanceWaiverCapability.forbidden);

      final failedEval = ReleaseGovernanceEvaluation(
        evaluationId: 'eval-rg005',
        ruleId: 'RG005',
        ruleSetId: 'technical-gate',
        target: ReleaseGovernanceRuleTarget.qualityGateCompatibility,
        operator: ReleaseGovernanceRuleOperator.isCompatible,
        status: ReleaseGovernanceRuleStatus.failed,
        decisionImpact: ReleaseGovernanceDecisionImpact.causesRejection,
        explanation: const ReleaseGovernanceExplanation(
          explanationId: 'exp-rg005',
          type: ReleaseGovernanceExplanationType.ruleFailed,
          summary: 'incompatible',
          detail: 'detail',
          templateId: 'rule.failed',
        ),
        fingerprint: 'fp-rg005',
      );

      final waiverEvaluations = [
        ReleaseWaiverEvaluation(
          waiverId: 'waiver-rg005',
          status: ReleaseWaiverStatus.active,
          scopeValid: true,
          authorityValid: true,
          expirationValid: true,
          policyValid: true,
          releaseValid: true,
          commitValid: true,
          environmentValid: true,
          ruleCoverageValid: true,
          compensatingControlsValid: true,
          usageValid: true,
          affectedEvaluationIds: const ['eval-rg005'],
          decisionImpact:
              ReleaseGovernanceDecisionImpact.contributesToConditions,
          evidenceIds: const [],
          explanation: const ReleaseGovernanceExplanation(
            explanationId: 'exp-waiver',
            type: ReleaseGovernanceExplanationType.waiverAccepted,
            summary: 'accepted',
            detail: 'detail',
            templateId: 'waiver',
          ),
          fingerprint: 'fp-waiver',
        ),
      ];

      final applied = waiverEvaluator.applyWaivers(
        evaluations: [failedEval],
        waiverEvaluations: waiverEvaluations,
        policy: policy,
      );

      expect(applied.single.status, ReleaseGovernanceRuleStatus.failed);
      expect(applied.single.status, isNot(ReleaseGovernanceRuleStatus.waived));
      expect(applied.single.status, isNot(ReleaseGovernanceRuleStatus.passed));
    });

    test('valid waiver on RG007 yields waived not passed', () async {
      final engine = ReleaseGovernanceEngine();
      final resolver = ReleaseGovernanceSourceResolver(
        qualityGateProvider: FakeQualityGateProvider(),
      );

      final qg = ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();
      final lowCoverageJson = qg.toJson();
      final coverage = Map<String, dynamic>.from(
        lowCoverageJson['coverage'] as Map<String, dynamic>,
      );
      coverage['requiredRuleCoveragePercentage'] = 50;
      coverage['overallRuleCoveragePercentage'] = 50;
      lowCoverageJson['coverage'] = coverage;
      final lowCoverageQg = QualityGateSnapshot.fromJson(lowCoverageJson);

      final request = ReleaseGovernanceRequest(
        releaseContext: context,
        policyId: ReleaseGovernancePolicyV1.policyId,
        qualityGateSnapshot: lowCoverageQg,
        approvalSet: ReleaseGovernanceTestFixtures.productionApprovalSet(),
        waiverSet: ReleaseWaiverSet(
          releaseId: context.releaseId,
          fingerprint: 'fp-waiver-set',
          schemaVersion: 1,
          waivers: [ReleaseGovernanceTestFixtures.validWaiver()],
        ),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      final rg007 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'RG007');
      expect(rg007.status, ReleaseGovernanceRuleStatus.waived);
      expect(rg007.status, isNot(ReleaseGovernanceRuleStatus.passed));
      expect(
        result.snapshot!.decision,
        ReleaseGovernanceDecision.approvedWithConditions,
      );
    });

    test('waived status is distinct from passed in evaluations', () {
      expect(
        ReleaseGovernanceRuleStatus.waived,
        isNot(ReleaseGovernanceRuleStatus.passed),
      );
      expect(ReleaseGovernanceRuleStatus.waived.wireName, 'waived');
    });
  });
}
