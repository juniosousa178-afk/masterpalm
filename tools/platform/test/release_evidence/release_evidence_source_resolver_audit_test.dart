import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_source_resolver.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence source resolver audit', () {
    late FakeQualityGateProviderForEvidence qgProvider;
    late FakeReleaseGovernanceProviderForEvidence rgProvider;
    late ReleaseEvidenceSourceResolver resolver;

    setUp(() {
      qgProvider = FakeQualityGateProviderForEvidence();
      rgProvider = FakeReleaseGovernanceProviderForEvidence();
      resolver = ReleaseEvidenceSourceResolver(
        qualityGateProvider: qgProvider,
        releaseGovernanceProvider: rgProvider,
      );
    });

    test('injected quality gate wins over byId and latest', () async {
      final injected = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      qgProvider.loaded =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(
        id: 'qg-store',
      );
      qgProvider.latestSnapshot = injected;

      final request = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        qualityGateSnapshot: injected,
        qualityGateSnapshotId: 'qg-store',
        useLatest: true,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedEvidencePolicy: ReleaseEvidencePolicyV1.create(),
      );

      expect(qgProvider.loadCalls, 0);
      expect(qgProvider.latestCalls, 0);
      expect(qgProvider.evaluateCalls, 0);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseEvidenceSourceResolutionMode.injected,
      );
    });

    test('byId resolves when injected absent', () async {
      final stored = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      qgProvider.loaded = stored;

      final request = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        qualityGateSnapshotId: stored.metadata.qualityGateSnapshotId,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(request);
      expect(qgProvider.loadCalls, 1);
      expect(sources.qualityGateSnapshot.isAvailable, isTrue);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseEvidenceSourceResolutionMode.byId,
      );
    });

    test('latest only when useLatest is true', () async {
      final latest = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      qgProvider.latestSnapshot = latest;

      final withLatest = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        useLatest: true,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      final withoutLatest = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      final resolvedLatest = await resolver.resolveAll(withLatest);
      final resolvedNone = await resolver.resolveAll(withoutLatest);

      expect(qgProvider.latestCalls, 1);
      expect(resolvedLatest.qualityGateSnapshot.isAvailable, isTrue);
      expect(resolvedNone.qualityGateSnapshot.state,
          ResolvedReleaseEvidenceSourceState.notRequested);
    });

    test('missing byId does not fall back to latest implicitly', () async {
      qgProvider.latestSnapshot =
          ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();

      final request = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        qualityGateSnapshotId: 'missing-qg',
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      final sources = await resolver.resolveAll(request);
      expect(qgProvider.latestCalls, 0);
      expect(sources.qualityGateSnapshot.isAvailable, isFalse);
    });

    test('resolver never calls origin evaluate', () async {
      await resolver.resolveAll(ReleaseEvidenceTestFixtures.passingRequest());
      expect(qgProvider.evaluateCalls, 0);
      expect(rgProvider.evaluateCalls, 0);
    });
  });
}
