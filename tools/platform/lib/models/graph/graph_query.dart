import 'graph_edge_type.dart';
import 'graph_node_type.dart';

/// Query parameters for [GraphQueryEngine].
class GraphQuery {
  const GraphQuery({
    this.nodeId,
    this.nodeType,
    this.edgeType,
    this.sourceId,
    this.targetId,
    this.maxDepth = 1,
    this.includeSelf = false,
  });

  final String? nodeId;
  final GraphNodeType? nodeType;
  final GraphEdgeType? edgeType;
  final String? sourceId;
  final String? targetId;
  final int maxDepth;
  final bool includeSelf;
}
