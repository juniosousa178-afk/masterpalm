import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';
import 'support/fake_persistent_artifact_cloud_backend_bridge.dart';

void main() {
  group('Persistent Artifact Cloud hardening umbrella', () {
    test('defaults keep production blocked and staging disabled', () {
      final descriptor = CloudTestFixtures.backendDescriptor();
      expect(descriptor.productionEligible, isFalse);
      expect(descriptor.stagingEligible, isFalse);
    });

    test('validator blocks production flag in Part 1', () {
      final issues =
          PersistentArtifactCloudValidators.validateBackendDescriptor(
        CloudTestFixtures.backendDescriptor(productionEligible: true),
      );
      expect(issues.map((e) => e.code), contains('CLOUD_PRODUCTION_BLOCKED'));
    });

    test('fingerprints remain stable across repeated governance decisions', () {
      const evaluator = PersistentArtifactCloudStagingGovernanceEvaluator();
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: true);
      final criteria = CloudTestFixtures.promotionCriteria();
      final fps = List.generate(
        5,
        (_) => PersistentArtifactCloudFingerprint.stagingDecision(
          evaluator.evaluate(descriptor: descriptor, criteria: criteria),
        ),
      );
      expect(fps.toSet(), hasLength(1));
    });

    test('bridge capabilities do not imply auto registration', () async {
      final bridge = FakePersistentArtifactCloudBackendBridge();
      final registry = PersistentArtifactBackendRegistry();
      expect(registry.cloudBridgeOf('cloud-backend-1'), isNull);
      expect(
        await bridge.evaluateCapabilities(),
        contains(PersistentArtifactCloudCapability.putObject),
      );
    });
  });
}
