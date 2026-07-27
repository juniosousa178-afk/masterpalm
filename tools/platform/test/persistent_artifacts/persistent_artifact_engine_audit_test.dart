import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('Persistent Artifact engine audit', () {
    const engine = PersistentArtifactEngine();

    test('engine returns succeeded when subjects are present', () {
      final result = engine.evaluateOperation(
        request: fixtureEvaluationRequest(),
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
      expect(result.artifactResults, hasLength(1));
    });

    test('engine returns partial when no subjects exist', () {
      final request = fixtureEvaluationRequest().copyWith(
        operationRequest: fixtureOperationRequest(subjects: const []),
      );
      final result = engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.status, PersistentArtifactOperationStatus.partial);
    });

    test('engine result id is deterministic for evaluation id', () {
      final result = engine.evaluateOperation(
        request: fixtureEvaluationRequest(evaluationId: 'engine-audit'),
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.resultId, 'op:engine-audit');
    });
  });
}
