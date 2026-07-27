import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_engine.dart';
import 'package:masterpalm_platform/release_governance/release_governance_source_resolver.dart';
import 'package:test/test.dart';

import 'release_governance_source_resolver_test.dart';
import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance replay', () {
    late ReleaseGovernanceEngine engine;
    late ReleaseGovernanceSourceResolver resolver;
    final policy = ReleaseGovernancePolicyV1.create();

    setUp(() {
      engine = ReleaseGovernanceEngine();
      resolver = ReleaseGovernanceSourceResolver(
        qualityGateProvider: FakeQualityGateProvider(),
      );
    });

    test('toJson/fromJson preserves id fingerprint and decision', () async {
      final request = ReleaseGovernanceTestFixtures.passingRequest();
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      final original = result.snapshot!;

      final restored = ReleaseDecisionSnapshot.fromJson(original.toJson());

      expect(restored.metadata.snapshotId, original.metadata.snapshotId);
      expect(restored.fingerprint, original.fingerprint);
      expect(restored.decision, original.decision);
    });

    test('re-evaluate same inputs yields same id and fingerprint', () async {
      final request = ReleaseGovernanceTestFixtures.passingRequest();
      final sources = await resolver.resolveAll(request, policy);

      final first = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      final second = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );

      expect(first.snapshot, isNotNull);
      expect(second.snapshot, isNotNull);
      expect(
        second.snapshot!.metadata.snapshotId,
        first.snapshot!.metadata.snapshotId,
      );
      expect(second.snapshot!.fingerprint, first.snapshot!.fingerprint);
      expect(second.snapshot!.decision, first.snapshot!.decision);
      expect(
        second.snapshot!.metadata.policyFingerprint,
        first.snapshot!.metadata.policyFingerprint,
      );
    });

    test('round-trip preserves evaluation count and decision', () async {
      final request = ReleaseGovernanceTestFixtures.passingRequest();
      final sources = await resolver.resolveAll(request, policy);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      final roundTrip =
          ReleaseDecisionSnapshot.fromJson(result.snapshot!.toJson());
      expect(roundTrip.evaluations.length, result.snapshot!.evaluations.length);
      expect(roundTrip.decision, result.snapshot!.decision);
    });
  });
}
