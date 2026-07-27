import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('registry exports environment decision API', () {
    final registry = PersistentArtifactBackendRegistry();
    final decision = registry.evaluateEnvironment('missing');
    expect(decision.allowed, isFalse);
    expect(decision.reasonCode, 'backend-unregistered');
  });
}
