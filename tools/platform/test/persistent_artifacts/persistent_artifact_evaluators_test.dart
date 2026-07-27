import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('PersistentArtifactEvaluators', () {
    test('deletion evaluator bloqueia legal hold sem force', () {
      final result = const PersistentArtifactDeletionEvaluator().evaluate(
        request:
            fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
        force: false,
      );
      expect(result.status, PersistentArtifactOperationStatus.blocked);
    });

    test('deletion evaluator bloqueia legal hold com force', () {
      final result = const PersistentArtifactDeletionEvaluator().evaluate(
        request:
            fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
        force: true,
      );
      expect(result.status, PersistentArtifactOperationStatus.blocked);
    });

    test('deletion evaluator permite quando sem legal hold', () {
      final result = const PersistentArtifactDeletionEvaluator().evaluate(
        request: fixtureEvaluationRequest(),
        force: true,
      );
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('policy evaluators expostos', () {
      const evaluators = PersistentArtifactPolicyEvaluators();
      expect(evaluators.integrity, isNotNull);
      expect(evaluators.storage, isNotNull);
      expect(evaluators.retention, isNotNull);
      expect(evaluators.replication, isNotNull);
    });

    for (var i = 0; i < 4; i++) {
      test('avaliador cenario $i', () {
        final result = const PersistentArtifactDeletionEvaluator().evaluate(
          request: fixtureEvaluationRequest(
            metadata: {'legalHold': i.isEven ? 'true' : 'false'},
          ),
          force: i.isOdd,
        );
        expect(result.metadata.containsKey('force'), isTrue);
      });
    }
  });
}
