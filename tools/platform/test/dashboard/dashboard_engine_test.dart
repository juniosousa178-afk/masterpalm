import 'dart:io';

import 'package:masterpalm_platform/dashboard/builders/overview_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_canonical_serializer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_exceptions.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_request_validator.dart';
import 'package:masterpalm_platform/dashboard/stores/in_memory_dashboard_store.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/mes/policies/mes_official_policy_v1.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import '../score/score_fixtures.dart';

void main() {
  const projectId = ScoreFixtures.projectId;
  const createdAt = ScoreFixtures.createdAtA;
  const referenceTime = '2026-01-02T12:00:00.000Z';

  group('Dashboard models', () {
    test('DashboardSnapshot round-trip JSON', () async {
      final snap = await _buildSnapshot();
      final roundTrip = DashboardSnapshot.fromJson(snap.toJson());
      expect(
        roundTrip.metadata.dashboardSnapshotId,
        snap.metadata.dashboardSnapshotId,
      );
      expect(roundTrip.sections.length, snap.sections.length);
    });

    test('toComparableJson excludes createdAt from metadata', () async {
      final snap = await _buildSnapshot();
      final comparable = snap.toComparableJson();
      final meta = comparable['metadata'] as Map<String, dynamic>;
      expect(meta.containsKey('createdAt'), isFalse);
    });
  });

  group('DashboardRequestValidator', () {
    const validator = DashboardRequestValidator();

    test('rejects empty projectId', () {
      final result = validator.validate(const DashboardRequest(
        projectId: '',
        createdAt: createdAt,
        referenceTime: referenceTime,
      ));
      expect(result.isValid, isFalse);
    });

    test('rejects inverted timeRange', () {
      final result = validator.validate(DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        timeRange:
            const DashboardTimeRange(from: '2026-02-01', to: '2026-01-01'),
      ));
      expect(result.isValid, isFalse);
    });

    test('rejects duplicate requested sections is noop for Set', () {
      final request = DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        requestedSections: {
          DashboardSectionType.overview,
          DashboardSectionType.overview,
        },
      );
      expect(request.requestedSections!.length, 1);
    });

    test('rejects useLatest false without sources', () {
      final result = validator.validate(DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        useLatest: false,
      ));
      expect(result.isValid, isFalse);
    });
  });

  group('DashboardEngine determinism', () {
    test('same request produces same snapshot id', () async {
      final core = await _coreWithArtifacts();
      final request = await _fullRequest();
      final a = await core.dashboard().build(request);
      final b = await core.dashboard().build(request);
      expect(a.snapshot!.metadata.dashboardSnapshotId,
          b.snapshot!.metadata.dashboardSnapshotId);
      expect(a.snapshot!.metadata.queryFingerprint,
          b.snapshot!.metadata.queryFingerprint);
      expect(a.snapshot!.metadata.dashboardFingerprint,
          b.snapshot!.metadata.dashboardFingerprint);
    });

    test('reordered filters preserve identity', () async {
      final core = await _coreWithArtifacts();
      final mes = await _mesSnapshot(core);
      final metrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianGo(),
      );
      final score = await core.score().latest(projectId: projectId);

      final r1 = DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        mesSnapshot: mes,
        metricsSnapshot: metrics,
        engineeringScoreSnapshot: score,
        filters: const [
          DashboardFilter(key: 'a', value: '1'),
          DashboardFilter(key: 'b', value: '2'),
        ],
      );
      final r2 = DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        mesSnapshot: mes,
        metricsSnapshot: metrics,
        engineeringScoreSnapshot: score,
        filters: const [
          DashboardFilter(key: 'b', value: '2'),
          DashboardFilter(key: 'a', value: '1'),
        ],
      );
      final s1 = await core.dashboard().build(r1);
      final s2 = await core.dashboard().build(r2);
      expect(s1.snapshot!.metadata.dashboardSnapshotId,
          s2.snapshot!.metadata.dashboardSnapshotId);
    });

    test('different createdAt does not change structural id', () async {
      final core = await _coreWithArtifacts();
      final base = await _fullRequest();
      final r2 = DashboardRequest(
        projectId: base.projectId,
        createdAt: ScoreFixtures.createdAtB,
        referenceTime: base.referenceTime,
        mesSnapshot: base.mesSnapshot,
        metricsSnapshot: base.metricsSnapshot,
        engineeringScoreSnapshot: base.engineeringScoreSnapshot,
        guardianAnalysis: base.guardianAnalysis,
      );
      final s1 = await core.dashboard().build(base);
      final s2 = await core.dashboard().build(r2);
      expect(s1.snapshot!.metadata.dashboardSnapshotId,
          s2.snapshot!.metadata.dashboardSnapshotId);
    });
  });

  group('DashboardEngine composition', () {
    test('overview with MES score and guardian', () async {
      final core = await _coreWithArtifacts();
      final result = await core.dashboard().build(await _fullRequest());
      expect(result.status,
          anyOf(DashboardStatus.success, DashboardStatus.partial));
      final overview = result.snapshot!.sections
          .firstWhere((s) => s.type == DashboardSectionType.overview);
      expect(overview.widgets.any((w) => w.widgetId == 'overview.mes.overall'),
          isTrue);
      expect(
        overview.widgets.any((w) => w.widgetId == 'overview.guardian.decision'),
        isTrue,
      );
    });

    test('partial when only metrics available', () async {
      final core = await _coreWithArtifacts();
      final metrics = await ScoreFixtures.metricsComplete();
      final result = await core.dashboard().build(DashboardRequest(
            projectId: projectId,
            createdAt: createdAt,
            referenceTime: referenceTime,
            metricsSnapshot: metrics,
            useLatest: false,
            requestedSections: {
              DashboardSectionType.mes,
              DashboardSectionType.metrics
            },
          ));
      expect(result.status, DashboardStatus.partial);
    });

    test('incompatible project rejected by request validator', () async {
      const validator = DashboardRequestValidator();
      final mes = await _mesSnapshot(await _coreWithArtifacts());
      final json = await _metricsJsonOtherProject();
      final otherMetrics = MetricsSnapshot.fromJson(json);
      final result = validator.validate(DashboardRequest(
        projectId: projectId,
        createdAt: createdAt,
        referenceTime: referenceTime,
        mesSnapshot: mes,
        metricsSnapshot: otherMetrics,
      ));
      expect(result.isValid, isFalse);
    });

    test('source references registered for injected artifacts', () async {
      final core = await _coreWithArtifacts();
      final result = await core.dashboard().build(await _fullRequest());
      final refs = result.snapshot!.sourceReferences;
      expect(refs.any((r) => r.sourceType == DashboardSourceType.mes), isTrue);
      expect(
        refs.any(
            (r) => r.resolutionMode == DashboardSourceResolutionMode.injected),
        isTrue,
      );
    });
  });

  group('DashboardStore', () {
    test('publish idempotent', () async {
      final store = InMemoryDashboardStore();
      final snap = await _buildSnapshot();
      await store.save(snap);
      await store.save(snap);
      expect(await store.load(snap.metadata.dashboardSnapshotId), isNotNull);
    });

    test('conflict on divergent payload', () async {
      final store = InMemoryDashboardStore();
      final snap = await _buildSnapshot();
      await store.save(snap);
      final modified = DashboardSnapshot.fromJson(snap.toJson());
      final metaJson = modified.metadata.toJson();
      metaJson['sectionCount'] = metaJson['sectionCount'] + 1;
      final badMeta = DashboardMetadata.fromJson(metaJson);
      final bad = DashboardSnapshot(
        metadata: badMeta,
        sections: modified.sections,
        sourceReferences: modified.sourceReferences,
        layout: modified.layout,
        warnings: modified.warnings,
        errors: modified.errors,
        limitations: modified.limitations,
      );
      expect(() => store.save(bad), throwsA(isA<DashboardConflictException>()));
    });
  });

  group('DashboardRegistry', () {
    test('foundation layout registered and frozen', () {
      final registry = DashboardRegistry();
      DashboardRegistry.registerFoundation(registry);
      expect(registry.isFrozen, isTrue);
      expect(
        registry.layout('dashboard-foundation-v1').layoutId,
        'dashboard-foundation-v1',
      );
    });

    test('duplicate builder rejected', () {
      final registry = DashboardRegistry();
      registry.registerBuilder(const OverviewSectionBuilder());
      expect(
        () => registry.registerBuilder(const OverviewSectionBuilder()),
        throwsA(isA<DashboardRegistryException>()),
      );
    });
  });

  group('Platform integration', () {
    test('DashboardProvider registered and core.dashboard resolves', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.dashboard(), isNotNull);
      expect(core.dashboard().supportedSections, isNotEmpty);
    });

    test('ReportType.engineeringDashboard renders snapshot', () async {
      final core = await _coreWithArtifacts();
      final dash = await core.dashboard().build(await _fullRequest());
      final engine = ReportEngine();
      final report = await engine.generate(ReportRequest(
        reportType: ReportType.engineeringDashboard,
        projectId: projectId,
        dashboardSnapshot: dash.snapshot!.toJson(),
      ));
      expect(report.document.sections, isNotEmpty);
      expect(
        report.document.sections.any((s) => s.id.contains('dashboard')),
        isTrue,
      );
    });
  });

  group('Freshness', () {
    test('current freshness for recent sources', () async {
      final core = await _coreWithArtifacts();
      final result = await core.dashboard().build(await _fullRequest());
      expect(
        result.snapshot!.metadata.freshness,
        anyOf(DashboardFreshness.current, DashboardFreshness.recent),
      );
    });
  });

  group('Architecture constraints', () {
    test('dashboard engine source has no DateTime.now', () async {
      final file = File(
        'lib/dashboard/dashboard_engine.dart',
      ).readAsStringSync();
      expect(file.contains('DateTime.now'), isFalse);
    });

    test('dashboard engine source has no File access', () async {
      final file = File(
        'lib/dashboard/dashboard_engine.dart',
      ).readAsStringSync();
      expect(file.contains('File('), isFalse);
      expect(file.contains('Directory('), isFalse);
    });
  });
}

Future<PlatformCore> _coreWithArtifacts() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final metrics = await ScoreFixtures.metricsComplete(
    guardianAnalysis: ScoreFixtures.guardianGo(),
  );
  await core.metrics().publish(metrics);

  final scoreResult = await core.score().calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: 'foundation-reference-v1',
      ));
  if (scoreResult.snapshot != null) {
    await core.score().publish(scoreResult.snapshot!);
  }

  final mesResult = await core.mes().calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
  if (mesResult.snapshot != null) {
    await core.mes().publish(mesResult.snapshot!);
  }

  return core;
}

Future<DashboardRequest> _fullRequest() async {
  final core = await _coreWithArtifacts();
  final metrics = await ScoreFixtures.metricsComplete(
    guardianAnalysis: ScoreFixtures.guardianGo(),
  );
  return DashboardRequest(
    projectId: ScoreFixtures.projectId,
    createdAt: ScoreFixtures.createdAtA,
    referenceTime: '2026-01-02T12:00:00.000Z',
    metricsSnapshot: metrics,
    engineeringScoreSnapshot:
        await core.score().latest(projectId: ScoreFixtures.projectId),
    mesSnapshot: await _mesSnapshot(core),
    guardianAnalysis: ScoreFixtures.guardianGo(),
  );
}

Future<MESSnapshot> _mesSnapshot(PlatformCore core) async {
  return (await core.mes().latest(projectId: ScoreFixtures.projectId))!;
}

Future<DashboardSnapshot> _buildSnapshot() async {
  final core = await _coreWithArtifacts();
  final result = await core.dashboard().build(await _fullRequest());
  if (result.snapshot == null) {
    throw StateError(result.errors.map((e) => e.message).join('; '));
  }
  return result.snapshot!;
}

Future<Map<String, dynamic>> _metricsJsonOtherProject() async {
  final snapshot = await ScoreFixtures.metricsMinimal();
  final json = snapshot.toJson();
  final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
  metadata['projectId'] = 'other-project';
  json['metadata'] = metadata;
  return json;
}
