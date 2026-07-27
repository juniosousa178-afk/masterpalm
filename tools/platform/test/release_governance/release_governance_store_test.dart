import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_evidence.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_policy.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_query.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_exceptions.dart';
import 'package:masterpalm_platform/release_governance/stores/in_memory_release_governance_store.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

ReleaseDecisionSnapshot _snapshot({
  required String id,
  String fingerprint = 'fp-1',
  ReleaseGovernanceDecision decision = ReleaseGovernanceDecision.approved,
  String evaluatedAt = ReleaseGovernanceTestFixtures.referenceTime,
}) {
  final policy = ReleaseGovernancePolicyV1.create();
  return ReleaseDecisionSnapshot(
    metadata: ReleaseDecisionSnapshotMetadata(
      snapshotId: id,
      projectId: ReleaseGovernanceTestFixtures.projectId,
      releaseId: ReleaseGovernanceTestFixtures.releaseId,
      releaseVersion: '1.0.0',
      commitId: ReleaseGovernanceTestFixtures.commitId,
      branch: 'main',
      environment: ReleaseEnvironment.production,
      releaseType: ReleaseType.production,
      policyId: policy.metadata.policyId,
      policyVersion: 1,
      policyFingerprint: 'fp-policy',
      qualityGateSnapshotId: 'qg-1',
      qualityGateFingerprint: 'fp-qg',
      schemaVersion: 1,
      calculationVersion: 1,
      canonicalizationVersion: 1,
      evaluatedAt: evaluatedAt,
      createdAt: evaluatedAt,
      decision: decision,
    ),
    releaseContext: ReleaseGovernanceTestFixtures.validContext(),
    policyReference: ReleaseGovernancePolicyReference(
      policyId: policy.metadata.policyId,
      policyVersion: 1,
      fingerprint: 'fp-policy',
    ),
    qualityGateReference: const ReleaseQualityGateReference(
      qualityGateSnapshotId: 'qg-1',
      qualityGateFingerprint: 'fp-qg',
      policyId: 'quality-gate-release-v1',
      policyVersion: 1,
      decision: 'passed',
    ),
    decision: decision,
    compatibility: ReleaseGovernanceCompatibility(
      status: ReleaseGovernanceCompatibilityStatus.compatible,
      checks: const [],
      compatibleSources: const [ReleaseGovernanceSourceType.releaseContext],
      partiallyCompatibleSources: const [],
      incompatibleSources: const [],
      unknownSources: const [],
      reasons: const [],
      compatibilityFingerprint: 'compat-1',
    ),
    eligibility: ReleaseGovernanceEligibility(
      status: ReleaseGovernanceEligibilityStatus.eligible,
      reasons: const [],
      missingSources: const [],
      incompatibleSources: const [],
      eligibilityFingerprint: 'elig-1',
    ),
    coverage: ReleaseGovernanceCoverage(
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
      evidenceRequiredCount: 1,
      evidencePresentCount: 1,
      ruleCoveragePercentage: 100,
      requiredRuleCoveragePercentage: 100,
      approvalCoveragePercentage: 100,
      evidenceCoveragePercentage: 100,
      sourceCoveragePercentage: 100,
      fingerprint: 'cov-1',
    ),
    fingerprint: fingerprint,
  );
}

void main() {
  group('InMemoryReleaseGovernanceStore', () {
    late InMemoryReleaseGovernanceStore store;

    setUp(() => store = InMemoryReleaseGovernanceStore());

    test('save load exists invalidate', () async {
      await store.save(_snapshot(id: 's1'));
      expect(await store.exists('s1'), isTrue);
      expect(await store.load('s1'), isNotNull);
      await store.invalidate('s1');
      expect(await store.exists('s1'), isFalse);
    });

    test('query filters by project and decision', () async {
      await store.save(_snapshot(
          id: 's-approved', decision: ReleaseGovernanceDecision.approved));
      await store.save(_snapshot(
          id: 's-rejected', decision: ReleaseGovernanceDecision.rejected));

      final approved = await store.query(
        const ReleaseGovernanceQuery(
          projectId: ReleaseGovernanceTestFixtures.projectId,
          decision: ReleaseGovernanceDecision.approved,
        ),
      );
      expect(approved.length, 1);
      expect(approved.first.metadata.snapshotId, 's-approved');
    });

    test('conflicting snapshot content throws', () async {
      await store.save(_snapshot(
          id: 's-conflict', decision: ReleaseGovernanceDecision.approved));
      expect(
        () => store.save(_snapshot(
            id: 's-conflict', decision: ReleaseGovernanceDecision.rejected)),
        throwsA(isA<ReleaseGovernanceSnapshotConflictException>()),
      );
    });
  });
}
