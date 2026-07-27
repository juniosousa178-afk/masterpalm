import '../../interfaces/ast_provider.dart';
import '../../interfaces/graph_provider.dart';
import '../../models/graph/project_graph.dart';
import '../../models/graph/graph_edge_type.dart';
import '../../models/graph/graph_node_type.dart';
import '../report_exceptions.dart';
import '../report_input.dart';

/// Converts AST provider data into [AstReportInputData].
class AstReportSource {
  const AstReportSource();

  AstReportInputData fromMap(Map<String, dynamic> report) {
    if (report.isEmpty) {
      throw ReportSourceException(
        'AST report is empty',
        sourceKind: 'ast',
      );
    }
    final metrics = report['metrics'] as Map<String, dynamic>? ?? {};
    final meta = report['meta'] as Map<String, dynamic>? ?? {};
    return AstReportInputData(
      filesAnalyzed: meta['files_analyzed'] as int? ?? 0,
      totalClasses: metrics['total_classes'] as int? ?? 0,
      totalMethods: metrics['total_methods'] as int? ?? 0,
      firestoreWrites: metrics['firestore_writes'] as int? ?? 0,
      firestoreReads: metrics['firestore_reads'] as int? ?? 0,
      widgetClasses: metrics['widget_classes'] as int? ?? 0,
      serviceFiles: metrics['service_files'] as int? ?? 0,
    );
  }

  AstReportInputData fromProvider(AstProvider provider) {
    return fromMap(provider.loadReport());
  }
}

/// Converts Guardian analysis payload into [GuardianReportInputData].
class GuardianReportSource {
  const GuardianReportSource();

  GuardianReportInputData fromMap(Map<String, dynamic> guardian) {
    final impact = guardian['impact'] as Map<String, dynamic>? ?? {};
    final risk = guardian['risk'] as Map<String, dynamic>? ?? {};
    final tests = guardian['tests'] as Map<String, dynamic>? ?? {};
    final files = guardian['files'] as Map<String, dynamic>? ?? {};

    return GuardianReportInputData(
      summary: guardian['summary'] as String? ?? '',
      decision: guardian['decision'] as String? ?? 'noGo',
      simulationOnly: guardian['simulation_only'] as bool? ?? true,
      domains: _stringList(impact['domains']),
      riskOverall: risk['overall'] as String? ?? 'green',
      violations: _mapList(guardian['violations']),
      requiredTests: _stringList(tests['required']),
      missingTests: _stringList(tests['missing']),
      foundTests: _stringList(tests['found']),
      filesAdded: _stringList(files['added']),
      filesModified: _stringList(files['modified']),
      filesRemoved: _stringList(files['removed']),
      riskItems: _mapList(risk['items']),
      recommendations: _stringList(guardian['recommendations']),
      services: _stringList(impact['services']),
      screens: _stringList(impact['screens']),
      firestoreCollections: _stringList(impact['firestore_collections']),
      hiveBoxes: _stringList(impact['hive_boxes']),
      requiredDocumentation: _stringList(guardian['required_documentation']),
      methodsChanged: _stringList(guardian['methods_changed']),
      classesChanged: _stringList(guardian['classes_changed']),
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return [];
    return value.map((e) => e.toString()).toList()..sort();
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
}

/// Converts graph provider data into [GraphReportInputData].
class GraphReportSource {
  const GraphReportSource();

  GraphReportInputData fromProjectGraph(ProjectGraph graph) {
    final nodeTypes = <String, int>{};
    for (final node in graph.nodes) {
      final key = node.type.wireName;
      nodeTypes[key] = (nodeTypes[key] ?? 0) + 1;
    }
    final edgeTypes = <String, int>{};
    for (final edge in graph.edges) {
      final key = edge.type.wireName;
      edgeTypes[key] = (edgeTypes[key] ?? 0) + 1;
    }

    final degree = <String, int>{};
    for (final edge in graph.edges) {
      degree[edge.sourceId] = (degree[edge.sourceId] ?? 0) + 1;
      degree[edge.targetId] = (degree[edge.targetId] ?? 0) + 1;
    }
    final top = degree.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return GraphReportInputData(
      nodeCount: graph.nodes.length,
      edgeCount: graph.edges.length,
      nodeTypes: nodeTypes,
      edgeTypes: edgeTypes,
      topConnectedNodes: top.take(10).map((e) => e.key).toList(),
    );
  }

  Future<GraphReportInputData?> fromProvider(GraphProvider provider) async {
    final graph = await provider.load();
    if (graph == null) return null;
    return fromProjectGraph(graph);
  }
}
