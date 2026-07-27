import '../../models/graph/project_graph.dart';

/// Maximum bounded depth over directed outgoing edges.
({int maxDepth, bool limitReached}) boundedGraphDepthMax(
  ProjectGraph graph,
  int depthLimit,
) {
  if (depthLimit < 0) {
    return (maxDepth: 0, limitReached: false);
  }

  final adjacency = <String, List<String>>{};
  for (final node in graph.nodes) {
    adjacency[node.id] = <String>[];
  }
  for (final edge in graph.edges) {
    adjacency.putIfAbsent(edge.sourceId, () => <String>[]).add(edge.targetId);
  }
  for (final entry in adjacency.entries) {
    entry.value.sort();
  }

  var globalMax = 0;
  var limitReached = false;
  final sortedIds = graph.nodes.map((n) => n.id).toList()..sort();

  for (final start in sortedIds) {
    final queue = <(String node, int depth)>[(start, 0)];
    final visitedDepth = <String, int>{start: 0};

    while (queue.isNotEmpty) {
      final (node, depth) = queue.removeAt(0);
      if (depth > globalMax) globalMax = depth;
      if (depth >= depthLimit) {
        if ((adjacency[node] ?? const []).isNotEmpty) {
          limitReached = true;
        }
        continue;
      }
      for (final next in adjacency[node] ?? const <String>[]) {
        final nextDepth = depth + 1;
        final previous = visitedDepth[next];
        if (previous != null && previous >= nextDepth) continue;
        visitedDepth[next] = nextDepth;
        queue.add((next, nextDepth));
      }
    }
  }

  return (maxDepth: globalMax, limitReached: limitReached);
}
