import 'package:masterpalm_platform/interfaces/quality_gate_provider.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_source_resolver.dart';
import 'package:masterpalm_platform/release_governance/resolved_release_governance_sources.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

class FakeQualityGateProvider implements QualityGateProvider {
  FakeQualityGateProvider({this.loaded, this.latestSnapshot});

  QualityGateSnapshot? loaded;
  QualityGateSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;

  @override
  Future<QualityGateResult> evaluate(QualityGateRequest request) async =>
      throw UnimplementedError();

  @override
  Future<QualityGateResult> evaluateAndPublish(
    QualityGateRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> publish(QualityGateSnapshot snapshot) async {}

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<QualityGateSnapshot>> query(query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

void main() {
  group('ReleaseGovernanceSourceResolver', () {
    late FakeQualityGateProvider qgProvider;
    late ReleaseGovernanceSourceResolver resolver;
    final policy = ReleaseGovernancePolicyV1.create();

    setUp(() {
      qgProvider = FakeQualityGateProvider();
      resolver = ReleaseGovernanceSourceResolver(
        qualityGateProvider: qgProvider,
      );
    });

    test('injected quality gate wins over byId and latest', () async {
      final injected =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();
      qgProvider.loaded =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(
        id: 'qg-store',
      );

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        qualityGateSnapshot: injected,
        qualityGateSnapshotId: 'qg-store',
        useLatest: true,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final resolved = await resolver.resolveQualityGateSnapshot(
        request,
        [],
        [],
      );
      expect(resolved.isAvailable, isTrue);
      expect(
        resolved.resolvedArtifact?.metadata.qualityGateSnapshotId,
        injected.metadata.qualityGateSnapshotId,
      );
      expect(
        resolved.resolutionMode,
        ReleaseGovernanceSourceResolutionMode.injected,
      );
      expect(qgProvider.loadCalls, 0);
      expect(qgProvider.latestCalls, 0);
    });

    test('byId loads when injected absent', () async {
      final stored = ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(
        id: 'qg-by-id',
      );
      qgProvider.loaded = stored;

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        qualityGateSnapshotId: 'qg-by-id',
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final resolved = await resolver.resolveQualityGateSnapshot(
        request,
        [],
        [],
      );
      expect(resolved.isAvailable, isTrue);
      expect(
          resolved.resolutionMode, ReleaseGovernanceSourceResolutionMode.byId);
      expect(qgProvider.loadCalls, 1);
    });

    test('byId not found does not fall back to latest', () async {
      qgProvider.latestSnapshot =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();

      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        qualityGateSnapshotId: 'qg-missing',
        useLatest: true,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );

      final resolved = await resolver.resolveQualityGateSnapshot(
        request,
        [],
        [],
      );
      expect(resolved.isAvailable, isFalse);
      expect(qgProvider.loadCalls, 1);
      expect(qgProvider.latestCalls, 0);
    });

    test('latest only when useLatest is true', () async {
      qgProvider.latestSnapshot =
          ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();

      final withLatest = await resolver.resolveQualityGateSnapshot(
        ReleaseGovernanceRequest(
          releaseContext: ReleaseGovernanceTestFixtures.validContext(),
          useLatest: true,
          referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
        ),
        [],
        [],
      );
      expect(withLatest.isAvailable, isTrue);
      expect(
        withLatest.resolutionMode,
        ReleaseGovernanceSourceResolutionMode.latest,
      );

      final withoutLatest = await resolver.resolveQualityGateSnapshot(
        ReleaseGovernanceRequest(
          releaseContext: ReleaseGovernanceTestFixtures.validContext(),
          useLatest: false,
          referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
        ),
        [],
        [],
      );
      expect(
        withoutLatest.state,
        ResolvedReleaseGovernanceSourceState.notRequested,
      );
    });

    test('resolveAll tracks injected and resolved sources', () async {
      final request = ReleaseGovernanceTestFixtures.passingRequest();
      final sources = await resolver.resolveAll(request, policy);

      expect(sources.releaseContext.isAvailable, isTrue);
      expect(sources.qualityGateSnapshot.isAvailable, isTrue);
      expect(sources.approvalSet.isAvailable, isTrue);
      expect(sources.resolutionSummary.injectedSources,
          contains('releaseContext'));
      expect(sources.resolutionSummary.injectedSources,
          contains('qualityGateSnapshot'));
      expect(sources.resolutionSummary.resolvedSources, isNotEmpty);
    });
  });
}
