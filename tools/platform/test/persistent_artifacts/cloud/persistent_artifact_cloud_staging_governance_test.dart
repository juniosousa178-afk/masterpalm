import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud staging governance', () {
    const evaluator = PersistentArtifactCloudStagingGovernanceEvaluator();

    test('approved when descriptor satisfies criteria and staging enabled', () {
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: true);
      final decision = evaluator.evaluate(
        descriptor: descriptor,
        criteria: CloudTestFixtures.promotionCriteria(),
      );
      expect(decision.approved, isTrue);
      expect(decision.status, CloudPromotionStatus.approved);
      expect(decision.productionEligible, isFalse);
    });

    test('blocked when encryption at rest missing', () {
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: true).copyWith(
        encryption: CloudTestFixtures.encryption().copyWith(atRest: false),
      );
      final decision = evaluator.evaluate(
        descriptor: descriptor,
        criteria: CloudTestFixtures.promotionCriteria(),
      );
      expect(decision.approved, isFalse);
      expect(
        decision.issues.map((e) => e.code),
        contains('CLOUD_ENCRYPTION_AT_REST_REQUIRED'),
      );
    });

    test('blocked when required metadata missing', () {
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: true)
              .copyWith(metadata: const {});
      final decision = evaluator.evaluate(
        descriptor: descriptor,
        criteria: CloudTestFixtures.promotionCriteria(),
      );
      expect(decision.approved, isFalse);
      expect(
        decision.issues.map((e) => e.code),
        contains('CLOUD_REQUIRED_METADATA_MISSING'),
      );
    });

    test('rejected when staging is disabled', () {
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: false);
      final decision = evaluator.evaluate(
        descriptor: descriptor,
        criteria: CloudTestFixtures.promotionCriteria(),
      );
      expect(decision.status, CloudPromotionStatus.rejected);
    });
  });
}
