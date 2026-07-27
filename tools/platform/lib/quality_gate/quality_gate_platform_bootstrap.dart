import '../core/provider_registry.dart';
import '../interfaces/dashboard_provider.dart';
import '../interfaces/history_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/observability_provider.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/score_provider.dart';
import '../providers/platform_quality_gate_provider.dart';
import 'policies/quality_gate_release_policy_v1.dart';
import 'quality_gate_engine.dart';
import 'quality_gate_policy_registry.dart';
import 'quality_gate_rule_evaluator.dart';
import 'quality_gate_source_resolver.dart';
import 'quality_gate_target_registry.dart';
import 'stores/in_memory_quality_gate_store.dart';

/// Composition root for Quality Gate integration.
class QualityGatePlatformBootstrap {
  const QualityGatePlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    QualityGateProvider? qualityGateProvider,
    InMemoryQualityGateStore? store,
    QualityGatePolicyRegistry? policyRegistry,
  }) {
    if (registry.isRegistered<QualityGateProvider>()) return;

    if (!registry.isRegistered<MetricsProvider>() ||
        !registry.isRegistered<ScoreProvider>() ||
        !registry.isRegistered<MESProvider>() ||
        !registry.isRegistered<HistoryProvider>() ||
        !registry.isRegistered<ObservabilityProvider>() ||
        !registry.isRegistered<DashboardProvider>()) {
      throw StateError(
        'Metrics, Score, MES, History, Observability and Dashboard providers '
        'must be registered before QualityGateProvider',
      );
    }

    final policies = policyRegistry ?? QualityGatePolicyRegistry();
    if (!policies.isFrozen) {
      policies.register(QualityGateReleasePolicyV1.create());
      policies.freeze();
    }

    final targetRegistry = QualityGateTargetRegistry();
    final sourceResolver = QualityGateSourceResolver(
      metricsProvider: registry.resolve<MetricsProvider>(),
      scoreProvider: registry.resolve<ScoreProvider>(),
      mesProvider: registry.resolve<MESProvider>(),
      observabilityProvider: registry.resolve<ObservabilityProvider>(),
      dashboardProvider: registry.resolve<DashboardProvider>(),
    );

    final engine = QualityGateEngine(
      ruleEvaluator: QualityGateRuleEvaluator(
        targetRegistry: targetRegistry,
      ),
    );

    registry.registerInstance<QualityGateProvider>(
      qualityGateProvider ??
          PlatformQualityGateProvider(
            engine: engine,
            policyRegistry: policies,
            sourceResolver: sourceResolver,
            store: store ?? InMemoryQualityGateStore(),
          ),
    );
  }
}
