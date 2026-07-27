import '../core/provider_registry.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../providers/platform_release_governance_provider.dart';
import 'policies/release_governance_policy_v1.dart';
import 'policies/release_governance_policy_v1_1.dart';
import 'release_governance_engine.dart';
import 'release_governance_policy_registry.dart';
import 'release_governance_source_resolver.dart';
import 'stores/in_memory_release_governance_store.dart';

/// Composition root for Release Governance integration.
class ReleaseGovernancePlatformBootstrap {
  const ReleaseGovernancePlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    ReleaseGovernanceProvider? releaseGovernanceProvider,
    InMemoryReleaseGovernanceStore? store,
    ReleaseGovernancePolicyRegistry? policyRegistry,
  }) {
    if (registry.isRegistered<ReleaseGovernanceProvider>()) return;

    if (!registry.isRegistered<QualityGateProvider>()) {
      throw StateError(
        'QualityGateProvider must be registered before ReleaseGovernanceProvider',
      );
    }

    final policies = policyRegistry ?? ReleaseGovernancePolicyRegistry();
    if (!policies.isFrozen) {
      policies.register(ReleaseGovernancePolicyV1.create());
      policies.register(ReleaseGovernancePolicyV11.create());
      policies.freeze();
    }

    final sourceResolver = ReleaseGovernanceSourceResolver(
      qualityGateProvider: registry.resolve<QualityGateProvider>(),
    );

    final engine = ReleaseGovernanceEngine();

    registry.registerInstance<ReleaseGovernanceProvider>(
      releaseGovernanceProvider ??
          PlatformReleaseGovernanceProvider(
            engine: engine,
            policyRegistry: policies,
            sourceResolver: sourceResolver,
            store: store ?? InMemoryReleaseGovernanceStore(),
          ),
    );
  }
}
