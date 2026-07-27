import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../persistent_artifacts/cloud/support/fake_persistent_artifact_cloud_backend_bridge.dart';
import '../persistent_artifacts/cloud/support/cloud_test_fixtures.dart';
import '../persistent_artifacts/hardening/support/null_source_providers.dart';

/// Offline reference composition root for cloud integration tests.
///
/// Not a global bootstrap. Fake bridge is test-only and does not represent
/// vendor behaviour or remote persistence.
class PersistentArtifactOfflineCloudReferenceComposition {
  const PersistentArtifactOfflineCloudReferenceComposition({
    this.environment = PersistentArtifactRuntimeEnvironment.localReference,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
    this.environmentGate = const PersistentArtifactCloudEnvironmentGate(),
  });

  final PersistentArtifactRuntimeEnvironment environment;
  final PersistentArtifactCloudBridgeClassification classification;
  final PersistentArtifactCloudEnvironmentGate environmentGate;

  PersistentArtifactOfflineCloudReferenceRuntime create({
    String backendId = 'offline-cloud-ref',
    FakePersistentArtifactCloudBackendBridge? bridge,
    PersistentArtifactPolicyRegistry? policyRegistry,
    InMemoryPersistentArtifactSnapshotStore? snapshotStore,
    ReleaseEvidenceProvider? releaseEvidenceProvider,
    ReleaseSupplyChainProvider? releaseSupplyChainProvider,
    CicdIntegrationProvider? cicdIntegrationProvider,
    CryptographicTrustProvider? cryptographicTrustProvider,
  }) {
    if (environment == PersistentArtifactRuntimeEnvironment.staging ||
        environment == PersistentArtifactRuntimeEnvironment.production) {
      throw StateError('staging-production-blocked');
    }

    final registry = PersistentArtifactBackendRegistry();
    final activeBridge = bridge ??
        FakePersistentArtifactCloudBackendBridge(
          classification: classification,
        );
    final descriptor =
        CloudTestFixtures.backendDescriptor().copyWith(backendId: backendId);
    registry.register(
      PersistentArtifactBackendRegistration(
        descriptor: PersistentArtifactBackendDescriptor(
          backendId: backendId,
          kind: 'cloud',
          capabilities: const {
            PersistentArtifactBackendCapability.contentRead,
          },
          environment: PersistentArtifactBackendEnvironment.localReferenceOnly,
        ),
        cloudDescriptor: descriptor,
        cloudBridge: activeBridge,
      ),
    );

    final policies = policyRegistry ??
        PersistentArtifactPolicyRegistry(registerDefaults: true);
    final store = snapshotStore ?? InMemoryPersistentArtifactSnapshotStore();
    final provider = PlatformPersistentArtifactProvider(
      policyRegistry: policies,
      sourceResolver: PersistentArtifactSourceResolver(
        releaseEvidenceProvider:
            releaseEvidenceProvider ?? NullReleaseEvidenceProvider(),
        releaseSupplyChainProvider:
            releaseSupplyChainProvider ?? NullReleaseSupplyChainProvider(),
        cicdIntegrationProvider: cicdIntegrationProvider ?? NullCicdProvider(),
        cryptographicTrustProvider:
            cryptographicTrustProvider ?? NullCryptographicTrustProvider(),
      ),
      store: store,
      backendRegistry: registry,
    );
    final service = PersistentArtifactCloudOperationsService(
      registry: registry,
      runtimeEnvironment: environment,
    );
    final environmentDecision = registry.evaluateCloudEnvironment(
      backendId,
      environment,
    );

    return PersistentArtifactOfflineCloudReferenceRuntime(
      registry: registry,
      bridge: activeBridge,
      service: service,
      provider: provider,
      backendId: backendId,
      descriptor: descriptor,
      environment: environment,
      environmentDecision: environmentDecision,
    );
  }
}

class PersistentArtifactOfflineCloudReferenceRuntime {
  PersistentArtifactOfflineCloudReferenceRuntime({
    required this.registry,
    required this.bridge,
    required this.service,
    required this.provider,
    required this.backendId,
    required this.descriptor,
    required this.environment,
    required this.environmentDecision,
  });

  final PersistentArtifactBackendRegistry registry;
  final FakePersistentArtifactCloudBackendBridge bridge;
  final PersistentArtifactCloudOperationsService service;
  final PlatformPersistentArtifactProvider provider;
  final String backendId;
  final PersistentArtifactCloudBackendDescriptor descriptor;
  final PersistentArtifactRuntimeEnvironment environment;
  final PersistentArtifactCloudEnvironmentDecision environmentDecision;

  bool _disposed = false;
  bool _unregistered = false;

  bool get isDisposed => _disposed;
  bool get isUnregistered => _unregistered;

  Map<String, dynamic> compositionDescriptorJson() => {
        'backendId': backendId,
        'environment': environment.name,
        'classification': bridge.classification.wireName,
        'environmentAllowed': environmentDecision.allowed,
        'stagingBlocked': true,
        'productionBlocked': true,
      };

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
