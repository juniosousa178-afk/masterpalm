import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';
import 'support/fake_persistent_artifact_cloud_backend_bridge.dart';

void main() {
  group('Persistent Artifact Cloud registry extension', () {
    test('cloudBridgeOf returns registered bridge', () {
      final registry = PersistentArtifactBackendRegistry();
      final bridge = FakePersistentArtifactCloudBackendBridge();
      registry.register(
        PersistentArtifactBackendRegistration(
          descriptor: PersistentArtifactBackendDescriptor(
            backendId: 'cloud-backend-1',
            kind: 'cloud',
            capabilities: const {
              PersistentArtifactBackendCapability.contentRead
            },
            environment:
                PersistentArtifactBackendEnvironment.localReferenceOnly,
          ),
          cloudDescriptor: CloudTestFixtures.backendDescriptor(),
          cloudBridge: bridge,
        ),
      );

      expect(registry.cloudBridgeOf('cloud-backend-1'), same(bridge));
      expect(registry.cloudBridgeOf('missing'), isNull);
    });

    test(
        'registration reports hasCloudRegistration=true only when both are set',
        () {
      final withBoth = PersistentArtifactBackendRegistration(
        descriptor: PersistentArtifactBackendDescriptor(
          backendId: 'a',
          kind: 'cloud',
          capabilities: const {},
          environment: PersistentArtifactBackendEnvironment.localReferenceOnly,
        ),
        cloudDescriptor: CloudTestFixtures.backendDescriptor(),
        cloudBridge: FakePersistentArtifactCloudBackendBridge(),
      );

      final withoutBridge = PersistentArtifactBackendRegistration(
        descriptor: withBoth.descriptor,
        cloudDescriptor: CloudTestFixtures.backendDescriptor(),
      );

      expect(withBoth.hasCloudRegistration, isTrue);
      expect(withoutBridge.hasCloudRegistration, isFalse);
    });
  });
}
