import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_source_resolver.dart';
import 'package:masterpalm_platform/quality_gate/resolved_quality_gate_sources.dart';
import 'package:test/test.dart';

import '../score/score_fixtures.dart';
import 'support/quality_gate_test_fakes.dart';
import 'support/quality_gate_test_helpers.dart';

void main() {
  group('QualityGateSourceResolver', () {
    late FakeMetricsProvider metricsProvider;
    late FakeScoreProvider scoreProvider;
    late FakeMESProvider mesProvider;
    late FakeObservabilityProvider observabilityProvider;
    late FakeDashboardProvider dashboardProvider;
    late QualityGateSourceResolver resolver;

    setUp(() {
      metricsProvider = FakeMetricsProvider();
      scoreProvider = FakeScoreProvider();
      mesProvider = FakeMESProvider();
      observabilityProvider = FakeObservabilityProvider();
      dashboardProvider = FakeDashboardProvider();
      resolver = QualityGateSourceResolver(
        metricsProvider: metricsProvider,
        scoreProvider: scoreProvider,
        mesProvider: mesProvider,
        observabilityProvider: observabilityProvider,
        dashboardProvider: dashboardProvider,
      );
    });

    QualityGateRequest baseRequest({
      bool useLatest = false,
      String projectId = 'proj-a',
    }) {
      return QualityGateRequest(
        projectId: projectId,
        createdAt: '2026-01-01T10:00:00.000Z',
        referenceTime: '2026-01-01T10:00:01.000Z',
        useLatest: useLatest,
      );
    }

    test('injected metrics wins over byId and latest', () async {
      final injected = await QualityGateTestHelpers.minimalMetrics();
      metricsProvider.loaded = await QualityGateTestHelpers.minimalMetrics();

      final request = QualityGateRequest(
        projectId: 'proj-a',
        createdAt: '2026-01-01T10:00:00.000Z',
        referenceTime: '2026-01-01T10:00:01.000Z',
        metricsSnapshot: injected,
        metricsSnapshotId: 'metrics-store',
        useLatest: true,
      );

      final resolved = await resolver.resolveMetrics(request, [], [], []);
      expect(resolved.isAvailable, isTrue);
      expect(
        resolved.resolvedArtifact?.metadata.snapshotId,
        injected.metadata.snapshotId,
      );
      expect(resolved.resolutionMode, QualityGateSourceResolutionMode.injected);
      expect(metricsProvider.loadCalls, 0);
    });

    test('byId loads when injected absent', () async {
      final stored = await QualityGateTestHelpers.minimalMetrics();
      metricsProvider.loaded = stored;

      final request = baseRequest().copyWith(
        metricsSnapshotId: stored.metadata.snapshotId,
      );
      final resolved = await resolver.resolveMetrics(request, [], [], []);
      expect(resolved.isAvailable, isTrue);
      expect(resolved.resolutionMode, QualityGateSourceResolutionMode.byId);
      expect(metricsProvider.loadCalls, 1);
      expect(metricsProvider.calculateCalls, 0);
    });

    test('byId not found does not fall back to latest', () async {
      metricsProvider.loaded = await QualityGateTestHelpers.minimalMetrics();

      final request = baseRequest(useLatest: true)
          .copyWith(metricsSnapshotId: 'metrics-missing');
      final resolved = await resolver.resolveMetrics(request, [], [], []);
      expect(resolved.isAvailable, isFalse);
      expect(metricsProvider.loadCalls, 1);
    });

    test('latest only when useLatest is true', () async {
      metricsProvider.loaded = await QualityGateTestHelpers.minimalMetrics();

      final withLatest = await resolver.resolveMetrics(
        baseRequest(useLatest: true),
        [],
        [],
        [],
      );
      expect(withLatest.isAvailable, isTrue);
      expect(
        withLatest.resolutionMode,
        QualityGateSourceResolutionMode.latest,
      );

      final withoutLatest = await resolver.resolveMetrics(
        baseRequest(useLatest: false),
        [],
        [],
        [],
      );
      expect(
        withoutLatest.state,
        ResolvedQualityGateSourceState.notRequested,
      );
    });

    test('history is injection-only', () async {
      final request = baseRequest().copyWith(historyDiffId: 'hist-1');
      final resolved = resolver.resolveHistory(request, [], []);
      expect(resolved.isAvailable, isFalse);
      expect(resolved.state, ResolvedQualityGateSourceState.unavailable);
    });

    test('history diff injected is available', () async {
      final diff = QualityGateTestHelpers.minimalHistoryDiff();
      final request = baseRequest().copyWith(historyDiff: diff);
      final resolved = resolver.resolveHistory(request, [], []);
      expect(resolved.isAvailable, isTrue);
      expect(resolved.resolutionMode, QualityGateSourceResolutionMode.injected);
    });

    test('project mismatch adds compatibility hint', () async {
      final metrics = await QualityGateTestHelpers.minimalMetrics();
      final score = await QualityGateTestHelpers.minimalScore(
        projectId: 'other-project',
      );
      final mes = await QualityGateTestHelpers.minimalMes();

      final sources = await resolver.resolveAll(
        QualityGateRequest(
          projectId: 'proj-a',
          createdAt: '2026-01-01T10:00:00.000Z',
          referenceTime: '2026-01-01T10:00:01.000Z',
          metricsSnapshot: metrics,
          guardianAnalysis: QualityGateTestHelpers.guardianGo(),
          engineeringScoreSnapshot: score,
          mesSnapshot: mes,
        ),
      );

      expect(sources.compatibilityHints, isNotEmpty);
    });

    test('source resolution summary counts modes', () async {
      final metrics = await QualityGateTestHelpers.minimalMetrics();
      final score = await QualityGateTestHelpers.minimalScore();
      final mes = await QualityGateTestHelpers.minimalMes();

      final sources = await resolver.resolveAll(
        QualityGateRequest(
          projectId: 'proj-a',
          createdAt: '2026-01-01T10:00:00.000Z',
          referenceTime: '2026-01-01T10:00:01.000Z',
          metricsSnapshot: metrics,
          guardianAnalysis: QualityGateTestHelpers.guardianGo(),
          engineeringScoreSnapshot: score,
          mesSnapshot: mes,
        ),
      );

      expect(sources.resolutionSummary.injectedSourceCount, greaterThan(0));
      expect(sources.resolutionSummary.fingerprint, isNotEmpty);
    });

    test('resolveAll fingerprint stable regardless of ref collection order',
        () async {
      final metrics = await QualityGateTestHelpers.minimalMetrics();
      final score = await QualityGateTestHelpers.minimalScore();
      final mes = await QualityGateTestHelpers.minimalMes();
      final request = QualityGateRequest(
        projectId: 'proj-a',
        createdAt: '2026-01-01T10:00:00.000Z',
        referenceTime: '2026-01-01T10:00:01.000Z',
        metricsSnapshot: metrics,
        guardianAnalysis: QualityGateTestHelpers.guardianGo(),
        engineeringScoreSnapshot: score,
        mesSnapshot: mes,
      );

      final a = await resolver.resolveAll(request);
      final b = await resolver.resolveAll(request);
      expect(a.resolutionSummary.fingerprint, b.resolutionSummary.fingerprint);
    });

    test('no origin engine methods are invoked on resolveAll', () async {
      final metrics = await QualityGateTestHelpers.minimalMetrics();
      final score = await QualityGateTestHelpers.minimalScore();
      final mes = await QualityGateTestHelpers.minimalMes();
      await resolver.resolveAll(
        QualityGateRequest(
          projectId: ScoreFixtures.projectId,
          createdAt: '2026-01-01T10:00:00.000Z',
          referenceTime: '2026-01-01T10:00:01.000Z',
          metricsSnapshot: metrics,
          guardianAnalysis: QualityGateTestHelpers.guardianGo(),
          engineeringScoreSnapshot: score,
          mesSnapshot: mes,
          useLatest: true,
        ),
      );

      expect(metricsProvider.calculateCalls, 0);
      expect(scoreProvider.calculateCalls, 0);
      expect(mesProvider.calculateCalls, 0);
      expect(observabilityProvider.captureCalls, 0);
      expect(dashboardProvider.buildCalls, 0);
    });

    test('recoverable provider load error surfaces as unavailable', () async {
      metricsProvider.throwOnLoad = true;
      metricsProvider.recoverableLoadError = true;

      final request = baseRequest().copyWith(metricsSnapshotId: 'm-1');
      expect(
        () => resolver.resolveMetrics(request, [], [], []),
        throwsA(isA<StateError>()),
      );
    });
  });
}

extension on QualityGateRequest {
  QualityGateRequest copyWith({
    String? metricsSnapshotId,
    bool? useLatest,
    dynamic historyDiff,
    String? historyDiffId,
  }) {
    return QualityGateRequest(
      projectId: projectId,
      createdAt: createdAt,
      referenceTime: referenceTime,
      useLatest: useLatest ?? this.useLatest,
      metricsSnapshot: metricsSnapshot,
      metricsSnapshotId: metricsSnapshotId ?? this.metricsSnapshotId,
      guardianAnalysis: guardianAnalysis,
      engineeringScoreSnapshot: engineeringScoreSnapshot,
      mesSnapshot: mesSnapshot,
      historyDiff: historyDiff ?? this.historyDiff,
      historyDiffId: historyDiffId ?? this.historyDiffId,
    );
  }
}
