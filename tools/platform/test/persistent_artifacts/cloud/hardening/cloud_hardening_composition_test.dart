import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import '../operational/support/cloud_operational_helpers.dart';

void main() {
  group('CloudHardeningCompositionRoot', () {
    test('create/register/use/unregister/dispose lifecycle', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      expect(runtime.registry.contains(runtime.backendId), isTrue);
      final result = await runtime.service.putObject(
        CloudOperationalHelpers.request(backendId: runtime.backendId),
      );
      expect(result.status, PersistentArtifactCloudOperationStatus.success);
      expect(runtime.unregister(), isTrue);
      expect(runtime.registry.contains(runtime.backendId), isFalse);
      runtime.dispose();
      runtime.dispose();
      expect(runtime.isDisposed, isTrue);
    });

    test('operation after unregister returns unregistered/unavailable',
        () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      runtime.unregister();
      final result = await runtime.service.putObject(
        CloudOperationalHelpers.request(backendId: runtime.backendId),
      );
      expect(
        result.status,
        anyOf(
          PersistentArtifactCloudOperationStatus.unregistered,
          PersistentArtifactCloudOperationStatus.unavailable,
        ),
      );
    });

    test('staging and production blocked at composition root', () {
      expect(
        () => PersistentArtifactOfflineCloudReferenceComposition(
          environment: PersistentArtifactRuntimeEnvironment.staging,
        ).create(),
        throwsStateError,
      );
      expect(
        () => PersistentArtifactOfflineCloudReferenceComposition(
          environment: PersistentArtifactRuntimeEnvironment.production,
        ).create(),
        throwsStateError,
      );
    });

    test('composition descriptor excludes runtime handles', () {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      final json = runtime.compositionDescriptorJson();
      expect(json.containsKey('bridge'), isFalse);
      expect(json.containsKey('objectTable'), isFalse);
      expect(json['stagingBlocked'], isTrue);
      expect(json['productionBlocked'], isTrue);
    });
  });
}
