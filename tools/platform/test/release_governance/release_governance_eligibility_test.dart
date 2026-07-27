import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_rule_value.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1_1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_engine.dart';
import 'package:masterpalm_platform/release_governance/release_governance_operator_evaluator.dart';
import 'package:masterpalm_platform/release_governance/release_governance_source_resolver.dart';
import 'package:test/test.dart';

import 'release_governance_source_resolver_test.dart';
import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance eligibility semantics', () {
    const operatorEvaluator = ReleaseGovernanceOperatorEvaluator();
    final engine = ReleaseGovernanceEngine();
    final resolver = ReleaseGovernanceSourceResolver(
      qualityGateProvider: FakeQualityGateProvider(),
    );

    QualityGateSnapshot ineligibleQgSnapshot() {
      final base = ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();
      final json = base.toJson();
      final eligibility = Map<String, dynamic>.from(
        json['eligibility'] as Map<String, dynamic>,
      );
      eligibility['status'] = QualityGateEligibilityStatus.ineligible.wireName;
      eligibility['reasons'] = ['metrics source missing'];
      json['eligibility'] = eligibility;
      return QualityGateSnapshot.fromJson(json);
    }

    test('isValid passes structural presence for ineligible enum value', () {
      final result = operatorEvaluator.evaluate(
        operator: ReleaseGovernanceRuleOperator.isValid,
        actualValue: const ReleaseGovernanceEnumValue(
          domain: 'eligibility',
          value: 'ineligible',
        ),
      );
      expect(result.passed, isTrue);
    });

    test('isEligible fails for ineligible enum value', () {
      final result = operatorEvaluator.evaluate(
        operator: ReleaseGovernanceRuleOperator.isEligible,
        actualValue: const ReleaseGovernanceEnumValue(
          domain: 'eligibility',
          value: 'ineligible',
        ),
      );
      expect(result.passed, isFalse);
    });

    test('v1 RG006 passes with ineligible quality gate snapshot', () async {
      final policy = ReleaseGovernancePolicyV1.create();
      final rg006 = policy.rules.firstWhere((r) => r.ruleId == 'RG006');
      expect(rg006.operator, ReleaseGovernanceRuleOperator.isValid);

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernancePolicyV1.policyId,
        qualityGateSnapshot: ineligibleQgSnapshot(),
        approvalSet: ReleaseGovernanceTestFixtures.productionApprovalSet(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      final rg006Eval =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'RG006');
      expect(rg006Eval.status, ReleaseGovernanceRuleStatus.passed);
    });

    test('v1.1 RG006 fails with ineligible quality gate snapshot', () async {
      final policy = ReleaseGovernancePolicyV11.create();
      final rg006 = policy.rules.firstWhere((r) => r.ruleId == 'RG006');
      expect(rg006.operator, ReleaseGovernanceRuleOperator.isEligible);

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernancePolicyV11.policyId,
        qualityGateSnapshot: ineligibleQgSnapshot(),
        approvalSet: ReleaseGovernanceTestFixtures.productionApprovalSet(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      final rg006Eval =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'RG006');
      expect(rg006Eval.status, ReleaseGovernanceRuleStatus.failed);
    });
  });
}
