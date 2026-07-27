import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  const validator = ReleaseGovernancePolicyValidator();

  group('ReleaseGovernancePolicyV1', () {
    late final policy = ReleaseGovernancePolicyV1.create();

    test('policy is valid', () {
      final result = validator.validate(policy);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('has 20 rules with unique IDs', () {
      expect(policy.rules, hasLength(20));
      expect(policy.rules.map((r) => r.ruleId).toSet(), hasLength(20));
      expect(policy.rules.first.ruleId, 'RG001');
      expect(policy.rules.last.ruleId, 'RG020');
    });

    test('has 7 rule sets', () {
      expect(policy.ruleSets, hasLength(7));
      expect(
        policy.ruleSets.map((s) => s.ruleSetId).toSet(),
        containsAll([
          'release-integrity',
          'technical-gate',
          'approval-governance',
          'waiver-governance',
          'environment-governance',
          'evidence-integrity',
          'final-authorization',
        ]),
      );
    });

    test('candidate status and owner', () {
      expect(policy.metadata.policyId, 'release-governance-v1');
      expect(policy.metadata.status, ReleaseGovernancePolicyStatus.candidate);
      expect(policy.metadata.owner, 'MasterPalm Engineering Governance');
    });

    test('production approvals present', () {
      final prod = policy.approvalRequirements.where(
        (r) =>
            r.enabled &&
            r.environmentScope.contains(ReleaseEnvironment.production) &&
            r.releaseTypeScope.contains(ReleaseType.production),
      );
      expect(prod.length, greaterThanOrEqualTo(3));
      expect(
        prod.map((r) => r.approvalType),
        containsAll([
          ReleaseApprovalType.engineering,
          ReleaseApprovalType.quality,
          ReleaseApprovalType.releaseManager,
        ]),
      );
    });

    test('critical waivers forbidden on integrity rules', () {
      final rg001 = policy.rules.firstWhere((r) => r.ruleId == 'RG001');
      final rg002 = policy.rules.firstWhere((r) => r.ruleId == 'RG002');
      final rg005 = policy.rules.firstWhere((r) => r.ruleId == 'RG005');
      expect(
          rg001.waiverCapability, ReleaseGovernanceWaiverCapability.forbidden);
      expect(
          rg002.waiverCapability, ReleaseGovernanceWaiverCapability.forbidden);
      expect(
          rg005.waiverCapability, ReleaseGovernanceWaiverCapability.forbidden);
    });

    test('waiver policy is conservative', () {
      expect(policy.waiverRules.criticalForbidden, isTrue);
      expect(policy.waiverRules.projectConsistencyForbidden, isTrue);
      expect(policy.waiverRules.commitConsistencyForbidden, isTrue);
      expect(policy.waiverRules.incompatibleSourcesForbidden, isTrue);
      expect(policy.waiverRules.expirationRequired, isTrue);
      expect(policy.waiverRules.singleUseForProduction, isTrue);
    });

    test('decision policy rejects failed quality gate', () {
      expect(
        policy.decisionPolicy.qualityGateRejectedDecisions,
        contains('failed'),
      );
      expect(
        policy.decisionPolicy.qualityGateAcceptedDecisions,
        isNot(contains('failed')),
      );
    });
  });
}
