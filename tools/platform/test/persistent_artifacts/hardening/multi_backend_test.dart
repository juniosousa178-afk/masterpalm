import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  test('multi backend lookup stays isolated', () async {
    final registry = PersistentArtifactBackendRegistry();
    registry.register(buildFakeRegistration(
        backendId: 'b1', bridge: FakePersistentArtifactBackend()));
    registry.register(buildFakeRegistration(
        backendId: 'b2', bridge: FakePersistentArtifactBackend()));
    expect(registry.backends(), containsAll(['b1', 'b2']));
  });
}
