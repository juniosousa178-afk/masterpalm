import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  group('ReleaseGovernanceProvider', () {
    late ReleaseGovernanceProvider provider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.releaseGovernance();
    });

    test('PlatformCore resolves ReleaseGovernanceProvider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.releaseGovernance(), isA<ReleaseGovernanceProvider>());
    });

    test('passing scenario returns success with approved decision', () async {
      final result = await provider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );

      expect(result.status, ReleaseGovernanceResultStatus.success);
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.decision, ReleaseGovernanceDecision.approved);
      expect(result.snapshot!.evaluations, isNotEmpty);
      expect(result.sourceResolutionSummary?.injectedSources, isNotEmpty);
    });

    test('rejected QG yields rejected decision with success result status',
        () async {
      final qg = ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();
      final failedQg = QualityGateSnapshot.fromJson(qg.toJson()
        ..['decision'] = 'failed'
        ..['metadata'] = {
          ...qg.metadata.toJson(),
          'decision': 'failed',
        });

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernancePolicyV1.policyId,
        qualityGateSnapshot: failedQg,
        approvalSet: ReleaseGovernanceTestFixtures.productionApprovalSet(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final result = await provider.evaluate(request);
      expect(result.status, ReleaseGovernanceResultStatus.success);
      expect(result.snapshot!.decision, ReleaseGovernanceDecision.rejected);
    });

    test('missing approvals yields pending decision', () async {
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernancePolicyV1.policyId,
        qualityGateSnapshot:
            ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final result = await provider.evaluate(request);
      expect(result.status, ReleaseGovernanceResultStatus.success);
      expect(result.snapshot!.decision, ReleaseGovernanceDecision.pending);
    });

    test('evaluateAndPublish stores snapshot idempotently', () async {
      final result = await provider.evaluateAndPublish(
        ReleaseGovernanceTestFixtures.passingRequest(publish: true),
      );

      expect(result.snapshot, isNotNull);
      final loaded = await provider.load(result.snapshot!.metadata.snapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, result.snapshot!.fingerprint);

      final second = await provider.evaluateAndPublish(
        ReleaseGovernanceTestFixtures.passingRequest(publish: true),
      );
      expect(second.snapshot!.metadata.snapshotId,
          result.snapshot!.metadata.snapshotId);
    });
  });
}
