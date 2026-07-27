import '../models/graph/project_graph.dart';

/// Contract for publishing and loading project graphs via Platform Core.
abstract class GraphProvider {
  Future<ProjectGraph?> load();

  Future<void> publish(ProjectGraph graph);

  Future<bool> isAvailable();

  Future<void> invalidate();
}
