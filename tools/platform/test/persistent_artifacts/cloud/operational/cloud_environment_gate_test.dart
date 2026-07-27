import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudEnvironmentGate', () {
    const gate = PersistentArtifactCloudEnvironmentGate();

    test('offlineSimulation allows test', () {
      final decision = gate.evaluate(
        backendId: 'b1',
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.test,
        classification:
            PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
      expect(decision.allowed, isTrue);
      expect(decision.status, PersistentArtifactCloudOperationStatus.success);
    });

    test('offlineSimulation allows development', () {
      final decision = gate.evaluate(
        backendId: 'b1',
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.development,
        classification:
            PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
      expect(decision.allowed, isTrue);
    });

    test('offlineSimulation allows localReference', () {
      final decision = gate.evaluate(
        backendId: 'b1',
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.localReference,
        classification:
            PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
      expect(decision.allowed, isTrue);
    });

    test('offlineSimulation blocks staging', () {
      final decision = gate.evaluate(
        backendId: 'b1',
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.staging,
        classification:
            PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
      expect(decision.allowed, isFalse);
      expect(decision.status,
          PersistentArtifactCloudOperationStatus.stagingBlocked);
    });

    test('offlineSimulation blocks production', () {
      final decision = gate.evaluate(
        backendId: 'b1',
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.production,
        classification:
            PersistentArtifactCloudBridgeClassification.offlineSimulation,
      );
      expect(decision.allowed, isFalse);
      expect(decision.status,
          PersistentArtifactCloudOperationStatus.stagingBlocked);
    });

    test('contractOnly allows non-production validation environments', () {
      for (final env in [
        PersistentArtifactRuntimeEnvironment.test,
        PersistentArtifactRuntimeEnvironment.development,
        PersistentArtifactRuntimeEnvironment.localReference,
      ]) {
        final decision = gate.evaluate(
          backendId: 'b1',
          runtimeEnvironment: env,
          classification:
              PersistentArtifactCloudBridgeClassification.contractOnly,
        );
        expect(decision.allowed, isTrue);
        expect(decision.status, PersistentArtifactCloudOperationStatus.success);
      }
    });

    test('contractOnly blocks staging and production', () {
      for (final env in [
        PersistentArtifactRuntimeEnvironment.staging,
        PersistentArtifactRuntimeEnvironment.production,
      ]) {
        final decision = gate.evaluate(
          backendId: 'b1',
          runtimeEnvironment: env,
          classification:
              PersistentArtifactCloudBridgeClassification.contractOnly,
        );
        expect(decision.allowed, isFalse);
        expect(decision.status,
            PersistentArtifactCloudOperationStatus.stagingBlocked);
      }
    });
  });
}
