import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('PersistentArtifactEngine', () {
    test('gera resultado com artifactResults', () {
      final engine = const PersistentArtifactEngine();
      final result = engine.evaluateOperation(
        request: fixtureEvaluationRequest(),
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.artifactResults, isNotEmpty);
    });

    test('status partial quando sem subjects', () {
      final req = fixtureEvaluationRequest().copyWith(
        operationRequest: fixtureOperationRequest(subjects: const []),
      );
      final result = const PersistentArtifactEngine().evaluateOperation(
        request: req,
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.status, PersistentArtifactOperationStatus.partial);
    });

    for (var i = 0; i < 4; i++) {
      test('engine cenario $i', () {
        final req = fixtureEvaluationRequest(
          evaluationId: 'eval-$i',
        );
        final result = const PersistentArtifactEngine().evaluateOperation(
          request: req,
          material: const CollectedPersistentArtifactMaterial(),
        );
        expect(result.resultId, contains('eval-$i'));
      });
    }
  });
}
