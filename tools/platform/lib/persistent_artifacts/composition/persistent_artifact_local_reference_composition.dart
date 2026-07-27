import '../../interfaces/cicd_integration_provider.dart';
import '../../interfaces/cryptographic_trust_provider.dart';
import '../../interfaces/release_evidence_provider.dart';
import '../../interfaces/release_supply_chain_provider.dart';
import '../../providers/platform_persistent_artifact_provider.dart';
import '../adapters/filesystem/secure_filesystem_backend_config.dart';
import '../adapters/filesystem/secure_filesystem_backend_factory.dart';
import '../backend/persistent_artifact_backend_environment.dart';
import '../backend/persistent_artifact_backend_environment_decision.dart';
import '../backend/persistent_artifact_backend_promotion_criteria.dart';
import '../backend/persistent_artifact_environment_gate.dart';
import '../persistent_artifact_backend_registry_impl.dart';
import '../persistent_artifact_operational_core.dart'
    show
        InMemoryPersistentArtifactSnapshotStore,
        PersistentArtifactPolicyRegistry,
        PersistentArtifactSourceResolver;

class PersistentArtifactLocalReferenceComposition {
  const PersistentArtifactLocalReferenceComposition({
    this.environment = PersistentArtifactRuntimeEnvironment.localReference,
    this.environmentContext =
        PersistentArtifactBackendEnvironmentContext.nonProduction,
    this.environmentGate = const PersistentArtifactEnvironmentGate(),
    this.promotionCriteria = const PersistentArtifactBackendPromotionCriteria(),
  });

  final PersistentArtifactRuntimeEnvironment environment;
  final PersistentArtifactBackendEnvironmentContext environmentContext;
  final PersistentArtifactEnvironmentGate environmentGate;
  final PersistentArtifactBackendPromotionCriteria promotionCriteria;

  PersistentArtifactLocalReferenceRuntime create({
    required SecureFilesystemBackendConfig filesystemConfig,
    required ReleaseEvidenceProvider releaseEvidenceProvider,
    required ReleaseSupplyChainProvider releaseSupplyChainProvider,
    required CicdIntegrationProvider cicdIntegrationProvider,
    required CryptographicTrustProvider cryptographicTrustProvider,
    PersistentArtifactPolicyRegistry? policyRegistry,
    InMemoryPersistentArtifactSnapshotStore? snapshotStore,
  }) {
    if (environment == PersistentArtifactRuntimeEnvironment.production) {
      throw StateError('production-blocked');
    }
    final registry = PersistentArtifactBackendRegistry(
      environmentContext: environmentContext,
      environmentGate: environmentGate,
    );
    SecureFilesystemBackendFactory.registerInto(
      registry,
      filesystemConfig,
      environmentContext: environmentContext,
    );
    final policies = policyRegistry ??
        PersistentArtifactPolicyRegistry(registerDefaults: true);
    final store = snapshotStore ?? InMemoryPersistentArtifactSnapshotStore();
    final provider = PlatformPersistentArtifactProvider(
      policyRegistry: policies,
      sourceResolver: PersistentArtifactSourceResolver(
        releaseEvidenceProvider: releaseEvidenceProvider,
        releaseSupplyChainProvider: releaseSupplyChainProvider,
        cicdIntegrationProvider: cicdIntegrationProvider,
        cryptographicTrustProvider: cryptographicTrustProvider,
      ),
      store: store,
      backendRegistry: registry,
    );
    return PersistentArtifactLocalReferenceRuntime(
      provider: provider,
      registry: registry,
      backendId: filesystemConfig.backendId,
      promotionCriteria: promotionCriteria,
      environmentDecision: registry.evaluateEnvironment(
        filesystemConfig.backendId,
        runtimeEnvironment: environment,
      ),
    );
  }
}

class PersistentArtifactLocalReferenceRuntime {
  PersistentArtifactLocalReferenceRuntime({
    required this.provider,
    required this.registry,
    required this.backendId,
    required this.promotionCriteria,
    required this.environmentDecision,
  });

  final PlatformPersistentArtifactProvider provider;
  final PersistentArtifactBackendRegistry registry;
  final String backendId;
  final PersistentArtifactBackendPromotionCriteria promotionCriteria;
  final PersistentArtifactBackendEnvironmentDecision environmentDecision;

  bool _disposed = false;
  bool _unregistered = false;

  bool get isDisposed => _disposed;
  bool get isUnregistered => _unregistered;

  bool unregister() {
    if (_unregistered) return false;
    _unregistered = true;
    return registry.unregister(backendId);
  }

  void dispose() {
    if (_disposed) return;
    unregister();
    _disposed = true;
  }
}
