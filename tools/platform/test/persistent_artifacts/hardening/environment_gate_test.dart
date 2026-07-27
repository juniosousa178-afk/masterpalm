import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('environment gate', () {
    const gate = PersistentArtifactEnvironmentGate();
    const env = PersistentArtifactBackendEnvironment(
      classification:
          PersistentArtifactBackendEnvironmentClassification.localReference,
      test: true,
      development: true,
      localReference: true,
      stagingEligible: false,
      productionEligible: false,
    );

    test('allows development', () {
      final decision = gate.evaluate(
        environment: env,
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.development,
      );
      expect(decision.allowed, isTrue);
    });

    test('blocks production always', () {
      final decision = gate.evaluate(
        environment: env,
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.production,
      );
      expect(decision.allowed, isFalse);
      expect(
        decision.status,
        PersistentArtifactPhysicalOperationStatus.environmentBlocked,
      );
    });
  });
}
