import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../../support/cloud_test_fixtures.dart';
import '../../support/fake_persistent_artifact_cloud_backend_bridge.dart';

class CloudOperationalHelpers {
  const CloudOperationalHelpers._();

  static PersistentArtifactBackendRegistry registryWithBridge({
    String backendId = 'cloud-backend-1',
    FakePersistentArtifactCloudBackendBridge? bridge,
  }) {
    final registry = PersistentArtifactBackendRegistry();
    final activeBridge = bridge ?? FakePersistentArtifactCloudBackendBridge();
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
    return registry;
  }

  static PersistentArtifactCloudOperationRequest request({
    CloudOperationType operation = CloudOperationType.putObject,
    String backendId = 'cloud-backend-1',
    String requestId = 'request-op-1',
    String objectKey = 'releases/v1/evidence.json',
  }) {
    final object = CloudTestFixtures.objectReference().copyWith(
      objectKey: objectKey,
    );
    return CloudTestFixtures.operationRequest().copyWith(
      backendId: backendId,
      requestId: requestId,
      operationType: operation,
      objectReference: object,
    );
  }

  static PersistentArtifactCloudOperationsService service({
    PersistentArtifactBackendRegistry? registry,
    PersistentArtifactRuntimeEnvironment runtimeEnvironment =
        PersistentArtifactRuntimeEnvironment.localReference,
  }) {
    return PersistentArtifactCloudOperationsService(
      registry: registry ?? registryWithBridge(),
      runtimeEnvironment: runtimeEnvironment,
    );
  }
}
