import 'package:masterpalm_platform/masterpalm_platform.dart';

/// Deterministic graph fixtures for metrics tests.
class MetricsFixtures {
  static const metadata = GraphMetadata(
    graphSchemaVersion: 1,
    source: 'metrics-test',
  );

  static ProjectGraph empty() => const ProjectGraph(
        nodes: [],
        edges: [],
        metadata: metadata,
      );

  static ProjectGraph linear() {
    return ProjectGraph(
      nodes: [
        node('a', GraphNodeType.file),
        node('b', GraphNodeType.file),
        node('c', GraphNodeType.file),
      ],
      edges: [
        edge('a', 'b', GraphEdgeType.dependsOn),
        edge('b', 'c', GraphEdgeType.dependsOn),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph branch() {
    return ProjectGraph(
      nodes: [
        node('root', GraphNodeType.service),
        node('left', GraphNodeType.method),
        node('right', GraphNodeType.method),
      ],
      edges: [
        edge('root', 'left', GraphEdgeType.declares),
        edge('root', 'right', GraphEdgeType.declares),
        edge('left', 'right', GraphEdgeType.calls),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph cycle() {
    return ProjectGraph(
      nodes: [
        node('a', GraphNodeType.file),
        node('b', GraphNodeType.file),
        node('c', GraphNodeType.file),
      ],
      edges: [
        edge('a', 'b', GraphEdgeType.dependsOn),
        edge('b', 'c', GraphEdgeType.dependsOn),
        edge('c', 'a', GraphEdgeType.dependsOn),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph twoComponents() {
    return ProjectGraph(
      nodes: [
        node('a1', GraphNodeType.file),
        node('a2', GraphNodeType.file),
        node('b1', GraphNodeType.file),
      ],
      edges: [
        edge('a1', 'a2', GraphEdgeType.dependsOn),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph isolatedNodes() {
    return ProjectGraph(
      nodes: [
        node('solo1', GraphNodeType.file),
        node('solo2', GraphNodeType.widget),
        node('linked', GraphNodeType.service),
        node('linked2', GraphNodeType.service),
      ],
      edges: [
        edge('linked', 'linked2', GraphEdgeType.dependsOn),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph calls() {
    return ProjectGraph(
      nodes: [
        node('main', GraphNodeType.method),
        node('helper', GraphNodeType.method),
        node('orphan', GraphNodeType.method),
      ],
      edges: [
        edge('main', 'helper', GraphEdgeType.calls),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph firestore() {
    return ProjectGraph(
      nodes: [
        node('svc', GraphNodeType.service),
        node('col', GraphNodeType.firestoreCollection, label: 'vendas'),
      ],
      edges: [
        edge('svc', 'col', GraphEdgeType.writesTo),
        edge('svc', 'col', GraphEdgeType.readsFrom),
      ],
      metadata: metadata,
    );
  }

  static ProjectGraph hive() {
    return ProjectGraph(
      nodes: [
        node('svc', GraphNodeType.service),
        node('box', GraphNodeType.hiveBox, label: 'cache'),
      ],
      edges: [
        edge('svc', 'box', GraphEdgeType.accesses),
      ],
      metadata: metadata,
    );
  }

  static Map<String, dynamic> guardianWithViolations() => {
        'decision': 'noGo',
        'violations': [
          {'code': 'G001', 'severity': 'blocking'},
          {'code': 'G002', 'severity': 'red'},
        ],
        'tests': {
          'required': ['t1', 't2']
        },
        'risk': {'overall': 'red'},
      };

  static Map<String, dynamic> astReport() => {
        'meta': {'files_analyzed': 5},
        'metrics': {'total_classes': 10, 'total_methods': 20},
      };

  static GraphNode node(
    String id,
    GraphNodeType type, {
    String? label,
  }) {
    return GraphNode(id: id, type: type, label: label ?? id);
  }

  static GraphEdge edge(
    String source,
    String target,
    GraphEdgeType type,
  ) {
    return GraphEdge(sourceId: source, targetId: target, type: type);
  }

  static ProjectGraph reorder(ProjectGraph graph) {
    final nodes = graph.nodes.reversed.toList();
    final edges = graph.edges.reversed.toList();
    return ProjectGraph(
      nodes: nodes,
      edges: edges,
      metadata: graph.metadata,
    );
  }
}
