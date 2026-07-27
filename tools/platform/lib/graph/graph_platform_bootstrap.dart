import '../core/platform_core.dart';
import '../core/provider_registry.dart';
import '../graph/graph_engine.dart';
import '../interfaces/ast_provider.dart';
import '../interfaces/graph_provider.dart';
import '../models/graph/project_graph.dart';
import '../providers/in_memory_graph_provider.dart';

/// Composition root for Graph Engine integration.
class GraphPlatformBootstrap {
  const GraphPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    GraphProvider? graphProvider,
    GraphEngine? graphEngine,
  }) {
    if (!registry.isRegistered<GraphProvider>()) {
      registry.registerInstance<GraphProvider>(
        graphProvider ?? InMemoryGraphProvider(),
      );
    }
    if (graphEngine != null && !registry.isRegistered<GraphEngine>()) {
      registry.registerInstance<GraphEngine>(graphEngine);
    }
  }

  static Future<ProjectGraph> buildAndPublish({
    required PlatformCore platform,
    GraphEngine? engine,
    GraphProvider? provider,
  }) async {
    final graphEngine = engine ?? GraphEngine();
    final graphProvider = provider ?? platform.graph();
    final graph = graphEngine.buildFromAstProvider(platform.ast());
    await graphProvider.publish(graph);
    return graph;
  }

  static Future<ProjectGraph> buildFromAst(AstProvider ast,
      {GraphEngine? engine}) {
    final graphEngine = engine ?? GraphEngine();
    return Future.value(graphEngine.buildFromAstProvider(ast));
  }
}
