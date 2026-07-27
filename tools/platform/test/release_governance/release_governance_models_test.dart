import 'package:masterpalm_platform/models/release_governance/release_context.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_evidence.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_policy.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_rule_value.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance models', () {
    test('ReleaseContext roundtrip', () {
      final context = ReleaseGovernanceTestFixtures.validContext();
      final restored = ReleaseContext.fromJson(context.toJson());
      expect(restored.releaseId, context.releaseId);
      expect(restored.environment, ReleaseEnvironment.production);
      expect(restored.artifactReferences, hasLength(1));
    });

    test('ReleaseGovernancePolicy roundtrip', () {
      final policy = ReleaseGovernancePolicyV1.create();
      final restored = ReleaseGovernancePolicy.fromJson(policy.toJson());
      expect(restored.metadata.policyId, ReleaseGovernancePolicyV1.policyId);
      expect(restored.rules, hasLength(20));
      expect(restored.ruleSets, hasLength(7));
    });

    test('enum roundtrip', () {
      expect(
        ReleaseGovernanceDecisionX.fromWireName('approved'),
        ReleaseGovernanceDecision.approved,
      );
      expect(
        ReleaseEnvironmentX.fromWireName('production'),
        ReleaseEnvironment.production,
      );
    });

    test('rule values reject non-finite decimal', () {
      expect(
        () => ReleaseGovernanceDecimalValue.fromJson({
          'valueKind': 'decimal',
          'value': double.nan,
        }),
        throwsFormatException,
      );
    });

    test('percentage rejects out of range', () {
      expect(
        () => ReleaseGovernancePercentageValue.fromJson({
          'valueKind': 'percentage',
          'value': 150,
        }),
        throwsFormatException,
      );
    });

    test('ReleaseGovernanceRequest roundtrip', () {
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policy: ReleaseGovernancePolicyV1.create(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final restored = ReleaseGovernanceRequest.fromJson(request.toJson());
      expect(restored.referenceTime, request.referenceTime);
      expect(restored.policy?.metadata.policyId,
          ReleaseGovernancePolicyV1.policyId);
    });

    test('ReleaseGovernanceResult distinguishes status from decision', () {
      final result = ReleaseGovernanceResult(
        status: ReleaseGovernanceResultStatus.success,
        snapshot: _minimalSnapshot(ReleaseGovernanceDecision.rejected),
      );
      expect(result.status, ReleaseGovernanceResultStatus.success);
      expect(result.snapshot!.decision, ReleaseGovernanceDecision.rejected);
    });

    test('ReleaseDecisionSnapshot roundtrip', () {
      final snapshot = _minimalSnapshot(ReleaseGovernanceDecision.pending);
      final restored = ReleaseDecisionSnapshot.fromJson(snapshot.toJson());
      expect(restored.decision, ReleaseGovernanceDecision.pending);
      expect(restored.qualityGateReference.qualityGateSnapshotId, isNotEmpty);
    });

    test('set value toJson canonicalizes without mutating input', () {
      final values = ['b', 'a'];
      final setValue = ReleaseGovernanceSetValue(values);
      expect(values, ['b', 'a']);
      expect(setValue.toJson()['values'], ['a', 'b']);
    });
  });
}

ReleaseDecisionSnapshot _minimalSnapshot(ReleaseGovernanceDecision decision) {
  final context = ReleaseGovernanceTestFixtures.validContext();
  return ReleaseDecisionSnapshot(
    metadata: ReleaseDecisionSnapshotMetadata(
      snapshotId: 'snap-001',
      projectId: context.projectId,
      releaseId: context.releaseId,
      releaseVersion: context.releaseVersion,
      commitId: context.commitId,
      branch: context.branch,
      environment: context.environment,
      releaseType: context.releaseType,
      policyId: ReleaseGovernancePolicyV1.policyId,
      policyVersion: 1,
      policyFingerprint: 'fp-policy',
      qualityGateSnapshotId: 'qg-snap-001',
      qualityGateFingerprint: 'fp-qg',
      schemaVersion: 1,
      calculationVersion: 1,
      canonicalizationVersion: 1,
      evaluatedAt: ReleaseGovernanceTestFixtures.referenceTime,
      createdAt: ReleaseGovernanceTestFixtures.referenceTime,
      decision: decision,
    ),
    releaseContext: context,
    policyReference: const ReleaseGovernancePolicyReference(
      policyId: ReleaseGovernancePolicyV1.policyId,
      policyVersion: 1,
      fingerprint: 'fp-policy',
    ),
    qualityGateReference: const ReleaseQualityGateReference(
      qualityGateSnapshotId: 'qg-snap-001',
      qualityGateFingerprint: 'fp-qg',
      policyId: 'quality-gate-release-v1',
      policyVersion: 1,
      decision: 'passed',
    ),
    decision: decision,
    compatibility: const ReleaseGovernanceCompatibility(
      status: ReleaseGovernanceCompatibilityStatus.compatible,
      checks: [],
      compatibleSources: [],
      partiallyCompatibleSources: [],
      incompatibleSources: [],
      unknownSources: [],
      reasons: [],
      compatibilityFingerprint: 'fp-compat',
    ),
    eligibility: const ReleaseGovernanceEligibility(
      status: ReleaseGovernanceEligibilityStatus.eligible,
      reasons: [],
      missingSources: [],
      incompatibleSources: [],
      eligibilityFingerprint: 'fp-elig',
    ),
    coverage: const ReleaseGovernanceCoverage(
      totalRuleCount: 20,
      enabledRuleCount: 20,
      evaluatedRuleCount: 20,
      passedRuleCount: 18,
      failedRuleCount: 2,
      pendingRuleCount: 0,
      waivedRuleCount: 0,
      unavailableRuleCount: 0,
      incompatibleRuleCount: 0,
      requiredRuleCount: 18,
      requiredRuleEvaluatedCount: 18,
      approvalRequirementCount: 3,
      approvalRequirementSatisfiedCount: 1,
      waiverEvaluationCount: 0,
      validWaiverCount: 0,
      evidenceRequiredCount: 10,
      evidencePresentCount: 10,
      ruleCoveragePercentage: 100,
      requiredRuleCoveragePercentage: 100,
      approvalCoveragePercentage: 33.3,
      evidenceCoveragePercentage: 100,
      sourceCoveragePercentage: 100,
      fingerprint: 'fp-coverage',
    ),
    fingerprint: 'fp-snapshot',
  );
}
