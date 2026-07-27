import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import '../support/fake_persistent_artifact_cloud_backend_bridge.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningStress', () {
    test('5000 registry lookups', () {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      for (var i = 0; i < 5000; i++) {
        final resolved =
            runtime.registry.resolveCloudBackend(runtime.backendId);
        expect(resolved.resolved, isTrue);
      }
    });

    test('1000 put operations sem rede', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      for (var i = 0; i < 1000; i++) {
        final result = await runtime.service.putObject(
          CloudHardeningHelpers.putRequest(
            backendId: runtime.backendId,
            requestId: 'stress-$i',
            objectKey: 'stress/$i.json',
          ),
        );
        expect(result.status, PersistentArtifactCloudOperationStatus.success);
      }
    });
  });

  group('CloudHardeningPerformance', () {
    test('registra baseline aproximado de put', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      final stopwatch = Stopwatch()..start();
      const iterations = 500;
      for (var i = 0; i < iterations; i++) {
        await runtime.service.putObject(
          CloudHardeningHelpers.putRequest(
            backendId: runtime.backendId,
            requestId: 'perf-$i',
          ),
        );
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(60000));
    });
  });

  group('CloudHardeningErrorContainment', () {
    test('bridge exception não vaza stack trace', () async {
      final bridge = FakePersistentArtifactCloudBackendBridge(
        injectedFailures: {
          CloudOperationType.putObject: StateError('injected'),
        },
      );
      final runtime = const PersistentArtifactOfflineCloudReferenceComposition()
          .create(bridge: bridge);
      addTearDown(runtime.dispose);
      final result = await runtime.service.putObject(
        CloudHardeningHelpers.putRequest(backendId: runtime.backendId),
      );
      expect(result.status, PersistentArtifactCloudOperationStatus.failed);
      expect(
        result.messages.any((m) => m.message.contains('injected')),
        isFalse,
      );
    });
  });
}
