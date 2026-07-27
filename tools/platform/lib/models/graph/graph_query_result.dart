import 'graph_edge.dart';

/// Typed result for graph queries.
class GraphQueryResult {
  const GraphQueryResult({
    required this.nodeIds,
    required this.edges,
    this.path = const [],
    this.reachedMaxDepth = false,
  });

  final List<String> nodeIds;
  final List<GraphEdge> edges;
  final List<String> path;
  final bool reachedMaxDepth;
}
