import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/renderers/json_report_renderer.dart';
import 'package:masterpalm_platform/metrics/metrics_engine.dart';

import '../metrics/metrics_fixtures.dart';

/// Deterministic fixtures for History Engine tests (A–J).
class HistoryFixtures {
  static const projectId = 'demo-project';
  static const createdAtA = '2026-01-01T10:00:00.000Z';
  static const createdAtB = '2026-01-02T10:00:00.000Z';
  static const branch = 'feature/history';
  static const gitRef = 'abc123';

  static Future<MetricsSnapshot> metricsSnapshot({
    ProjectGraph? graph,
  }) async {
    final result = await MetricsEngine().calculate(
      MetricsRequest(
        projectId: projectId,
        projectGraph: (graph ?? MetricsFixtures.linear()).toJson(),
      ),
    );
    return result.snapshot;
  }

  static Map<String, dynamic> astReport() {
    return jsonDecode(
      File('test/fixtures/minimal_ast_report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  static Map<String, dynamic> guardianGo() {
    return jsonDecode(
      File('test/fixtures/guardian_no_violations.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  static Map<String, dynamic> guardianNoGo() {
    return jsonDecode(
      File('test/fixtures/minimal_guardian_analysis.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  static Future<HistoryRequest> requestA() async {
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtA,
      metricsSnapshot: (await metricsSnapshot()).toJson(),
      branch: branch,
      gitRef: gitRef,
    );
  }

  static Future<HistoryRequest> requestB() async {
    final graph = MetricsFixtures.branch();
    final snapshot = await metricsSnapshot(graph: graph);
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: snapshot.toJson(),
      projectGraph: graph.toJson(),
    );
  }

  static Future<HistoryRequest> requestC() async {
    final graph = MetricsFixtures.linear();
    final extraNode = GraphNode(
      id: 'd',
      type: GraphNodeType.file,
      label: 'd',
    );
    final extended = ProjectGraph(
      nodes: [...graph.nodes, extraNode],
      edges: graph.edges,
      metadata: graph.metadata,
    );
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: (await metricsSnapshot(graph: extended)).toJson(),
      projectGraph: extended.toJson(),
    );
  }

  static Future<HistoryRequest> requestD() async {
    final graph = MetricsFixtures.linear();
    final trimmed = ProjectGraph(
      nodes: graph.nodes,
      edges: graph.edges.take(1).toList(),
      metadata: graph.metadata,
    );
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: (await metricsSnapshot(graph: trimmed)).toJson(),
      projectGraph: trimmed.toJson(),
    );
  }

  static Future<HistoryRequest> requestE() async {
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtA,
      metricsSnapshot: (await metricsSnapshot()).toJson(),
      guardianAnalysis: guardianGo(),
    );
  }

  static Future<HistoryRequest> requestF() async {
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: (await metricsSnapshot()).toJson(),
      guardianAnalysis: guardianNoGo(),
    );
  }

  static Future<HistoryRequest> requestG() async {
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtA,
      metricsSnapshot: (await metricsSnapshot()).toJson(),
      artifactSelection: {
        HistoryArtifactType.metrics,
        HistoryArtifactType.graph,
      },
    );
  }

  static Future<HistoryRequest> requestH() async {
    final metrics = await metricsSnapshot();
    final json = metrics.toJson();
    final metadata = Map<String, dynamic>.from(
      json['metadata'] as Map<String, dynamic>,
    );
    metadata['metricsSchemaVersion'] = 999;
    json['metadata'] = metadata;
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: json,
    );
  }

  static Future<HistoryRequest> requestI() async {
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtB,
      metricsSnapshot: (await metricsSnapshot()).toJson(),
    );
  }

  static Future<HistoryRequest> requestJ() async {
    final metrics = await metricsSnapshot();
    final graph = MetricsFixtures.linear();
    return HistoryRequest(
      projectId: projectId,
      createdAt: createdAtA,
      metricsSnapshot: metrics.toJson(),
      projectGraph: graph.toJson(),
      astReport: astReport(),
      guardianAnalysis: guardianGo(),
    );
  }

  static Future<ReportDocument> sampleReport() async {
    final engine = ReportEngine(
      renderers: {ReportFormat.json: const JsonReportRenderer()},
    );
    final metrics = await metricsSnapshot();
    final result = await engine.generate(
      ReportRequest(
        reportType: ReportType.metricsSummary,
        projectId: projectId,
        metricsSnapshot: metrics.toJson(),
      ),
    );
    return result.document;
  }
}
