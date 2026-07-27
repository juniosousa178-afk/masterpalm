import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';
import '../support/fake_persistent_artifact_cloud_backend_bridge.dart';

void main() {
  group('CloudHardeningOperational', () {
    test('bridge fake mantém classificação offlineSimulation', () async {
      final bridge = FakePersistentArtifactCloudBackendBridge();
      final described = await bridge.describe();
      expect(described.productionEligible, isFalse);
      expect(
        bridge.classification,
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
    });

    test('registry sem bridge não executa operação', () async {
      final service = CloudOperationalHelpers.service(
        registry: PersistentArtifactBackendRegistry(),
      );
      final result = await service.putObject(
        CloudOperationalHelpers.request(backendId: 'missing'),
      );
      expect(
        result.status,
        anyOf(
          PersistentArtifactCloudOperationStatus.unregistered,
          PersistentArtifactCloudOperationStatus.unavailable,
        ),
      );
    });
  });
}
