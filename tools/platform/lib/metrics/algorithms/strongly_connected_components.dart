import '../../models/graph/project_graph.dart';

/// Deterministic Tarjan SCC over a directed adjacency list.
List<List<String>> stronglyConnectedComponents(
  Map<String, List<String>> adjacency,
  List<String> sortedNodeIds,
) {
  var index = 0;
  final stack = <String>[];
  final onStack = <String>{};
  final indices = <String, int>{};
  final lowlink = <String, int>{};
  final result = <List<String>>[];

  void strongConnect(String v) {
    indices[v] = index;
    lowlink[v] = index;
    index++;
    stack.add(v);
    onStack.add(v);

    for (final w in adjacency[v] ?? const <String>[]) {
      if (!indices.containsKey(w)) {
        strongConnect(w);
        lowlink[v] = lowlink[v]! < lowlink[w]! ? lowlink[v]! : lowlink[w]!;
      } else if (onStack.contains(w)) {
        lowlink[v] = lowlink[v]! < indices[w]! ? lowlink[v]! : indices[w]!;
      }
    }

    if (lowlink[v] == indices[v]) {
      final component = <String>[];
      while (true) {
        final w = stack.removeLast();
        onStack.remove(w);
        component.add(w);
        if (w == v) break;
      }
      component.sort();
      result.add(component);
    }
  }

  for (final nodeId in sortedNodeIds) {
    if (!indices.containsKey(nodeId)) {
      strongConnect(nodeId);
    }
  }

  result.sort((a, b) => a.join('|').compareTo(b.join('|')));
  return result;
}

/// Weakly connected components treating edges as undirected.
List<List<String>> weaklyConnectedComponents(ProjectGraph graph) {
  final parent = <String, String>{};
  final sortedIds = graph.nodes.map((n) => n.id).toList()..sort();

  String find(String x) {
    parent.putIfAbsent(x, () => x);
    if (parent[x] != x) {
      parent[x] = find(parent[x]!);
    }
    return parent[x]!;
  }

  void union(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    parent[rb] = ra;
  }

  for (final id in sortedIds) {
    parent.putIfAbsent(id, () => id);
  }

  for (final edge in graph.edges) {
    union(edge.sourceId, edge.targetId);
  }

  final groups = <String, List<String>>{};
  for (final id in sortedIds) {
    groups.putIfAbsent(find(id), () => []).add(id);
  }

  final components = groups.values.toList();
  for (final component in components) {
    component.sort();
  }
  components.sort((a, b) => a.join('|').compareTo(b.join('|')));
  return components;
}
