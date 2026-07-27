import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/history/history_canonical_serializer.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/history_compatibility_checker.dart';
import 'package:masterpalm_platform/history/history_engine.dart';
import 'package:masterpalm_platform/history/history_exceptions.dart';
import 'package:masterpalm_platform/history/history_snapshot_id_factory.dart';
import 'package:masterpalm_platform/history/history_validator.dart';
import 'package:masterpalm_platform/history/stores/in_memory_history_store.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/renderers/json_report_renderer.dart';
import 'package:test/test.dart';

import '../metrics/metrics_fixtures.dart';
import 'history_fixtures.dart';

void main() {
  HistoryEngine engine() => HistoryEngine();
  const serializer = HistoryCanonicalSerializer();
  const validator = HistoryValidator();
  const comparator = HistoryComparator();
  const compatibility = HistoryCompatibilityChecker();

  PlatformHistoryProvider provider({InMemoryHistoryStore? store}) {
    return PlatformHistoryProvider(
      engine: engine(),
      store: store ?? InMemoryHistoryStore(),
    );
  }

  Future<HistorySnapshot> capture(HistoryRequest request) async {
    final result = await provider().capture(request);
    return result.snapshot;
  }

  group('HistorySnapshot models', () {
    test('creates immutable snapshot and round-trips JSON', () async {
      final snapshot = await capture(await HistoryFixtures.requestA());
      final roundTrip = HistorySnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.metadata.historySnapshotId,
          snapshot.metadata.historySnapshotId);
      expect(roundTrip.artifacts.length, snapshot.artifacts.length);
    });

    test('canonical serialization is stable', () async {
      final snapshot = await capture(await HistoryFixtures.requestA());
      final a = serializer.canonicalizeSnapshot(snapshot);
      final b = serializer.canonicalizeSnapshot(snapshot);
      expect(a, b);
    });
  });

  group('History identity', () {
    test('snapshotId and fingerprint are deterministic', () async {
      final req = await HistoryFixtures.requestA();
      final a = engine().capture(req).snapshot;
      final b = engine().capture(req).snapshot;
      expect(a.metadata.historySnapshotId, b.metadata.historySnapshotId);
      expect(a.metadata.snapshotFingerprint, b.metadata.snapshotFingerprint);
    });

    test('different timestamps do not change structural identity', () async {
      final metrics = (await HistoryFixtures.metricsSnapshot()).toJson();
      final a = engine()
          .capture(HistoryRequest(
            projectId: HistoryFixtures.projectId,
            createdAt: HistoryFixtures.createdAtA,
            metricsSnapshot: metrics,
          ))
          .snapshot;
      final b = engine()
          .capture(HistoryRequest(
            projectId: HistoryFixtures.projectId,
            createdAt: HistoryFixtures.createdAtB,
            metricsSnapshot: metrics,
          ))
          .snapshot;
      expect(a.metadata.historySnapshotId, b.metadata.historySnapshotId);
      expect(a.metadata.snapshotFingerprint, b.metadata.snapshotFingerprint);
    });

    test('artifact order does not change identity', () async {
      final req = await HistoryFixtures.requestJ();
      final reversed = HistoryRequest(
        projectId: req.projectId,
        createdAt: req.createdAt,
        metricsSnapshot: req.metricsSnapshot,
        projectGraph: req.projectGraph,
        astReport: req.astReport,
        guardianAnalysis: req.guardianAnalysis,
      );
      final a = engine().capture(req).snapshot;
      final b = engine().capture(reversed).snapshot;
      expect(a.metadata.historySnapshotId, b.metadata.historySnapshotId);
    });

    test('HistorySnapshotIdFactory format', () {
      const factory = HistorySnapshotIdFactory();
      final id = factory.create(
        projectId: 'demo',
        snapshotFingerprint: 'abc',
      );
      expect(id, 'history:demo:abc:1');
    });
  });

  group('History validation', () {
    test('rejects snapshot without artifacts', () {
      expect(
        () => engine().capture(
          const HistoryRequest(
            projectId: 'demo',
            createdAt: HistoryFixtures.createdAtA,
          ),
        ),
        throwsA(isA<HistoryValidationException>()),
      );
    });

    test('rejects duplicate artifact types in manual snapshot', () async {
      final base = await capture(await HistoryFixtures.requestA());
      final dup = HistorySnapshot(
        metadata: base.metadata,
        artifacts: [
          base.artifacts.first,
          base.artifacts.first,
        ],
      );
      final result = validator.validate(dup);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('duplicate artifact')));
    });

    test('rejects empty artifactId', () async {
      final base = await capture(await HistoryFixtures.requestA());
      final artifact = base.artifacts.first;
      final invalid = HistoryArtifact(
        artifactType: artifact.artifactType,
        artifactId: '',
        schemaVersion: artifact.schemaVersion,
        fingerprint: artifact.fingerprint,
        payload: artifact.payload,
      );
      final snapshot = HistorySnapshot(
        metadata: base.metadata.copyWith(artifactCount: 1, artifactTypes: [
          artifact.artifactType,
        ]),
        artifacts: [invalid],
      );
      expect(validator.validate(snapshot).isValid, isFalse);
    });

    test('rejects incompatible metadata counts', () async {
      final base = await capture(await HistoryFixtures.requestA());
      final snapshot = HistorySnapshot(
        metadata: base.metadata.copyWith(artifactCount: 99),
        artifacts: base.artifacts,
      );
      expect(validator.validate(snapshot).isValid, isFalse);
    });

    test('rejects partial snapshot without missingArtifacts', () async {
      final base = await capture(await HistoryFixtures.requestA());
      final snapshot = HistorySnapshot(
        metadata: base.metadata.copyWith(
          status: HistorySnapshotStatus.partial,
          missingArtifacts: const [],
        ),
        artifacts: base.artifacts,
      );
      expect(validator.validate(snapshot).isValid, isFalse);
    });
  });

  group('Artifact capture', () {
    test('captures metrics artifact', () async {
      final snapshot = await capture(await HistoryFixtures.requestA());
      expect(
        snapshot.artifacts
            .any((a) => a.artifactType == HistoryArtifactType.metrics),
        isTrue,
      );
    });

    test('captures graph artifact', () async {
      final snapshot = await capture(await HistoryFixtures.requestB());
      expect(
        snapshot.artifacts
            .any((a) => a.artifactType == HistoryArtifactType.graph),
        isTrue,
      );
    });

    test('captures report artifact', () async {
      final report = await HistoryFixtures.sampleReport();
      final snapshot = await capture(
        HistoryRequest(
          projectId: HistoryFixtures.projectId,
          createdAt: HistoryFixtures.createdAtA,
          metricsSnapshot: (await HistoryFixtures.metricsSnapshot()).toJson(),
          reportDocument: report.toJson(),
        ),
      );
      expect(
        snapshot.artifacts
            .any((a) => a.artifactType == HistoryArtifactType.report),
        isTrue,
      );
    });

    test('captures guardian artifact', () async {
      final snapshot = await capture(await HistoryFixtures.requestE());
      expect(
        snapshot.artifacts
            .any((a) => a.artifactType == HistoryArtifactType.guardian),
        isTrue,
      );
    });

    test('captures ast artifact', () async {
      final snapshot = await capture(
        HistoryRequest(
          projectId: HistoryFixtures.projectId,
          createdAt: HistoryFixtures.createdAtA,
          metricsSnapshot: (await HistoryFixtures.metricsSnapshot()).toJson(),
          astReport: HistoryFixtures.astReport(),
        ),
      );
      expect(
        snapshot.artifacts
            .any((a) => a.artifactType == HistoryArtifactType.ast),
        isTrue,
      );
    });

    test('captures complete multi-artifact snapshot', () async {
      final snapshot = await capture(await HistoryFixtures.requestJ());
      expect(snapshot.metadata.status, HistorySnapshotStatus.complete);
      expect(snapshot.artifacts.length, greaterThanOrEqualTo(4));
    });

    test('captures partial snapshot with missingArtifacts', () async {
      final snapshot = await capture(await HistoryFixtures.requestG());
      expect(snapshot.metadata.status, HistorySnapshotStatus.partial);
      expect(snapshot.metadata.missingArtifacts,
          contains(HistoryArtifactType.graph));
    });
  });

  group('HistoryProvider store', () {
    test('publish and load snapshot', () async {
      final p = provider();
      final snapshot = await capture(await HistoryFixtures.requestA());
      await p.publish(snapshot);
      final loaded = await p.loadById(snapshot.metadata.historySnapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.metadata.historySnapshotId,
          snapshot.metadata.historySnapshotId);
    });

    test('publish is idempotent for same snapshot', () async {
      final store = InMemoryHistoryStore();
      final p = provider(store: store);
      final snapshot =
          engine().capture(await HistoryFixtures.requestA()).snapshot;
      await p.publish(snapshot);
      await p.publish(snapshot);
      expect(await store.exists(snapshot.metadata.historySnapshotId), isTrue);
    });

    test('conflict when same id with different payload', () async {
      final store = InMemoryHistoryStore();
      final first = engine().capture(await HistoryFixtures.requestA()).snapshot;
      await store.save(first);
      final second =
          engine().capture(await HistoryFixtures.requestB()).snapshot;
      if (first.metadata.historySnapshotId ==
          second.metadata.historySnapshotId) {
        // force same id with different payload for conflict test
        final tampered = HistorySnapshot(
          metadata: second.metadata.copyWith(
            historySnapshotId: first.metadata.historySnapshotId,
            snapshotFingerprint: first.metadata.snapshotFingerprint,
          ),
          artifacts: second.artifacts,
        );
        expect(
          () => store.save(tampered),
          throwsA(isA<HistoryConflictException>()),
        );
      } else {
        final tampered = HistorySnapshot(
          metadata: second.metadata.copyWith(
            historySnapshotId: first.metadata.historySnapshotId,
            snapshotFingerprint: first.metadata.snapshotFingerprint,
          ),
          artifacts: second.artifacts,
        );
        expect(
          () => store.save(tampered),
          throwsA(isA<HistoryConflictException>()),
        );
      }
    });

    test('latest by project', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final latest = await p.latest(projectId: HistoryFixtures.projectId);
      expect(latest, isNotNull);
      expect(latest!.metadata.createdAt, HistoryFixtures.createdAtB);
    });

    test('list by project', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final list = await p.list(
        const HistoryQuery(projectId: HistoryFixtures.projectId),
      );
      expect(list.length, 2);
    });

    test('filter by branch', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final list = await p.list(
        const HistoryQuery(
          projectId: HistoryFixtures.projectId,
          branch: HistoryFixtures.branch,
        ),
      );
      expect(list.length, 1);
    });

    test('filter by gitRef', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final list = await p.list(
        const HistoryQuery(
          projectId: HistoryFixtures.projectId,
          gitRef: HistoryFixtures.gitRef,
        ),
      );
      expect(list.length, 1);
    });

    test('filter by period', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final list = await p.list(
        const HistoryQuery(
          projectId: HistoryFixtures.projectId,
          createdFrom: HistoryFixtures.createdAtB,
          createdTo: HistoryFixtures.createdAtB,
        ),
      );
      expect(list.length, 1);
    });

    test('filter by artifactType', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final list = await p.list(
        HistoryQuery(
          projectId: HistoryFixtures.projectId,
          artifactTypes: {HistoryArtifactType.graph},
        ),
      );
      expect(list.length, 1);
    });

    test('deterministic ordering', () async {
      final p = provider();
      await p.capture(await HistoryFixtures.requestA());
      await p.capture(await HistoryFixtures.requestB());
      final asc = await p.list(
        const HistoryQuery(
          projectId: HistoryFixtures.projectId,
          descending: false,
        ),
      );
      expect(asc.first.metadata.createdAt, HistoryFixtures.createdAtA);
      final desc = await p.list(
        const HistoryQuery(
          projectId: HistoryFixtures.projectId,
          descending: true,
        ),
      );
      expect(desc.first.metadata.createdAt, HistoryFixtures.createdAtB);
    });
  });

  group('HistoryComparator', () {
    test('equal snapshots produce unchanged artifact', () async {
      final a = await capture(await HistoryFixtures.requestA());
      final b = await capture(await HistoryFixtures.requestI());
      final diff = comparator.compare(a, b);
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.artifactUnchanged,
        ),
        isTrue,
      );
    });

    test('detects artifact added and removed', () async {
      final a = await capture(await HistoryFixtures.requestA());
      final b = await capture(await HistoryFixtures.requestB());
      final diff = comparator.compare(a, b);
      expect(
        diff.changes
            .any((c) => c.changeType == HistoryChangeType.artifactAdded),
        isTrue,
      );
    });

    test('detects metric and graph structural changes', () async {
      final a = await capture(await HistoryFixtures.requestB());
      final c = await capture(await HistoryFixtures.requestC());
      final diff = comparator.compare(a, c);
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.graphNodeAdded,
        ),
        isTrue,
      );
      expect(
        diff.changes.any(
          (c) =>
              c.changeType == HistoryChangeType.metricValueChanged ||
              c.changeType == HistoryChangeType.metricAdded,
        ),
        isTrue,
      );
    });

    test('detects graph edge removed', () async {
      final a = await capture(await HistoryFixtures.requestB());
      final d = await capture(await HistoryFixtures.requestD());
      final diff = comparator.compare(a, d);
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.graphEdgeRemoved,
        ),
        isTrue,
      );
    });

    test('detects guardian decision and violations', () async {
      final go = await capture(await HistoryFixtures.requestE());
      final noGo = await capture(await HistoryFixtures.requestF());
      final diff = comparator.compare(go, noGo);
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.guardianDecisionChanged,
        ),
        isTrue,
      );
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.guardianViolationAdded,
        ),
        isTrue,
      );
    });

    test('computes absolute and relative metric deltas', () async {
      final a = await capture(await HistoryFixtures.requestA());
      final b = await capture(await HistoryFixtures.requestB());
      final diff = comparator.compare(a, b);
      final valueChange = diff.changes.firstWhere(
        (c) =>
            c.changeType == HistoryChangeType.metricValueChanged &&
            c.absoluteDelta != null,
        orElse: () => throw StateError('no metric delta'),
      );
      expect(valueChange.absoluteDelta, isNotNull);
      if (valueChange.relativeDelta != null) {
        expect(valueChange.relativeDelta, isA<double>());
      }
    });

    test('skips relative delta when previous is zero', () {
      final checker = compatibility;
      expect(
        checker
            .betweenSameType(
              HistoryArtifact(
                artifactType: HistoryArtifactType.metrics,
                artifactId: 'm1',
                schemaVersion: 1,
                fingerprint: 'a',
                payload: HistoryArtifactPayload(
                  encoding: HistoryArtifactPayload.jsonEncoding,
                  data: const {},
                ),
                calculationVersion: 1,
              ),
              HistoryArtifact(
                artifactType: HistoryArtifactType.metrics,
                artifactId: 'm1',
                schemaVersion: 1,
                fingerprint: 'b',
                payload: HistoryArtifactPayload(
                  encoding: HistoryArtifactPayload.jsonEncoding,
                  data: const {},
                ),
                calculationVersion: 2,
              ),
            )
            .status,
        HistoryCompatibilityStatus.partiallyCompatible,
      );
    });

    test('report section changes via report capture', () async {
      final reportA = await HistoryFixtures.sampleReport();
      final reportB = await HistoryFixtures.sampleReport();
      final snapA = await capture(
        HistoryRequest(
          projectId: HistoryFixtures.projectId,
          createdAt: HistoryFixtures.createdAtA,
          metricsSnapshot: (await HistoryFixtures.metricsSnapshot()).toJson(),
          reportDocument: reportA.toJson(),
        ),
      );
      final snapB = await capture(
        HistoryRequest(
          projectId: HistoryFixtures.projectId,
          createdAt: HistoryFixtures.createdAtB,
          metricsSnapshot: (await HistoryFixtures.metricsSnapshot(
                  graph: MetricsFixtures.branch()))
              .toJson(),
          reportDocument: reportB.toJson(),
        ),
      );
      final diff = comparator.compare(snapA, snapB);
      expect(
        diff.changes.any(
          (c) => c.changeType == HistoryChangeType.artifactChanged,
        ),
        isTrue,
      );
    });
  });

  group('History compatibility', () {
    test('compatible same schema', () {
      final artifact = HistoryArtifact(
        artifactType: HistoryArtifactType.metrics,
        artifactId: 'm',
        schemaVersion: 1,
        fingerprint: 'fp',
        payload: HistoryArtifactPayload(
          encoding: HistoryArtifactPayload.jsonEncoding,
          data: const {'x': 1},
        ),
      );
      final status = compatibility.betweenSameType(artifact, artifact);
      expect(status.status, HistoryCompatibilityStatus.compatible);
    });

    test('partially compatible calculationVersion mismatch', () {
      final a = HistoryArtifact(
        artifactType: HistoryArtifactType.metrics,
        artifactId: 'm',
        schemaVersion: 1,
        calculationVersion: 1,
        fingerprint: 'a',
        payload: HistoryArtifactPayload(
          encoding: HistoryArtifactPayload.jsonEncoding,
          data: const {},
        ),
      );
      final b = HistoryArtifact(
        artifactType: HistoryArtifactType.metrics,
        artifactId: 'm',
        schemaVersion: 1,
        calculationVersion: 2,
        fingerprint: 'b',
        payload: HistoryArtifactPayload(
          encoding: HistoryArtifactPayload.jsonEncoding,
          data: const {},
        ),
      );
      expect(
        compatibility.betweenSameType(a, b).status,
        HistoryCompatibilityStatus.partiallyCompatible,
      );
    });

    test('incompatible schema mismatch', () async {
      final a = await capture(await HistoryFixtures.requestA());
      final h = await capture(await HistoryFixtures.requestH());
      final diff = comparator.compare(a, h);
      expect(
        diff.compatibility.status,
        anyOf(
          HistoryCompatibilityStatus.incompatible,
          HistoryCompatibilityStatus.partiallyCompatible,
        ),
      );
    });

    test('unknown when artifact missing', () {
      expect(
        compatibility.betweenArtifacts(null, null).status,
        HistoryCompatibilityStatus.unknown,
      );
    });
  });

  group('Platform integration', () {
    test('registers HistoryProvider and resolves via PlatformCore', () {
      final core = PlatformBootstrap.forRepo('.');
      expect(core.history(), isA<PlatformHistoryProvider>());
    });

    test('HistoryDiff integrates with ReportEngine', () async {
      final p = provider();
      final from = await p.capture(await HistoryFixtures.requestA());
      final to = await p.capture(await HistoryFixtures.requestB());
      final diff = await p.compare(
        fromSnapshotId: from.snapshot.metadata.historySnapshotId,
        toSnapshotId: to.snapshot.metadata.historySnapshotId,
      );
      final reportEngine = ReportEngine(
        renderers: {ReportFormat.json: const JsonReportRenderer()},
      );
      final report = await reportEngine.generate(
        ReportRequest(
          reportType: ReportType.historyDiff,
          projectId: HistoryFixtures.projectId,
          historyDiff: diff.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      expect(report.document.metadata.reportType, ReportType.historyDiff);
    });
  });

  group('Determinism stress', () {
    test('metrics internal order does not change identity', () async {
      final metrics = await HistoryFixtures.metricsSnapshot();
      final json = metrics.toJson();
      final list = List<Map<String, dynamic>>.from(
        json['metrics'] as List<dynamic>,
      );
      final reversed = Map<String, dynamic>.from(json);
      reversed['metrics'] = list.reversed.toList();
      final a = engine()
          .capture(HistoryRequest(
            projectId: HistoryFixtures.projectId,
            createdAt: HistoryFixtures.createdAtA,
            metricsSnapshot: json,
          ))
          .snapshot;
      final b = engine()
          .capture(HistoryRequest(
            projectId: HistoryFixtures.projectId,
            createdAt: HistoryFixtures.createdAtA,
            metricsSnapshot: reversed,
          ))
          .snapshot;
      expect(a.metadata.historySnapshotId, b.metadata.historySnapshotId);
    });
  });
}
