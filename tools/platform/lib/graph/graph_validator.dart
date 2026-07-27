import '../models/graph/graph_validation_result.dart';
import '../models/graph/project_graph.dart';

/// Validates structural integrity of a [ProjectGraph].
class GraphValidator {
  const GraphValidator({this.allowSelfLoops = false});

  final bool allowSelfLoops;

  GraphValidationResult validate(ProjectGraph graph) {
    final errors = <String>[];
    final warnings = <String>[];
    final nodeIds = <String>{};
    final edgeKeys = <String>{};

    for (final node in graph.nodes) {
      if (node.id.isEmpty) {
        errors.add('Node with empty id detected');
        continue;
      }
      if (!nodeIds.add(node.id)) {
        errors.add('Duplicate node id: ${node.id}');
      }
      if (node.label.isEmpty) {
        warnings.add('Node ${node.id} has empty label');
      }
    }

    final index = graph.nodeIndex;

    for (final edge in graph.edges) {
      if (edge.sourceId.isEmpty) {
        errors.add('Edge with empty sourceId');
      }
      if (edge.targetId.isEmpty) {
        errors.add('Edge with empty targetId');
      }
      if (!edgeKeys.add(edge.dedupeKey)) {
        errors.add('Duplicate edge: ${edge.dedupeKey}');
      }
      if (!index.containsKey(edge.sourceId)) {
        errors.add('Orphan edge source: ${edge.sourceId}');
      }
      if (!index.containsKey(edge.targetId)) {
        errors.add('Orphan edge target: ${edge.targetId}');
      }
      if (!allowSelfLoops && edge.sourceId == edge.targetId) {
        errors.add('Self-loop not allowed: ${edge.dedupeKey}');
      }
    }

    if (graph.metadata.graphSchemaVersion < 1) {
      warnings.add('graphSchemaVersion below supported minimum');
    }

    return GraphValidationResult(
      valid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      nodeCount: graph.nodes.length,
      edgeCount: graph.edges.length,
    );
  }
}
