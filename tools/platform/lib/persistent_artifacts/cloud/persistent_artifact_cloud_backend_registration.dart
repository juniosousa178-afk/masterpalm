import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_backend_descriptor.dart';
import '../backend/persistent_artifact_backend_registration.dart';
import 'persistent_artifact_cloud_backend_bridge.dart';

extension PersistentArtifactBackendRegistrationCloudX
    on PersistentArtifactBackendRegistration {
  bool get hasCloudRegistration =>
      cloudDescriptor != null && cloudBridge != null;

  PersistentArtifactCloudBackendDescriptor? get registeredCloudDescriptor =>
      cloudDescriptor;

  PersistentArtifactCloudBackendBridge? get registeredCloudBridge =>
      cloudBridge;
}
