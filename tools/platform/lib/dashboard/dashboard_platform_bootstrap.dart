import '../core/provider_registry.dart';
import '../interfaces/dashboard_provider.dart';
import '../interfaces/graph_provider.dart';
import '../interfaces/guardian_provider.dart';
import '../interfaces/history_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/score_provider.dart';
import '../providers/platform_dashboard_provider.dart';
import 'dashboard_compatibility_checker.dart';
import 'dashboard_engine.dart';
import 'dashboard_freshness_evaluator.dart';
import 'dashboard_registry.dart';
import 'dashboard_request_validator.dart';
import 'dashboard_source_resolver.dart';
import 'dashboard_validator.dart';
import 'stores/in_memory_dashboard_store.dart';

/// Composition root for Dashboard integration.
class DashboardPlatformBootstrap {
  const DashboardPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    DashboardProvider? dashboardProvider,
    InMemoryDashboardStore? store,
    DashboardRegistry? dashboardRegistry,
  }) {
    if (registry.isRegistered<DashboardProvider>()) return;

    if (!registry.isRegistered<MetricsProvider>()) {
      throw StateError(
          'MetricsProvider must be registered before DashboardProvider');
    }
    if (!registry.isRegistered<HistoryProvider>()) {
      throw StateError(
          'HistoryProvider must be registered before DashboardProvider');
    }
    if (!registry.isRegistered<ScoreProvider>()) {
      throw StateError(
          'ScoreProvider must be registered before DashboardProvider');
    }
    if (!registry.isRegistered<MESProvider>()) {
      throw StateError(
          'MESProvider must be registered before DashboardProvider');
    }

    final reg = dashboardRegistry ?? DashboardRegistry();
    if (!reg.isFrozen) {
      DashboardRegistry.registerFoundation(reg);
    }

    final sourceResolver = DashboardSourceResolver(
      metricsProvider: registry.resolve<MetricsProvider>(),
      historyProvider: registry.resolve<HistoryProvider>(),
      scoreProvider: registry.resolve<ScoreProvider>(),
      mesProvider: registry.resolve<MESProvider>(),
      graphProvider: registry.isRegistered<GraphProvider>()
          ? registry.resolve<GraphProvider>()
          : null,
      guardianProvider: registry.isRegistered<GuardianProvider>()
          ? registry.resolve<GuardianProvider>()
          : null,
      registry: registry,
    );

    final engine = DashboardEngine(
      sourceResolver: sourceResolver,
      registry: reg,
      requestValidator: const DashboardRequestValidator(),
      snapshotValidator: const DashboardValidator(),
      compatibilityChecker: const DashboardCompatibilityChecker(),
      freshnessEvaluator: const DashboardFreshnessEvaluator(),
    );

    registry.registerInstance<DashboardProvider>(
      dashboardProvider ??
          PlatformDashboardProvider(
            engine: engine,
            store: store ?? InMemoryDashboardStore(),
            registry: reg,
          ),
    );
  }
}
