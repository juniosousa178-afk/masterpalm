import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('production environment remains blocked', () {
    const gate = PersistentArtifactEnvironmentGate();
    final decision = gate.evaluate(
      environment: PersistentArtifactBackendEnvironment.localReferenceOnly,
      runtimeEnvironment: PersistentArtifactRuntimeEnvironment.production,
    );
    expect(decision.allowed, isFalse);
    expect(decision.reasonCode, 'production-blocked');
  });
}
