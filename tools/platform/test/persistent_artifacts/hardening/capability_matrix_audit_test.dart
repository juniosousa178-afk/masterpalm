import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/hardening_helpers.dart';

void main() {
  test('capability matrix exposes fake backend capabilities', () {
    final registration = buildFakeRegistration();
    expect(
      registration.descriptor.capabilities.contains(
        PersistentArtifactBackendCapability.contentWrite,
      ),
      isTrue,
    );
    expect(
      registration.descriptor.capabilities.contains(
        PersistentArtifactBackendCapability.manifestLoad,
      ),
      isTrue,
    );
  });
}
