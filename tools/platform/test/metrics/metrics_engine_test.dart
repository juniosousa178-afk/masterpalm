import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'package:masterpalm_platform/metrics/calculators/graph_metrics_calculator.dart';
import 'package:masterpalm_platform/metrics/metrics_canonical_serializer.dart';
import 'package:masterpalm_platform/metrics/metrics_definitions.dart';
import 'package:masterpalm_platform/metrics/metrics_engine.dart';
import 'package:masterpalm_platform/metrics/metrics_exceptions.dart';
import 'package:masterpalm_platform/metrics/metrics_math.dart';
import 'package:masterpalm_platform/metrics/metrics_registry.dart';
import 'package:masterpalm_platform/metrics/metrics_snapshot_id_factory.dart';
import 'package:masterpalm_platform/metrics/metrics_validator.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/renderers/json_report_renderer.dart';
import 'package:masterpalm_platform/report/renderers/markdown_report_renderer.dart';
import 'package:masterpalm_platform/report/renderers/html_report_renderer.dart';

import 'metrics_fixtures.dart';

void main() {
  MetricsEngine engine() => MetricsEngine();

  MetricRecord? findMetric(MetricsSnapshot snapshot, String id) {
    for (final metric in snapshot.metrics) {
      if (metric.definition.id == id) return metric;
    }
    return null;
  }

  int intMetric(MetricsSnapshot snapshot, String id) {
    final record = findMetric(snapshot, id)!;
    return (record.value as IntegerMetricValue).value;
  }

  double decimalMetric(MetricsSnapshot snapshot, String id) {
    final record = findMetric(snapshot, id)!;
    return (record.value as DecimalMetricValue).value;
  }

  Map<String, double> distMetric(MetricsSnapshot snapshot, String id) {
    final record = findMetric(snapshot, id)!;
    return (record.value as DistributionMetricValue).distribution.entries;
  }

  group('MetricsSnapshot', () {
    test('is immutable and round-trips JSON', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      final json = jsonDecode(jsonEncode(result.snapshot.toJson()));
      final roundTrip = MetricsSnapshot.fromJson(json as Map<String, dynamic>);
      expect(
          roundTrip.metadata.snapshotId, result.snapshot.metadata.snapshotId);
    });
  });

  group('MetricsSnapshotIdFactory', () {
    test('produces deterministic snapshotId', () {
      const factory = MetricsSnapshotIdFactory();
      final graph = MetricsFixtures.linear();
      final fp = factory.graphFingerprint(graph);
      final id = factory.create(projectId: 'demo', sourceGraphFingerprint: fp);
      expect(id, startsWith('metrics:demo:'));
      expect(factory.create(projectId: 'demo', sourceGraphFingerprint: fp), id);
    });
  });

  group('MetricsRegistry', () {
    test('registers metrics and rejects duplicate ids', () {
      final registry = MetricsRegistry();
      expect(registry.supportedMetricIds, contains('graph.node.count'));
      expect(
        () => MetricsRegistry(
          calculators: [
            const GraphMetricsCalculator(),
            const GraphMetricsCalculator(),
          ],
        ),
        throwsA(isA<MetricsException>()),
      );
    });
  });

  group('Structural metrics', () {
    test('empty graph density is zero', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.empty().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.node.count'), 0);
      expect(decimalMetric(result.snapshot, 'graph.density'), 0);
    });

    test('single node graph density is zero', () async {
      final graph = ProjectGraph(
        nodes: [MetricsFixtures.node('only', GraphNodeType.file)],
        edges: const [],
        metadata: MetricsFixtures.metadata,
      );
      final result = await engine().calculate(
        MetricsRequest(projectId: 'demo', projectGraph: graph.toJson()),
      );
      expect(decimalMetric(result.snapshot, 'graph.density'), 0);
    });

    test('linear graph counts and density', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.node.count'), 3);
      expect(intMetric(result.snapshot, 'graph.edge.count'), 2);
      expect(decimalMetric(result.snapshot, 'graph.density'),
          closeTo(1 / 3, 0.001));
    });

    test('node and edge distributions', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.branch().toJson(),
        ),
      );
      final nodeDist = distMetric(result.snapshot, 'graph.node.count.by_type');
      expect(nodeDist['service'], 1);
      expect(nodeDist['method'], 2);
    });

    test('fan-in and fan-out metrics', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.branch().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.degree.fan_in.max'),
          greaterThan(0));
      expect(intMetric(result.snapshot, 'graph.degree.fan_out.max'),
          greaterThan(0));
      expect(distMetric(result.snapshot, 'graph.degree.fan_in')['root'], 0);
    });

    test('isolated nodes and by type', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.isolatedNodes().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.component.isolated_count'), 2);
      final byType =
          distMetric(result.snapshot, 'graph.component.isolated.by_type');
      expect(byType['file'], 1);
      expect(byType['widget'], 1);
    });

    test('weak components', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.twoComponents().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.component.weak.count'), 2);
      expect(
          intMetric(result.snapshot, 'graph.component.weak.largest_size'), 2);
    });

    test('cycle detection', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.cycle().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.cycle.count'), 1);
      expect(intMetric(result.snapshot, 'graph.cycle.node_count'), 3);
      expect(
          intMetric(result.snapshot, 'graph.cycle.largest_component_size'), 3);
    });

    test('acyclic graph has zero cycles', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'graph.cycle.count'), 0);
    });

    test('bounded depth respects limit', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          depthLimit: 1,
        ),
      );
      expect(intMetric(result.snapshot, 'graph.depth.bounded_max'), 1);
    });
  });

  group('Storage and callable metrics', () {
    test('firestore metrics', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.firestore().toJson(),
        ),
      );
      expect(
          intMetric(result.snapshot, 'storage.firestore.collection_count'), 1);
      expect(
          intMetric(result.snapshot, 'storage.firestore.write_edge_count'), 1);
      expect(
          intMetric(result.snapshot, 'storage.firestore.read_edge_count'), 1);
    });

    test('hive metrics when present', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.hive().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'storage.hive.box_count'), 1);
      expect(intMetric(result.snapshot, 'storage.hive.access_edge_count'), 1);
    });

    test('hive zero when no hive nodes', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'storage.hive.box_count'), 0);
    });

    test('callable metrics and uncalled count', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.calls().toJson(),
        ),
      );
      expect(intMetric(result.snapshot, 'callable.method.count'), 3);
      expect(intMetric(result.snapshot, 'callable.call_edge_count'), 1);
      expect(intMetric(result.snapshot, 'callable.uncalled_count'), 2);
    });
  });

  group('Imported metrics', () {
    test('guardian metrics imported', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          guardianAnalysis: MetricsFixtures.guardianWithViolations(),
        ),
      );
      expect(intMetric(result.snapshot, 'guardian.violation.count'), 2);
      final decision = findMetric(result.snapshot, 'guardian.decision')!;
      expect((decision.value as TextMetricValue).value, 'noGo');
    });

    test('guardian unavailable when missing', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          metricIds: {'guardian.violation.count'},
        ),
      );
      final record = findMetric(result.snapshot, 'guardian.violation.count')!;
      expect(record.availability, MetricAvailability.unavailable);
    });

    test('ast metrics imported', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          astReport: MetricsFixtures.astReport(),
        ),
      );
      expect(intMetric(result.snapshot, 'ast.file.count'), 5);
      expect(intMetric(result.snapshot, 'ast.class.count'), 10);
    });
  });

  group('Request selection and errors', () {
    test('unknown metric id throws', () async {
      expect(
        () => engine().calculate(
          MetricsRequest(
            projectId: 'demo',
            projectGraph: MetricsFixtures.linear().toJson(),
            metricIds: {'unknown.metric'},
          ),
        ),
        throwsA(isA<MetricsUnknownMetricException>()),
      );
    });

    test('selection by metricId', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          metricIds: {'graph.node.count', 'graph.edge.count'},
        ),
      );
      expect(result.snapshot.metrics.length, 2);
    });

    test('selection by category', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
          categories: {MetricCategory.cycle},
        ),
      );
      expect(
        result.snapshot.metrics.every(
          (m) => m.definition.category == MetricCategory.cycle,
        ),
        isTrue,
      );
    });

    test('invalid graph fails structurally', () async {
      final bad = ProjectGraph(
        nodes: [MetricsFixtures.node('a', GraphNodeType.file)],
        edges: [
          GraphEdge(
            sourceId: 'a',
            targetId: 'missing',
            type: GraphEdgeType.dependsOn,
          ),
        ],
        metadata: MetricsFixtures.metadata,
      );
      expect(
        () => engine().calculate(
          MetricsRequest(projectId: 'demo', projectGraph: bad.toJson()),
        ),
        throwsA(isA<MetricsGraphException>()),
      );
    });
  });

  group('Decimal policy', () {
    test('normalizes decimals and rejects NaN', () {
      expect(MetricsMath.normalizeDecimal(-0.0), 0.0);
      expect(MetricsMath.normalizeDecimal(0.3333333333),
          closeTo(0.333333, 0.0001));
      expect(
          () => MetricsMath.normalizeDecimal(double.nan), throwsArgumentError);
      expect(() => MetricsMath.normalizeDecimal(double.infinity),
          throwsArgumentError);
    });
  });

  group('Determinism', () {
    test('same input same snapshotId and comparable JSON', () async {
      final request = MetricsRequest(
        projectId: 'demo',
        projectGraph: MetricsFixtures.cycle().toJson(),
      );
      final a = await engine().calculate(request);
      final b = await engine().calculate(request);
      expect(a.snapshot.metadata.snapshotId, b.snapshot.metadata.snapshotId);
      expect(
        a.snapshot.toComparableJson(),
        b.snapshot.toComparableJson(),
      );
    });

    test('reordered graph yields equivalent snapshot', () async {
      final graph = MetricsFixtures.branch();
      final reordered = MetricsFixtures.reorder(graph);
      final a = await engine().calculate(
        MetricsRequest(projectId: 'demo', projectGraph: graph.toJson()),
      );
      final b = await engine().calculate(
        MetricsRequest(projectId: 'demo', projectGraph: reordered.toJson()),
      );
      expect(a.snapshot.metadata.snapshotId, b.snapshot.metadata.snapshotId);
    });

    test('canonical serialization is stable', () async {
      const serializer = MetricsCanonicalSerializer();
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      final c1 = serializer.canonicalizeSnapshot(result.snapshot);
      final c2 = serializer.canonicalizeSnapshot(result.snapshot);
      expect(c1, c2);
    });
  });

  group('MetricsValidator', () {
    test('validates valid snapshot', () async {
      final result = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      final validation = const MetricsValidator().validate(result.snapshot);
      expect(validation.isValid, isTrue);
    });
  });

  group('Platform integration', () {
    test('MetricsProvider registers and resolves', () {
      final registry = ProviderRegistry();
      final core = PlatformBootstrap.forRepo('.', registry: registry);
      expect(core.metrics(), isA<PlatformMetricsProvider>());
    });

    test('publish and load snapshot', () async {
      final registry = ProviderRegistry();
      final core = PlatformBootstrap.forRepo('.', registry: registry);
      final provider = core.metrics();
      final result = await provider.calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      expect(await provider.load(), isNotNull);
      await provider.invalidate();
      expect(await provider.load(), isNull);
      expect(result.status, MetricsResultStatus.success);
    });

    test('GraphProvider to MetricsEngine integration', () async {
      final graphProvider = InMemoryGraphProvider();
      await graphProvider.publish(MetricsFixtures.hive());
      final metricsEngine = MetricsEngine(graphProvider: graphProvider);
      final result = await metricsEngine.calculate(
        const MetricsRequest(projectId: 'demo'),
      );
      expect(intMetric(result.snapshot, 'storage.hive.box_count'), 1);
    });
  });

  group('Report Engine integration', () {
    test('metricsSummary report from injected snapshot', () async {
      final metrics = await engine().calculate(
        MetricsRequest(
          projectId: 'demo',
          projectGraph: MetricsFixtures.linear().toJson(),
        ),
      );
      final reportEngine = ReportEngine(
        renderers: {
          ReportFormat.markdown: const MarkdownReportRenderer(),
          ReportFormat.json: const JsonReportRenderer(),
          ReportFormat.html: const HtmlReportRenderer(),
        },
      );
      final report = await reportEngine.generate(
        ReportRequest(
          reportType: ReportType.metricsSummary,
          projectId: 'demo',
          metricsSnapshot: metrics.snapshot.toJson(),
        ),
      );
      expect(
        report.document.sections.any((s) => s.id == 'metrics-summary'),
        isTrue,
      );
    });
  });
}
