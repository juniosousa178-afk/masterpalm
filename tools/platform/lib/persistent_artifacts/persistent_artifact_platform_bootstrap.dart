import '../core/provider_registry.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../interfaces/persistent_artifact_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import 'persistent_artifact_operational_core.dart';

class PersistentArtifactPlatformBootstrap {
  const PersistentArtifactPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    PersistentArtifactProvider? persistentArtifactProvider,
    PersistentArtifactPolicyRegistry? policyRegistry,
    InMemoryPersistentArtifactSnapshotStore? store,
  }) {
    if (registry.isRegistered<PersistentArtifactProvider>()) return;
    if (!registry.isRegistered<ReleaseEvidenceProvider>()) {
      throw StateError(
        'ReleaseEvidenceProvider must be registered before PersistentArtifactProvider',
      );
    }
    if (!registry.isRegistered<ReleaseSupplyChainProvider>()) {
      throw StateError(
        'ReleaseSupplyChainProvider must be registered before PersistentArtifactProvider',
      );
    }
    if (!registry.isRegistered<CicdIntegrationProvider>()) {
      throw StateError(
        'CicdIntegrationProvider must be registered before PersistentArtifactProvider',
      );
    }
    if (!registry.isRegistered<CryptographicTrustProvider>()) {
      throw StateError(
        'CryptographicTrustProvider must be registered before PersistentArtifactProvider',
      );
    }

    final policies = policyRegistry ?? PersistentArtifactPolicyRegistry();
    if (!policies.isFrozen) {
      policies.registerDefaultPolicies();
      policies.freeze();
    }

    registry.registerInstance<PersistentArtifactProvider>(
      persistentArtifactProvider ??
          PlatformPersistentArtifactProvider(
            policyRegistry: policies,
            sourceResolver: PersistentArtifactSourceResolver(
              releaseEvidenceProvider:
                  registry.resolve<ReleaseEvidenceProvider>(),
              releaseSupplyChainProvider:
                  registry.resolve<ReleaseSupplyChainProvider>(),
              cicdIntegrationProvider:
                  registry.resolve<CicdIntegrationProvider>(),
              cryptographicTrustProvider:
                  registry.resolve<CryptographicTrustProvider>(),
            ),
            store: store ?? InMemoryPersistentArtifactSnapshotStore(),
          ),
    );
  }
}
