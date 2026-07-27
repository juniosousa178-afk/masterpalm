import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('performance hardening keeps fake writes under threshold', () async {
    final fake = FakePersistentArtifactBackend();
    final service = PersistentArtifactPhysicalOperationsService(
      registry: createRegistryWith(buildFakeRegistration(bridge: fake)),
    );
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      await service.writePhysicalContent(
        WritePhysicalContentRequest(
          backendId: hardeningBackendId,
          contentId: 'perf-$i',
          bytes: const [1],
        ),
      );
    }
    sw.stop();
    expect(sw.elapsedMilliseconds < 3000, isTrue);
  });
}
