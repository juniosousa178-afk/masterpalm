import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('evaluate publish IO guard via counters', () async {
    final fake = FakePersistentArtifactBackend();
    final service = PersistentArtifactPhysicalOperationsService(
      registry: createRegistryWith(buildFakeRegistration(bridge: fake)),
    );
    await service.writePhysicalContent(
      const WritePhysicalContentRequest(
        backendId: hardeningBackendId,
        contentId: 'x',
        bytes: [1],
      ),
    );
    expect(fake.writes, 1);
    expect(fake.reads, 0);
  });
}
