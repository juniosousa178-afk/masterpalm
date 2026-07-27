import '../interfaces/graph_provider.dart';
import '../models/graph/project_graph.dart';

/// In-memory [GraphProvider] implementation (no disk persistence).
class InMemoryGraphProvider implements GraphProvider {
  ProjectGraph? _graph;

  @override
  Future<ProjectGraph?> load() async => _graph;

  @override
  Future<void> publish(ProjectGraph graph) async {
    _graph = graph;
  }

  @override
  Future<bool> isAvailable() async => _graph != null;

  @override
  Future<void> invalidate() async {
    _graph = null;
  }
}
