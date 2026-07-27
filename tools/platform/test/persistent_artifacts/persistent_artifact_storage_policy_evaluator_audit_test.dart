import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact storage policy evaluator audit', () {
    test('storage evaluator is wired in policy evaluators', () {
      const evaluators = PersistentArtifactPolicyEvaluators();
      expect(
          evaluators.storage, isA<PersistentArtifactStoragePolicyEvaluator>());
    });

    test('provider evaluate returns operation result for storage path',
        () async {
      final result = await evaluatePassingSnapshot();
      expect(result.operationResult!.status,
          PersistentArtifactOperationStatus.succeeded);
    });

    test('storage semantics remain declarative without backend writes',
        () async {
      final stack = createTestStack();
      final result = await stack.provider.evaluate(passingScenarioRequest());
      expect(result.metadata['declarativeBoundaries'],
          contains('no-physical-storage'));
    });
  });
}
