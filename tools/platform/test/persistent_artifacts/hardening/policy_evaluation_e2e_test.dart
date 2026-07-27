import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('policy evaluation e2e keeps default registry frozen behavior', () {
    final registry = PersistentArtifactPolicyRegistry(registerDefaults: true);
    expect(registry.list(), isNotEmpty);
    registry.freeze();
    expect(registry.isFrozen, isTrue);
  });
}
