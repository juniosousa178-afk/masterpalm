import '../models/graph/graph_edge.dart';
import '../models/graph/graph_node.dart';
import '../models/graph/project_graph.dart';

/// Precomputed deterministic graph views for metric calculators.
class MetricsGraphContext {
  MetricsGraphContext(ProjectGraph graph)
      : graph = graph,
        sortedNodes = (List<GraphNode>.from(graph.nodes)
          ..sort((a, b) => a.id.compareTo(b.id))),
        sortedEdges = (List<GraphEdge>.from(graph.edges)
          ..sort((a, b) => a.dedupeKey.compareTo(b.dedupeKey))) {
    for (final node in sortedNodes) {
      fanIn[node.id] = 0;
      fanOut[node.id] = 0;
      outgoing[node.id] = <String>[];
      incoming[node.id] = <String>[];
    }
    for (final edge in sortedEdges) {
      fanOut[edge.sourceId] = (fanOut[edge.sourceId] ?? 0) + 1;
      fanIn[edge.targetId] = (fanIn[edge.targetId] ?? 0) + 1;
      outgoing.putIfAbsent(edge.sourceId, () => <String>[]).add(edge.targetId);
      incoming.putIfAbsent(edge.targetId, () => <String>[]).add(edge.sourceId);
    }
    for (final entry in outgoing.entries) {
      entry.value.sort();
    }
    for (final entry in incoming.entries) {
      entry.value.sort();
    }
  }

  final ProjectGraph graph;
  final List<GraphNode> sortedNodes;
  final List<GraphEdge> sortedEdges;
  final Map<String, int> fanIn = {};
  final Map<String, int> fanOut = {};
  final Map<String, List<String>> outgoing = {};
  final Map<String, List<String>> incoming = {};

  List<String> get sortedNodeIds =>
      sortedNodes.map((n) => n.id).toList(growable: false);

  Map<String, List<String>> get directedAdjacency => outgoing;
}
