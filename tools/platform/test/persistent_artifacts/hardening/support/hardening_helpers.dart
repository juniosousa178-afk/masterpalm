import 'package:masterpalm_platform/masterpalm_platform.dart';

const hardeningBackendId = 'hardening-backend';

PersistentArtifactBackendRegistration buildFakeRegistration({
  String backendId = hardeningBackendId,
  PersistentArtifactPhysicalBackendBridge? bridge,
}) {
  return PersistentArtifactBackendRegistration(
    descriptor: PersistentArtifactBackendDescriptor(
      backendId: backendId,
      kind: 'fake-hardening',
      capabilities: {
        PersistentArtifactBackendCapability.contentWrite,
        PersistentArtifactBackendCapability.contentRead,
        PersistentArtifactBackendCapability.contentExists,
        PersistentArtifactBackendCapability.contentMetadata,
        PersistentArtifactBackendCapability.manifestSave,
        PersistentArtifactBackendCapability.manifestLoad,
        PersistentArtifactBackendCapability.manifestLatest,
        PersistentArtifactBackendCapability.manifestQuery,
        PersistentArtifactBackendCapability.manifestInvalidate,
        PersistentArtifactBackendCapability.locationResolve,
        PersistentArtifactBackendCapability.quarantineDelete,
        PersistentArtifactBackendCapability.recoveryInspect,
        PersistentArtifactBackendCapability.recoveryRecover,
        PersistentArtifactBackendCapability.recoveryDiscard,
      },
      environment: PersistentArtifactBackendEnvironment(
        classification:
            PersistentArtifactBackendEnvironmentClassification.localReference,
        test: true,
        development: true,
        localReference: true,
        stagingEligible: false,
        productionEligible: false,
      ),
    ),
    bridge: bridge,
  );
}

PersistentArtifactBackendRegistry createRegistryWith(
  PersistentArtifactBackendRegistration registration,
) {
  final registry = PersistentArtifactBackendRegistry();
  registry.register(registration);
  return registry;
}
