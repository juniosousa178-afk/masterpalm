import '../core/provider_registry.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/score_provider.dart';
import '../providers/platform_score_provider.dart';
import '../score/policies/foundation_reference_policy.dart';
import '../models/score/score_policy.dart';
import '../score/score_canonical_serializer.dart';
import '../score/score_engine.dart';
import '../score/score_exceptions.dart';
import '../score/score_registry.dart';
import '../score/score_snapshot_id_factory.dart';
import '../score/stores/in_memory_score_store.dart';

/// Composition root for Score Engine integration.
class ScorePlatformBootstrap {
  const ScorePlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    ScoreProvider? scoreProvider,
    InMemoryScoreStore? store,
    ScoreRegistry? registryPolicies,
    List<ScorePolicy> extraPolicies = const [],
  }) {
    if (registry.isRegistered<ScoreProvider>()) return;

    if (!registry.isRegistered<MetricsProvider>()) {
      throw ScorePolicyException(
        'MetricsProvider must be registered before ScoreProvider',
      );
    }

    final policyRegistry = registryPolicies ?? ScoreRegistry();
    if (!policyRegistry.isFrozen) {
      policyRegistry.register(FoundationReferencePolicy.create());
      for (final policy in extraPolicies) {
        policyRegistry.register(policy);
      }
      policyRegistry.freeze();
    }

    final serializer = const ScoreCanonicalSerializer();
    final engine = ScoreEngine(
      registry: policyRegistry,
      serializer: serializer,
      idFactory: ScoreSnapshotIdFactory(serializer: serializer),
    );

    registry.registerInstance<ScoreProvider>(
      scoreProvider ??
          PlatformScoreProvider(
            engine: engine,
            registry: policyRegistry,
            store: store ?? InMemoryScoreStore(serializer: serializer),
            serializer: serializer,
          ),
    );
  }
}
