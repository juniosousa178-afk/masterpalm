import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_backend_descriptor.dart';
import 'persistent_artifact_cloud_backend_bridge.dart';
import 'persistent_artifact_cloud_bridge_classification.dart';

class PersistentArtifactCloudBackendRegistrationHandle {
  const PersistentArtifactCloudBackendRegistrationHandle({
    required this.backendId,
    required this.descriptor,
    required this.bridge,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
  });

  final String backendId;
  final PersistentArtifactCloudBackendDescriptor descriptor;
  final PersistentArtifactCloudBackendBridge bridge;
  final PersistentArtifactCloudBridgeClassification classification;
}
