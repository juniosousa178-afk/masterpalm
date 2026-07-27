import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:test/test.dart';

import '../quality_gate/support/quality_gate_snapshot_fixtures.dart';
import 'support/release_governance_test_fixtures.dart';

/// Documental semantics tests — domain invariants without engine execution.
void main() {
  group('Release Governance semantics', () {
    test(
        'approval request does not embed mutable quality gate snapshot mutation',
        () {
      final qgSnapshot = QualityGateSnapshotFixtures.minimal(
        decision: QualityGateDecision.passed,
      );
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        qualityGateSnapshot: qgSnapshot,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final originalJson = qgSnapshot.toJson();
      final copy = Map<String, dynamic>.from(originalJson);
      copy['decision'] = 'failed';
      expect(request.qualityGateSnapshot!.decision, QualityGateDecision.passed);
      expect(copy['decision'], 'failed');
    });

    test('waived is distinct from passed in rule status enum', () {
      expect(ReleaseGovernanceRuleStatus.waived,
          isNot(ReleaseGovernanceRuleStatus.passed));
      expect(ReleaseGovernanceRuleStatus.waived.wireName, 'waived');
    });

    test('rejected decision is not operational failure status', () {
      expect(ReleaseGovernanceDecision.rejected,
          isNot(ReleaseGovernanceDecision.error));
      expect(
        ReleaseGovernanceResultStatus.failure,
        isNot(ReleaseGovernanceResultStatus.success),
      );
    });

    test('approvedWithConditions requires conditions model support', () {
      expect(
        ReleaseGovernanceDecision.approvedWithConditions.wireName,
        'approvedWithConditions',
      );
      expect(ReleaseConditionStatus.open.wireName, 'open');
    });

    test('policy candidate is not active', () {
      final policy = ReleaseGovernancePolicyV1.create();
      expect(policy.metadata.status, ReleaseGovernancePolicyStatus.candidate);
      expect(
          policy.metadata.status, isNot(ReleaseGovernancePolicyStatus.active));
    });

    test('critical rules in v1 are waiver forbidden', () {
      final policy = ReleaseGovernancePolicyV1.create();
      final criticalRules = policy.rules.where(
        (r) => r.severity == ReleaseGovernanceRuleSeverity.critical,
      );
      for (final rule in criticalRules) {
        expect(
          rule.waiverCapability,
          isNot(ReleaseGovernanceWaiverCapability.allowed),
          reason: '${rule.ruleId} must not allow waiver',
        );
      }
    });

    test(
        'historicalEvaluation flag exists on request without authorizing by default',
        () {
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
        historicalEvaluation: true,
      );
      expect(request.historicalEvaluation, isTrue);
      expect(
        ReleaseGovernancePolicyV1.create()
            .decisionPolicy
            .allowHistoricalEvaluation,
        isFalse,
      );
    });
  });
}
