import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('concurrency hardening handles parallel writes', () async {
    final fake = FakePersistentArtifactBackend();
    final service = PersistentArtifactPhysicalOperationsService(
      registry: createRegistryWith(buildFakeRegistration(bridge: fake)),
    );
    await Future.wait(
      List.generate(
        20,
        (i) => service.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: hardeningBackendId,
            contentId: 'c-$i',
            bytes: const [1, 2],
          ),
        ),
      ),
    );
    expect(fake.writes, 20);
  });
}
