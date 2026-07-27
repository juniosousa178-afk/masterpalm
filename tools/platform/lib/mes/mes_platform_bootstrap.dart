import '../core/provider_registry.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/score_provider.dart';
import '../models/score/score_policy.dart';
import '../providers/platform_mes_provider.dart';
import 'mes_engine.dart';
import 'mes_exceptions.dart';
import 'mes_registry.dart';
import 'mes_score_policy_mapper.dart';
import 'policies/mes_official_policy_v1.dart';
import 'stores/in_memory_mes_store.dart';

/// Composition root for MES integration.
class MESPlatformBootstrap {
  const MESPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    MESProvider? mesProvider,
    InMemoryMESStore? store,
    MESPolicyRegistry? policyRegistry,
  }) {
    if (registry.isRegistered<MESProvider>()) return;

    if (!registry.isRegistered<MetricsProvider>()) {
      throw MESPolicyException(
        'MetricsProvider must be registered before MESProvider',
      );
    }
    if (!registry.isRegistered<ScoreProvider>()) {
      throw MESPolicyException(
        'ScoreProvider must be registered before MESProvider',
      );
    }

    final mesRegistry = policyRegistry ?? MESPolicyRegistry();
    if (!mesRegistry.isFrozen) {
      mesRegistry.register(MesOfficialPolicyV1.create());
      mesRegistry.freeze();
    }

    final scoreProvider = registry.resolve<ScoreProvider>();
    final engine = MESEngine(
      registry: mesRegistry,
      scoreProvider: scoreProvider,
    );

    registry.registerInstance<MESProvider>(
      mesProvider ??
          PlatformMESProvider(
            engine: engine,
            registry: mesRegistry,
            store: store ?? InMemoryMESStore(),
          ),
    );
  }

  /// Score policies that must be registered in [ScorePlatformBootstrap].
  static List<ScorePolicy> scorePoliciesForBootstrap() {
    final mesPolicy = MesOfficialPolicyV1.create();
    return [const MESScorePolicyMapper().toScorePolicy(mesPolicy)];
  }
}
