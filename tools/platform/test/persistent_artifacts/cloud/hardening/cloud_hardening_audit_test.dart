import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import '../operational/support/cloud_operational_helpers.dart';
import '../support/cloud_test_fixtures.dart';
import '../support/fake_persistent_artifact_cloud_backend_bridge.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningAudit', () {
    test('registry resolution determinístico por backendId', () {
      final registry = CloudOperationalHelpers.registryWithBridge();
      final resolved = registry.resolveCloudBackend('cloud-backend-1');
      expect(resolved.resolved, isTrue);
      expect(registry.resolveCloudBackend('missing').resolved, isFalse);
    });

    test('uma bridge call por put operation', () async {
      final bridge = FakePersistentArtifactCloudBackendBridge();
      final runtime = const PersistentArtifactOfflineCloudReferenceComposition()
          .create(bridge: bridge);
      addTearDown(runtime.dispose);
      await runtime.service.putObject(
        CloudHardeningHelpers.putRequest(backendId: runtime.backendId),
      );
      expect(
        CloudHardeningHelpers.bridgeCallCount(
          bridge,
          CloudOperationType.putObject,
        ),
        1,
      );
    });

    test('execution plan declarativo sem execução de retry', () {
      const evaluator = PersistentArtifactCloudBackendPolicyEvaluator();
      final plan = evaluator.evaluate(
        context: const PersistentArtifactCloudOperationContext(
          backendId: 'offline-cloud-ref',
          runtimeEnvironment:
              PersistentArtifactRuntimeEnvironment.localReference,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
          capability: PersistentArtifactCloudCapability.putObject,
          operation: CloudOperationType.putObject,
          correlationId: 'corr-1',
          requestId: 'req-1',
        ),
        capabilities: const {PersistentArtifactCloudCapability.putObject},
      );
      expect(plan.bridgeCallAllowed, isTrue);
      expect(plan.environmentDecision.allowed, isTrue);
    });

    test('retry classifier permanece puro', () {
      const classifier = PersistentArtifactCloudRetryClassifier();
      final throttled = classifier.classify(
        PersistentArtifactCloudOperationStatus.throttled,
      );
      final authRejected = classifier.classify(
        PersistentArtifactCloudOperationStatus.authenticationRejected,
      );
      expect(throttled.retryable, isTrue);
      expect(authRejected.retryable, isFalse);
    });

    test('policy evaluator não chama bridge', () {
      const evaluator = PersistentArtifactCloudBackendPolicyEvaluator();
      final plan = evaluator.evaluate(
        context: const PersistentArtifactCloudOperationContext(
          backendId: 'offline-cloud-ref',
          runtimeEnvironment:
              PersistentArtifactRuntimeEnvironment.localReference,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
          capability: PersistentArtifactCloudCapability.putObject,
          operation: CloudOperationType.putObject,
          correlationId: 'corr-1',
          requestId: 'req-1',
        ),
        capabilities: const {PersistentArtifactCloudCapability.putObject},
      );
      expect(
          plan.messages, isA<List<PersistentArtifactCloudExecutionMessage>>());
    });

    test('staging governance nunca aprova', () {
      const evaluator = PersistentArtifactCloudStagingGovernanceEvaluator();
      final decision = evaluator.evaluate(
        descriptor: CloudTestFixtures.backendDescriptor(),
        criteria: CloudTestFixtures.promotionCriteria(),
      );
      expect(decision.approved, isFalse);
      expect(decision.productionEligible, isFalse);
    });
  });
}
