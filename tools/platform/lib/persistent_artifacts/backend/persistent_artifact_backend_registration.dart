import '../interfaces/persistent_artifact_content_reader.dart';
import '../interfaces/persistent_artifact_content_store.dart';
import '../interfaces/persistent_artifact_content_writer.dart';
import '../interfaces/persistent_artifact_location_resolver.dart';
import '../interfaces/persistent_artifact_manifest_store.dart';
import '../interfaces/persistent_artifact_physical_deletion_provider.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_backend_descriptor.dart';
import '../cloud/persistent_artifact_cloud_backend_bridge.dart';
import 'persistent_artifact_backend_capability.dart';
import 'persistent_artifact_backend_environment.dart';
import 'persistent_artifact_physical_backend_bridge.dart';

abstract interface class PersistentArtifactRecoveryInspector {
  Future<List<String>> listQuarantinedReferences();
  Future<List<String>> listOrphanTemporaryObjects();
  Future<List<String>> inspectInterruptedOperations();
  Future<bool> recoverTemporaryObject(String reference);
  Future<bool> discardTemporaryObject(String reference);
}

class PersistentArtifactBackendDescriptor {
  const PersistentArtifactBackendDescriptor({
    required this.backendId,
    required this.kind,
    required this.capabilities,
    required this.environment,
    this.metadata = const {},
  });

  final String backendId;
  final String kind;
  final Set<PersistentArtifactBackendCapability> capabilities;
  final PersistentArtifactBackendEnvironment environment;
  final Map<String, String> metadata;
}

class PersistentArtifactBackendRegistration {
  const PersistentArtifactBackendRegistration({
    required this.descriptor,
    this.contentStore,
    this.manifestStore,
    this.locationResolver,
    this.contentReader,
    this.contentWriter,
    this.quarantineProvider,
    this.recoveryInspector,
    this.bridge,
    this.cloudDescriptor,
    this.cloudBridge,
    this.runtimeRegistration = true,
  });

  final PersistentArtifactBackendDescriptor descriptor;
  final PersistentArtifactContentStore? contentStore;
  final PersistentArtifactManifestStore? manifestStore;
  final PersistentArtifactLocationResolver? locationResolver;
  final PersistentArtifactContentReader? contentReader;
  final PersistentArtifactContentWriter? contentWriter;
  final PersistentArtifactPhysicalDeletionProvider? quarantineProvider;
  final PersistentArtifactRecoveryInspector? recoveryInspector;
  final PersistentArtifactPhysicalBackendBridge? bridge;
  final PersistentArtifactCloudBackendDescriptor? cloudDescriptor;
  final PersistentArtifactCloudBackendBridge? cloudBridge;
  final bool runtimeRegistration;
}

class PersistentArtifactBackendHandle {
  const PersistentArtifactBackendHandle({
    required this.descriptor,
    required this.registration,
  });

  final PersistentArtifactBackendDescriptor descriptor;
  final PersistentArtifactBackendRegistration registration;
}
