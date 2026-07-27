import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';

void main() {
  group('CloudGovernanceIntegration', () {
    const evaluator = PersistentArtifactCloudStagingGovernanceEvaluator();
    final baseCriteria = CloudTestFixtures.promotionCriteria();

    test('bloqueia quando stagingEligible=false', () {
      final decision = evaluator.evaluate(
        descriptor: CloudTestFixtures.backendDescriptor(stagingEligible: false),
        criteria: baseCriteria,
      );
      expect(decision.approved, isFalse);
    });

    test('aprova com descriptor elegível', () {
      final descriptor = CloudTestFixtures.backendDescriptor(
        stagingEligible: true,
      ).copyWith(metadata: const {'owner': 'platform'});
      final decision =
          evaluator.evaluate(descriptor: descriptor, criteria: baseCriteria);
      expect(decision.status, isNot(CloudPromotionStatus.rejected));
    });

    for (final mode in CloudReplicationMode.values) {
      test('execução com replication ${mode.name}', () {
        final descriptor = CloudTestFixtures.backendDescriptor(
          stagingEligible: true,
        ).copyWith(
          replication: CloudTestFixtures.replication().copyWith(mode: mode),
          metadata: const {'owner': 'platform'},
        );
        final decision = evaluator.evaluate(
          descriptor: descriptor,
          criteria: baseCriteria.copyWith(requiredReplicationMode: mode),
        );
        expect(decision.criteriaId, 'criteria-1');
      });
    }
  });
}
