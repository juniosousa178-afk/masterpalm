import '../core/provider_registry.dart';
import '../interfaces/graph_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../providers/platform_metrics_provider.dart';
import 'metrics_engine.dart';

/// Composition root for Metrics Engine integration.
class MetricsPlatformBootstrap {
  const MetricsPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    GraphProvider? graphProvider,
    MetricsEngine? metricsEngine,
    MetricsProvider? metricsProvider,
  }) {
    if (registry.isRegistered<MetricsProvider>()) return;

    final graph = graphProvider ??
        (registry.isRegistered<GraphProvider>()
            ? registry.resolve<GraphProvider>()
            : null);

    final engine = metricsEngine ??
        MetricsEngine(
          graphProvider: graph,
        );

    registry.registerInstance<MetricsProvider>(
      metricsProvider ?? PlatformMetricsProvider(engine: engine),
    );
  }
}
