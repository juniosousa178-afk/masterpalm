import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('bridge failures are contained as failed status', () async {
    final fake = FakePersistentArtifactBackend()..fail = true;
    final service = PersistentArtifactPhysicalOperationsService(
      registry: createRegistryWith(buildFakeRegistration(bridge: fake)),
    );
    final result = await service.writePhysicalContent(
      const WritePhysicalContentRequest(
        backendId: hardeningBackendId,
        contentId: 'x',
        bytes: [1],
      ),
    );
    expect(result.status, PersistentArtifactPhysicalOperationStatus.failed);
  });
}
