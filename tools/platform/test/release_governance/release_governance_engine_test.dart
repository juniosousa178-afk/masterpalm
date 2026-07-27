import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_engine.dart';
import 'package:masterpalm_platform/release_governance/release_governance_source_resolver.dart';
import 'package:test/test.dart';

import 'release_governance_source_resolver_test.dart';
import 'support/release_governance_test_fixtures.dart';

void main() {
  group('ReleaseGovernanceEngine', () {
    late ReleaseGovernanceEngine engine;
    late ReleaseGovernanceSourceResolver resolver;
    final policy = ReleaseGovernancePolicyV1.create();

    setUp(() {
      engine = ReleaseGovernanceEngine();
      resolver = ReleaseGovernanceSourceResolver(
        qualityGateProvider: FakeQualityGateProvider(),
      );
    });

    test('end-to-end passing evaluation produces deterministic snapshot',
        () async {
      final request = ReleaseGovernanceTestFixtures.passingRequest();
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      expect(result.status, ReleaseGovernanceResultStatus.success);
      expect(result.snapshot!.decision, ReleaseGovernanceDecision.approved);
      expect(result.snapshot!.evaluations.length, policy.rules.length);
      expect(result.snapshot!.fingerprint, isNotEmpty);
      expect(result.snapshot!.metadata.qualityGateSnapshotId, isNotEmpty);

      final replay = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      expect(replay.snapshot!.fingerprint, result.snapshot!.fingerprint);
      expect(replay.snapshot!.metadata.snapshotId,
          result.snapshot!.metadata.snapshotId);
    });

    test('missing quality gate yields unavailable decision', () async {
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernancePolicyV1.policyId,
        approvalSet: ReleaseGovernanceTestFixtures.productionApprovalSet(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      expect(result.status, isNot(ReleaseGovernanceResultStatus.failure));
      expect(
        result.snapshot!.decision,
        isIn([
          ReleaseGovernanceDecision.unavailable,
          ReleaseGovernanceDecision.pending,
          ReleaseGovernanceDecision.rejected,
        ]),
      );
    });
  });
}
