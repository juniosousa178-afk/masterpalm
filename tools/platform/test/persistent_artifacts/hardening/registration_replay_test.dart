import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('registration replay is idempotent when compatible', () {
    final registry = PersistentArtifactBackendRegistry();
    final first = registry.register(
      buildFakeRegistration(
          backendId: 'replay', bridge: FakePersistentArtifactBackend()),
    );
    final second = registry.register(
      buildFakeRegistration(
          backendId: 'replay', bridge: FakePersistentArtifactBackend()),
    );
    expect(first.descriptor.backendId, second.descriptor.backendId);
  });
}
