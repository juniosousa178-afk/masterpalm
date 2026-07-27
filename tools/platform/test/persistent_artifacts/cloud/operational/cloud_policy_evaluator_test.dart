import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudBackendPolicyEvaluator', () {
    const evaluator = PersistentArtifactCloudBackendPolicyEvaluator();

    PersistentArtifactCloudOperationContext context({
      required PersistentArtifactRuntimeEnvironment env,
      required PersistentArtifactCloudBridgeClassification classification,
      required PersistentArtifactCloudCapability capability,
    }) {
      return PersistentArtifactCloudOperationContext(
        backendId: 'cloud-backend-1',
        operation: CloudOperationType.putObject,
        capability: capability,
        runtimeEnvironment: env,
        correlationId: 'corr-1',
        requestId: 'req-1',
        classification: classification,
      );
    }

    test('permite quando env e capability permitem', () {
      final plan = evaluator.evaluate(
        context: context(
          env: PersistentArtifactRuntimeEnvironment.localReference,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
          capability: PersistentArtifactCloudCapability.putObject,
        ),
        capabilities: const {PersistentArtifactCloudCapability.putObject},
      );
      expect(plan.bridgeCallAllowed, isTrue);
    });

    test('bloqueia quando capability ausente', () {
      final plan = evaluator.evaluate(
        context: context(
          env: PersistentArtifactRuntimeEnvironment.localReference,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
          capability: PersistentArtifactCloudCapability.putObject,
        ),
        capabilities: const {PersistentArtifactCloudCapability.getObject},
      );
      expect(plan.bridgeCallAllowed, isFalse);
      expect(plan.capabilityDecision.status,
          PersistentArtifactCloudOperationStatus.unsupported);
    });

    test('bloqueia staging', () {
      final plan = evaluator.evaluate(
        context: context(
          env: PersistentArtifactRuntimeEnvironment.staging,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
          capability: PersistentArtifactCloudCapability.putObject,
        ),
        capabilities: const {PersistentArtifactCloudCapability.putObject},
      );
      expect(plan.bridgeCallAllowed, isFalse);
      expect(plan.environmentDecision.status,
          PersistentArtifactCloudOperationStatus.stagingBlocked);
    });
  });
}
