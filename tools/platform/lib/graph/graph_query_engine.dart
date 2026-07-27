import '../models/graph/graph_edge.dart';
import '../models/graph/graph_edge_type.dart';
import '../models/graph/graph_node.dart';
import '../models/graph/graph_node_type.dart';
import '../models/graph/graph_query.dart';
import '../models/graph/graph_query_result.dart';
import '../models/graph/project_graph.dart';

/// Executes structural queries over an in-memory [ProjectGraph].
class GraphQueryEngine {
  const GraphQueryEngine();

  GraphNode? nodeById(ProjectGraph graph, String id) => graph.nodeIndex[id];

  List<GraphNode> nodesByType(ProjectGraph graph, GraphNodeType type) {
    return graph.nodes.where((n) => n.type == type).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  List<GraphEdge> outgoingEdges(
    ProjectGraph graph,
    String nodeId, {
    GraphEdgeType? type,
  }) {
    return graph.edges
        .where((e) => e.sourceId == nodeId && (type == null || e.type == type))
        .toList()
      ..sort((a, b) => a.dedupeKey.compareTo(b.dedupeKey));
  }

  List<GraphEdge> incomingEdges(
    ProjectGraph graph,
    String nodeId, {
    GraphEdgeType? type,
  }) {
    return graph.edges
        .where((e) => e.targetId == nodeId && (type == null || e.type == type))
        .toList()
      ..sort((a, b) => a.dedupeKey.compareTo(b.dedupeKey));
  }

  List<String> directDependencies(ProjectGraph graph, String nodeId) {
    return outgoingEdges(graph, nodeId, type: GraphEdgeType.dependsOn)
        .map((e) => e.targetId)
        .toList();
  }

  List<String> directDependents(ProjectGraph graph, String nodeId) {
    return incomingEdges(graph, nodeId, type: GraphEdgeType.dependsOn)
        .map((e) => e.sourceId)
        .toList();
  }

  List<String> methodCalls(ProjectGraph graph, String methodId) {
    return outgoingEdges(graph, methodId, type: GraphEdgeType.calls)
        .map((e) => e.targetId)
        .toList();
  }

  List<String> methodCallers(ProjectGraph graph, String methodId) {
    return incomingEdges(graph, methodId, type: GraphEdgeType.calls)
        .map((e) => e.sourceId)
        .toList();
  }

  bool hasPath(
    ProjectGraph graph,
    String fromId,
    String toId, {
    int maxDepth = 20,
  }) {
    return findPath(graph, fromId, toId, maxDepth: maxDepth).isNotEmpty;
  }

  List<String> findPath(
    ProjectGraph graph,
    String fromId,
    String toId, {
    int maxDepth = 20,
  }) {
    if (fromId == toId) return [fromId];
    final visited = <String>{fromId};
    final queue = <List<String>>[
      [fromId],
    ];

    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      if (path.length > maxDepth) continue;
      final current = path.last;
      for (final edge in outgoingEdges(graph, current)) {
        final next = edge.targetId;
        if (visited.contains(next)) continue;
        final nextPath = [...path, next];
        if (next == toId) return nextPath;
        visited.add(next);
        queue.add(nextPath);
      }
    }
    return const [];
  }

  GraphQueryResult neighbors(
    ProjectGraph graph,
    String nodeId, {
    int maxDepth = 1,
  }) {
    final collectedNodes = <String>{nodeId};
    final collectedEdges = <GraphEdge>[];
    final frontier = <String>[nodeId];
    var depth = 0;
    var reachedMax = false;

    if (maxDepth < 0) {
      return const GraphQueryResult(nodeIds: [], edges: []);
    }

    while (frontier.isNotEmpty && depth < maxDepth) {
      final nextFrontier = <String>[];
      for (final current in frontier) {
        for (final edge in outgoingEdges(graph, current)) {
          collectedEdges.add(edge);
          if (collectedNodes.add(edge.targetId)) {
            nextFrontier.add(edge.targetId);
          }
        }
        for (final edge in incomingEdges(graph, current)) {
          collectedEdges.add(edge);
          if (collectedNodes.add(edge.sourceId)) {
            nextFrontier.add(edge.sourceId);
          }
        }
      }
      frontier
        ..clear()
        ..addAll(nextFrontier);
      depth++;
      if (depth >= maxDepth && frontier.isNotEmpty) {
        reachedMax = true;
      }
    }

    final nodeIds = collectedNodes.toList()..sort();
    final edges = collectedEdges.toSet().toList()
      ..sort((a, b) => a.dedupeKey.compareTo(b.dedupeKey));

    return GraphQueryResult(
      nodeIds: nodeIds,
      edges: edges,
      reachedMaxDepth: reachedMax,
    );
  }

  GraphQueryResult execute(ProjectGraph graph, GraphQuery query) {
    if (query.nodeId != null && query.nodeType != null) {
      final node = nodeById(graph, query.nodeId!);
      if (node == null || node.type != query.nodeType) {
        return const GraphQueryResult(nodeIds: [], edges: []);
      }
    }

    if (query.nodeId != null) {
      return neighbors(graph, query.nodeId!, maxDepth: query.maxDepth);
    }

    if (query.nodeType != null) {
      final nodes = nodesByType(graph, query.nodeType!);
      return GraphQueryResult(
        nodeIds: nodes.map((n) => n.id).toList(),
        edges: const [],
      );
    }

    return const GraphQueryResult(nodeIds: [], edges: []);
  }
}
