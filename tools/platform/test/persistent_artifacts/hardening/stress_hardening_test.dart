import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('stress hardening with 300 writes', () async {
    final fake = FakePersistentArtifactBackend();
    final service = PersistentArtifactPhysicalOperationsService(
      registry: createRegistryWith(buildFakeRegistration(bridge: fake)),
    );
    for (var i = 0; i < 300; i++) {
      await service.writePhysicalContent(
        WritePhysicalContentRequest(
          backendId: hardeningBackendId,
          contentId: 'stress-$i',
          bytes: const [9, 9, 9],
        ),
      );
    }
    expect(fake.writes, 300);
  });
}
