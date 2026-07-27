import 'graph_edge.dart';
import 'graph_metadata.dart';
import 'graph_node.dart';

/// Immutable architectural graph for a MasterPalm project.
class ProjectGraph {
  const ProjectGraph({
    required this.nodes,
    required this.edges,
    required this.metadata,
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final GraphMetadata metadata;

  Map<String, GraphNode> get nodeIndex => {
        for (final node in nodes) node.id: node,
      };

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  factory ProjectGraph.fromJson(Map<String, dynamic> json) {
    return ProjectGraph(
      metadata: GraphMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>? ?? {},
      ),
      nodes: (json['nodes'] as List<dynamic>? ?? [])
          .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Structural JSON without non-deterministic metadata fields.
  Map<String, dynamic> toComparableJson() {
    final copy = Map<String, dynamic>.from(toJson());
    final meta = Map<String, dynamic>.from(copy['metadata'] as Map);
    meta.remove('generatedAt');
    copy['metadata'] = meta;
    return copy;
  }
}
