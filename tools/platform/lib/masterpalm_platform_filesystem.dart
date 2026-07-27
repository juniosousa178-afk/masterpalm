library masterpalm_platform_filesystem;

export 'persistent_artifacts/adapters/filesystem/secure_filesystem_artifact_backend.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_backend_config.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_backend_factory.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_backend_result.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_content_handle.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_content_store.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_location_resolver.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_manifest_store.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_path_resolver.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_physical_backend_bridge.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_quarantine_provider.dart';
export 'persistent_artifacts/adapters/filesystem/secure_filesystem_recovery_inspector.dart';
export 'persistent_artifacts/composition/persistent_artifact_local_reference_composition.dart';
export 'persistent_artifacts/persistent_artifact_backend_registry.dart'
    show
        PersistentArtifactBackendRegistry,
        PersistentArtifactBackendEnvironmentContext,
        PersistentArtifactBackendHandle,
        PersistentArtifactBackendRegistration;

import 'persistent_artifacts/adapters/filesystem/secure_filesystem_backend_config.dart';
import 'persistent_artifacts/adapters/filesystem/secure_filesystem_backend_factory.dart';
import 'persistent_artifacts/composition/persistent_artifact_local_reference_composition.dart';
import 'persistent_artifacts/persistent_artifact_backend_registry.dart';

PersistentArtifactBackendRegistration createSecureFilesystemRegistration(
  SecureFilesystemBackendConfig config, {
  PersistentArtifactBackendEnvironmentContext environmentContext =
      PersistentArtifactBackendEnvironmentContext.nonProduction,
}) {
  return SecureFilesystemBackendFactory.createRegistration(
    config,
    environmentContext: environmentContext,
  );
}

PersistentArtifactBackendHandle registerSecureFilesystemBackend(
  PersistentArtifactBackendRegistry registry,
  SecureFilesystemBackendConfig config, {
  PersistentArtifactBackendEnvironmentContext environmentContext =
      PersistentArtifactBackendEnvironmentContext.nonProduction,
}) {
  return SecureFilesystemBackendFactory.registerInto(
    registry,
    config,
    environmentContext: environmentContext,
  );
}

PersistentArtifactLocalReferenceComposition
    createPersistentArtifactLocalReferenceComposition({
  PersistentArtifactBackendEnvironmentContext environmentContext =
      PersistentArtifactBackendEnvironmentContext.nonProduction,
}) {
  return PersistentArtifactLocalReferenceComposition(
    environmentContext: environmentContext,
  );
}
