import '../core/provider_registry.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../providers/platform_release_supply_chain_provider.dart';
import 'policies/compliance_policy_v1.dart';
import 'policies/distribution_policy_v1.dart';
import 'policies/supply_chain_policy_v1.dart';
import 'release_supply_chain_policy_registry.dart';
import 'release_supply_chain_source_resolver.dart';
import 'stores/in_memory_release_supply_chain_store.dart';

/// Composition root for Release Supply Chain integration.
class ReleaseSupplyChainPlatformBootstrap {
  const ReleaseSupplyChainPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    ReleaseSupplyChainProvider? releaseSupplyChainProvider,
    InMemoryReleaseSupplyChainStore? store,
    SupplyChainPolicyRegistry? supplyChainPolicyRegistry,
    DistributionPolicyRegistry? distributionPolicyRegistry,
    CompliancePolicyRegistry? compliancePolicyRegistry,
  }) {
    if (registry.isRegistered<ReleaseSupplyChainProvider>()) return;

    if (!registry.isRegistered<ReleaseEvidenceProvider>()) {
      throw StateError(
        'ReleaseEvidenceProvider must be registered before ReleaseSupplyChainProvider',
      );
    }

    final supplyChainPolicies =
        supplyChainPolicyRegistry ?? SupplyChainPolicyRegistry();
    if (!supplyChainPolicies.isFrozen) {
      supplyChainPolicies.register(SupplyChainPolicyV1.create());
      supplyChainPolicies.freeze();
    }

    final distributionPolicies =
        distributionPolicyRegistry ?? DistributionPolicyRegistry();
    if (!distributionPolicies.isFrozen) {
      distributionPolicies.register(DistributionPolicyV1.create());
      distributionPolicies.freeze();
    }

    final compliancePolicies =
        compliancePolicyRegistry ?? CompliancePolicyRegistry();
    if (!compliancePolicies.isFrozen) {
      compliancePolicies.register(CompliancePolicyV1.create());
      compliancePolicies.freeze();
    }

    final sourceResolver = ReleaseSupplyChainSourceResolver(
      qualityGateProvider: registry.resolve<QualityGateProvider>(),
      releaseGovernanceProvider: registry.resolve<ReleaseGovernanceProvider>(),
      releaseEvidenceProvider: registry.resolve<ReleaseEvidenceProvider>(),
      supplyChainPolicyRegistry: supplyChainPolicies,
      distributionPolicyRegistry: distributionPolicies,
      compliancePolicyRegistry: compliancePolicies,
    );

    registry.registerInstance<ReleaseSupplyChainProvider>(
      releaseSupplyChainProvider ??
          PlatformReleaseSupplyChainProvider(
            sourceResolver: sourceResolver,
            supplyChainPolicyRegistry: supplyChainPolicies,
            distributionPolicyRegistry: distributionPolicies,
            compliancePolicyRegistry: compliancePolicies,
            store: store ?? InMemoryReleaseSupplyChainStore(),
          ),
    );
  }
}
