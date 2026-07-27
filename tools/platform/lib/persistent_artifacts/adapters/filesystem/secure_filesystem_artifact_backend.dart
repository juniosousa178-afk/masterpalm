import '../../interfaces/persistent_artifact_content_reader.dart';
import '../../interfaces/persistent_artifact_content_store.dart';
import '../../interfaces/persistent_artifact_content_writer.dart';
import '../../interfaces/persistent_artifact_location_resolver.dart';
import '../../interfaces/persistent_artifact_manifest_store.dart';
import '../../interfaces/persistent_artifact_physical_deletion_provider.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_manifest_store.dart';
import 'secure_filesystem_quarantine_provider.dart';
import 'secure_filesystem_recovery_inspector.dart';

class SecureFilesystemBackendCapabilities {
  const SecureFilesystemBackendCapabilities({
    required this.contentAddressedStorage,
    required this.atomicWrites,
    required this.digestVerification,
    required this.quarantineDeletion,
  });

  final bool contentAddressedStorage;
  final bool atomicWrites;
  final bool digestVerification;
  final bool quarantineDeletion;
}

class SecureFilesystemBackendDescriptor {
  const SecureFilesystemBackendDescriptor({
    required this.backendId,
    required this.kind,
    required this.capabilities,
    this.metadata = const {},
  });

  final String backendId;
  final String kind;
  final SecureFilesystemBackendCapabilities capabilities;
  final Map<String, String> metadata;
}

class SecureFilesystemArtifactBackend {
  const SecureFilesystemArtifactBackend({
    required this.config,
    required this.contentStore,
    required this.manifestStore,
    required this.locationResolver,
    required this.contentReader,
    required this.contentWriter,
    required this.quarantineProvider,
    required this.recoveryInspector,
    required this.descriptor,
  });

  final SecureFilesystemBackendConfig config;
  final PersistentArtifactContentStore contentStore;
  final PersistentArtifactManifestStore manifestStore;
  final PersistentArtifactLocationResolver locationResolver;
  final PersistentArtifactContentReader contentReader;
  final PersistentArtifactContentWriter contentWriter;
  final PersistentArtifactPhysicalDeletionProvider quarantineProvider;
  final SecureFilesystemRecoveryInspector recoveryInspector;
  final SecureFilesystemBackendDescriptor descriptor;

  SecureFilesystemManifestStore get manifestStoreExtended =>
      manifestStore as SecureFilesystemManifestStore;
  SecureFilesystemQuarantineProvider get quarantineProviderExtended =>
      quarantineProvider as SecureFilesystemQuarantineProvider;
}
