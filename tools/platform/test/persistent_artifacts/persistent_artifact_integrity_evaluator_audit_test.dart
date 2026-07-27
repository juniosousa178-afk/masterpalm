import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('Persistent Artifact integrity evaluator audit', () {
    test('integrity evaluator can be instantiated', () {
      const evaluator = PersistentArtifactIntegrityEvaluator();
      expect(evaluator, isNotNull);
    });

    test('policy evaluators aggregate integrity evaluator by default', () {
      const evaluators = PersistentArtifactPolicyEvaluators();
      expect(evaluators.integrity, isA<PersistentArtifactIntegrityEvaluator>());
    });

    test('integrity operation uses engine status semantics', () {
      final result = const PersistentArtifactEngine().evaluateOperation(
        request: fixtureEvaluationRequest(
          evaluationId: 'integrity-audit',
        ).copyWith(
          operationRequest: fixtureOperationRequest(subjects: const []),
        ),
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.status, PersistentArtifactOperationStatus.partial);
    });
  });
}
