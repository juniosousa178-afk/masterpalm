import 'secure_filesystem_artifact_backend.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_content_store.dart';
import 'secure_filesystem_location_resolver.dart';
import 'secure_filesystem_manifest_store.dart';
import 'secure_filesystem_path_resolver.dart';
import 'secure_filesystem_physical_backend_bridge.dart';
import 'secure_filesystem_quarantine_provider.dart';
import 'secure_filesystem_recovery_inspector.dart';
import '../../backend/persistent_artifact_backend_capability.dart';
import '../../backend/persistent_artifact_backend_environment.dart';
import '../../backend/persistent_artifact_backend_registration.dart';
import '../../persistent_artifact_backend_registry_impl.dart';

class SecureFilesystemBackendFactory {
  const SecureFilesystemBackendFactory._();

  static SecureFilesystemArtifactBackend create(
    SecureFilesystemBackendConfig config,
  ) {
    SecureFilesystemBackendConfigValidator.validateOrThrow(config);
    final pathResolver = SecureFilesystemPathResolver(config: config);
    final locationResolver = SecureFilesystemLocationResolver(
      config: config,
      pathResolver: pathResolver,
    );
    final contentStore = SecureFilesystemContentStore(
      config: config,
      pathResolver: pathResolver,
    );
    final manifestStore = SecureFilesystemManifestStore(
      config: config,
      pathResolver: pathResolver,
      locationResolver: locationResolver,
    );
    final quarantineProvider = SecureFilesystemQuarantineProvider(
      config: config,
      pathResolver: pathResolver,
    );
    final recoveryInspector = SecureFilesystemRecoveryInspector(
      config: config,
      pathResolver: pathResolver,
    );

    return SecureFilesystemArtifactBackend(
      config: config,
      contentStore: contentStore,
      manifestStore: manifestStore,
      locationResolver: locationResolver,
      contentReader: contentStore,
      contentWriter: contentStore,
      quarantineProvider: quarantineProvider,
      recoveryInspector: recoveryInspector,
      descriptor: SecureFilesystemBackendDescriptor(
        backendId: config.backendId,
        kind: 'secure-filesystem-reference',
        capabilities: SecureFilesystemBackendCapabilities(
          contentAddressedStorage: true,
          atomicWrites: config.useAtomicWrites,
          digestVerification: config.verifyDigestAfterWrite,
          quarantineDeletion: config.quarantineEnabled,
        ),
        metadata: config.metadata,
      ),
    );
  }

  static PersistentArtifactBackendRegistration createRegistration(
    SecureFilesystemBackendConfig config, {
    PersistentArtifactBackendEnvironmentContext environmentContext =
        PersistentArtifactBackendEnvironmentContext.nonProduction,
  }) {
    final backend = create(config);
    final capabilities = <PersistentArtifactBackendCapability>{
      PersistentArtifactBackendCapability.contentWrite,
      PersistentArtifactBackendCapability.contentRead,
      PersistentArtifactBackendCapability.contentExists,
      PersistentArtifactBackendCapability.contentMetadata,
      PersistentArtifactBackendCapability.manifestSave,
      PersistentArtifactBackendCapability.manifestLoad,
      PersistentArtifactBackendCapability.manifestLatest,
      PersistentArtifactBackendCapability.manifestQuery,
      PersistentArtifactBackendCapability.manifestList,
      PersistentArtifactBackendCapability.manifestInvalidate,
      PersistentArtifactBackendCapability.locationResolve,
      PersistentArtifactBackendCapability.quarantineDelete,
      PersistentArtifactBackendCapability.recoveryInspect,
      PersistentArtifactBackendCapability.recoveryRecover,
      PersistentArtifactBackendCapability.recoveryDiscard,
    };
    final _ = environmentContext;
    return PersistentArtifactBackendRegistration(
      descriptor: PersistentArtifactBackendDescriptor(
        backendId: config.backendId,
        kind: backend.descriptor.kind,
        capabilities: capabilities,
        environment: PersistentArtifactBackendEnvironment.localReferenceOnly,
        metadata: backend.descriptor.metadata,
      ),
      contentStore: backend.contentStore,
      manifestStore: backend.manifestStore,
      locationResolver: backend.locationResolver,
      contentReader: backend.contentReader,
      contentWriter: backend.contentWriter,
      quarantineProvider: backend.quarantineProvider,
      recoveryInspector: backend.recoveryInspector,
      bridge: SecureFilesystemPhysicalBackendBridge(
        backendId: config.backendId,
        contentStore: backend.contentStore as SecureFilesystemContentStore,
        manifestStore: backend.manifestStore as SecureFilesystemManifestStore,
        locationResolver: backend.locationResolver,
        quarantineProvider:
            backend.quarantineProvider as SecureFilesystemQuarantineProvider,
        recoveryInspector: backend.recoveryInspector,
      ),
    );
  }

  static PersistentArtifactBackendHandle registerInto(
    PersistentArtifactBackendRegistry registry,
    SecureFilesystemBackendConfig config, {
    PersistentArtifactBackendEnvironmentContext environmentContext =
        PersistentArtifactBackendEnvironmentContext.nonProduction,
  }) {
    final registration = createRegistration(
      config,
      environmentContext: environmentContext,
    );
    return registry.register(registration);
  }
}
